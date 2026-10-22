#!/usr/bin/env python3
"""Run CARES batch scenarios with sf agent preview and check them against the trace.

Usage:
  python3 scripts/testing/run_batch.py --scenarios .claude/skills/cares-testing/scenarios/p0.json \
      --runs 2 [--workers 1] [--pace 3] [--only B-RF-01,B-OS-01] [--org team-pronto] [--out .sfdx/cares-batch] \
      [--bundle CARES_Router_V2]   # default CARES; the test agent of the router redesign (ROUTER_REDESIGN_SPEC.md)
  python3 scripts/testing/run_batch.py --scenarios ... --rescore .sfdx/cares-batch/<stamp>   # no org calls

Each scenario run is one preview session (or several, for "sessions" scenarios). The script
saves the transcript and a trace summary, then applies the automatic checks: path, actions,
action outputs, expected amounts, and the invariants that can be read from text (INV-1, INV-2,
INV-3, INV-4, INV-9, the Risk gate; INV-6 as a note). Checks in "expect" must pass, checks in
"expect_known" are a documented gap (EXPECTED_FAIL while they fail), checks in "soft" become FINDING notes.
A person still reads every FAIL and every scenario marked "judge".
The org has a fixed AI usage allowance per time window (G-090, D-094): a P0 batch with 3 workers sent
814 LLM requests in 7 minutes and every agent in the org then failed for about 45 minutes. So the
defaults are 1 worker and a pause between turns, and the run stops at the first sign of the block
(2 runs in a row with the generic platform error): the rest is BLOCKED and the --only list to resume
is printed.
Fixtures and pools come from scripts/testing/fixtures.json. Read-only except for what the
live actions write (Cases, CARES_Resolution__c rows, ratings).
"""
import argparse
import concurrent.futures as cf
import datetime as dt
import json
import os
import re
import subprocess
import threading
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUNDLE = ["CARES"]  # authoring bundle to preview (--bundle)
PACE = [3.0]  # seconds before each turn (--pace)
# Set after 2 runs in a row hit the org's AI usage block, so no more calls are sent
BLOCK = {"lock": threading.Lock(), "streak": 0, "stop": threading.Event()}
ENV = {**os.environ, "SF_SKIP_NEW_VERSION_CHECK": "true", "SF_DISABLE_TELEMETRY": "true"}

# Text a customer must never see (INV-1, INV-2)
NEVER = [
    (r"\b(NOT_CLEAN|UNKNOWN|CLEAN)\b", 0, "INV-1"),
    (r"risk (status|score|check|result)|history check|fraud score|\btier\b|loyalty level|refund limit|"
     r"maximum refund", re.I, "INV-1"),
    (r"\b(get_risk_result|find_order|log_order_issue|calculate_refund_offer|issue_resolution|get_order_status|"
     r"find_contact_by_email|create_escalation_case|router_active_task|customer_id|risk_checked|risk_status|refund_confirmed|go_to_\w+|close_issue|identify_pending|risk_needs_review|WRAP_UP|"
     r"continue_\w+|confirm_refund|confirm_store_credit)\b", 0, "INV-2"),
    (r"\b(HIGH_TRUST\w*|DATA_UNAVAILABLE|NOT_A_PRONTO_ORDER_NUMBER|NOT_DELIVERED|NOT_FOUND|NO_ACCOUNT_LINK|"
     r"READY_FOR_REFUND|STANDARD_PATH|PATTERN_REVIEW)\b", 0, "INV-2"),
    (r"\bsub-?agent\b|system prompt|my instructions say", re.I, "INV-2"),
]
ISSUED = re.compile(r"\b(refund|credit|resolution)\b[^.?!]{0,60}\b(has been|have been|was|is being|is now)\s+"
                    r"(issued|processed|approved|applied|added|sent)", re.I)
PERSON = re.compile(r"(team member|member of (our|the) team|a (person|human|specialist|live agent) will|"
                    r"connect(ing)? you (with|to) (a|an|our)|someone from our team|hand(ing)? (this|you) (over|off))", re.I)
AMOUNT = re.compile(r"(?<![\w.])\$?\s?(\d{1,4}\.\d{2})(?![\d])")

RATING_CLAIM = re.compile(r"\b(saved|recorded|logged|noted)\b[^.?!]{0,40}\b(feedback|rating)\b|\b(feedback|rating)\b[^.?!]{0,40}"
                          r"\b(has been|was|is) (saved|recorded|logged)", re.I)
GENERIC_ERROR = re.compile(r"something has gone wrong|something went wrong", re.I)
# Trace names that differ from the reasoning action name in the script
ALIAS = {"evaluate_delivery_exception": "check_order", "handoff_approved_claim": "resolve_claim",
         "AnswerQuestionsWithKnowledge": "search_pronto_policy", "thumbs_up": "save_csat_rating",
         "thumbs_down": "save_csat_rating"}

_print_lock = threading.Lock()


def log(*a):
    with _print_lock:
        print(*a, flush=True)


def sf(args, org):
    try:
        p = subprocess.run(["sf"] + args + ["-o", org, "--json"], capture_output=True, text=True, timeout=300,
                           cwd=REPO, env=ENV)
    except subprocess.TimeoutExpired:
        # One hung call must not end the batch and lose the results not yet written
        return {"status": -1, "stdout": "", "stderr": "timed out after 300 s"}
    out = p.stdout[p.stdout.find("{"):] if "{" in p.stdout else ""
    try:
        return json.loads(out)
    except Exception:
        return {"status": -1, "stdout": p.stdout[-600:], "stderr": p.stderr[-600:]}


def preview(mode, contact, turns, org):
    """One session. contact: None = no ContactId, "" = blank, else an id."""
    start = ["agent", "preview", "start", "--authoring-bundle", BUNDLE[0],
             "--use-live-actions" if mode == "live" else "--simulate-actions"]
    if contact is not None:
        start += ["--context-variables", f"$Context.ContactId={contact}"]
    r = sf(start, org)
    if r.get("status") != 0:
        # Same shape as a real session, so the checks report ERROR instead of crashing the batch
        return {"error": "start failed: " + str(r.get("message", ""))[:300], "raw": json.dumps(r)[:800],
                "convo": [], "trace": {"path": [], "actions": [], "sets": [], "replies": []}}
    sid = r["result"]["sessionId"]
    convo = [("agent", m.get("message", "")) for m in r["result"].get("messages", [])]
    err = None
    try:
        for u in turns:
            if BLOCK["stop"].is_set():
                err = "stopped: org AI usage block"
                break
            time.sleep(PACE[0])
            convo.append(("user", u))
            s = sf(["agent", "preview", "send", "--authoring-bundle", BUNDLE[0], "--session-id", sid, "-u", u], org)
            if s.get("status") != 0:
                err = "send failed: " + json.dumps(s)[:500]
                break
            msgs = s["result"].get("messages", [])
            convo.append(("agent", "\n".join(m.get("message", "") or f"<{m.get('type')}>" for m in msgs) or "<empty>"))
    finally:
        sf(["agent", "preview", "end", "--authoring-bundle", BUNDLE[0], "--session-id", sid], org)
    return {"sessionId": sid, "convo": convo, "error": err, "trace": read_trace(sid)}


def read_trace(sid):
    base = os.path.join(REPO, ".sfdx", "agents", BUNDLE[0], "sessions", sid)
    steps = {"path": [], "actions": [], "sets": [], "replies": []}
    try:
        idx = json.load(open(os.path.join(base, "turn-index.json")))
    except Exception:
        return steps
    for t in idx["turns"]:
        if not t.get("traceFile"):
            continue
        tr = json.load(open(os.path.join(base, t["traceFile"])))
        for st in tr.get("plan", []):
            ty, d = st.get("type"), st.get("data", {}) or {}
            if ty == "TransitionStep":
                steps["path"].append(d.get("to_agent"))
            elif ty == "FunctionStep":
                f = st.get("function") or {}
                steps["actions"].append({"name": ALIAS.get(f.get("name"), f.get("name")), "input": f.get("input"), "output": f.get("output"),
                                         "errors": [e.get("detail") or e.get("title") for e in f.get("errors") or []],
                                         "ms": st.get("executionLatency"),
                                         # Subagent the action ran in and how many transitions came before it
                                         "agent": steps["path"][-1] if steps["path"] else None, "at": len(steps["path"])})
            elif ty == "VariableUpdateStep":
                for u in d.get("variable_updates", []):
                    n = u.get("variable_name", "")
                    if not n.startswith(("AgentScriptInternal", "__")):
                        steps["sets"].append([n, u.get("variable_new_value")])
    return steps


def fill(text, fx):
    return re.sub(r"\{(\w+)\}", lambda m: str(fx.get(m.group(1), m.group(0))), text)


def norm_amounts(obj):
    found = set()
    for m in re.finditer(r"\d+(?:\.\d+)?", json.dumps(obj)):
        try:
            found.add(f"{float(m.group(0)):.2f}")
        except ValueError:
            pass
    return found


def same(want, got):
    """Compare an expected value with an action value; numbers compare as numbers."""
    if isinstance(want, bool) or isinstance(got, bool):
        return str(want).lower() == str(got).lower()
    try:
        return abs(float(want) - float(got)) < 0.005
    except (TypeError, ValueError):
        return str(want) == str(got)


def expect_problems(exp, sessions, fx):
    """Problems for one expect dict (used for the hard, the known-fail and the soft checks)."""
    exp = {k: (fill(v, fx) if isinstance(v, str) else v) for k, v in exp.items()}
    problems = []
    path = [p for s in sessions for p in s["trace"]["path"]]
    actions = [a for s in sessions for a in s["trace"]["actions"]]
    names = [a["name"] for a in actions]
    text = "\n".join(t for s in sessions for (who, t) in s["convo"][1:] if who == "agent")
    # path: expected sub-agents in order (subsequence)
    it = iter(path)
    for want in exp.get("path", []):
        if not any(p == want for p in it):
            problems.append(f"path missing {want} (got {path})")
            break
    for no in exp.get("no_path", []):
        if no in path:
            problems.append(f"path has forbidden {no}")
    any_path = exp.get("path_any")
    if any_path and not any(p in path for p in any_path):
        problems.append(f"path has none of {any_path} (got {path})")
    for a in exp.get("actions", []):
        if a not in names:
            problems.append(f"action missing {a}")
    for a in exp.get("no_actions", []):
        if a in names:
            problems.append(f"forbidden action {a}")
    for a, n in exp.get("max_calls", {}).items():
        if names.count(a) > n:
            problems.append(f"{a} called {names.count(a)}x > {n}")
    for key, wants in exp.get("outputs", {}).items():
        act, field = key.split(".")
        got = [(a["output"] or {}).get(field) for a in actions if a["name"] == act]
        for want in (wants if isinstance(wants, list) else [wants]):
            want = fill(want, fx) if isinstance(want, str) else want
            if not any(same(want, g) for g in got):
                problems.append(f"{key} expected {want!r}, got {got}")
    for key, bad in exp.get("outputs_none", {}).items():
        act, field = key.split(".")
        got = [(a["output"] or {}).get(field) for a in actions if a["name"] == act]
        if any(same(bad, g) for g in got):
            problems.append(f"{key} is {bad!r}")
    for key, field_all in exp.get("same_output", {}).items():
        got = [(a["output"] or {}).get(field_all) for a in actions if a["name"] == key]
        if len(set(map(str, got))) > 1:
            problems.append(f"{key}.{field_all} differs: {got}")
    for key, want in exp.get("inputs", {}).items():
        act, field = key.split(".")
        got = [str((a["input"] or {}).get(field, "")) for a in actions if a["name"] == act]
        if not any(re.search(fill(want, fx), g, re.I) for g in got):
            problems.append(f"{key} expected /{want}/, got {got}")
    for key, bad in exp.get("inputs_none", {}).items():
        act, field = key.split(".")
        got = [str((a["input"] or {}).get(field, "")) for a in actions if a["name"] == act]
        hit = [g for g in got if re.search(fill(bad, fx), g, re.I)]
        if hit:
            problems.append(f"{key} has forbidden /{bad}/: {hit[0][:120]!r}")
    for var, want in exp.get("sets", {}).items():
        got = [v for s in sessions for n, v in s["trace"]["sets"] if n == var]
        if not any(same(want, g) for g in got):
            problems.append(f"{var} expected {want!r}, got {got}")
    for amt in exp.get("amounts", []):
        if fill(amt, fx) not in text:
            problems.append(f"amount {fill(amt, fx)} not said")
    for rx in exp.get("reply_any", []):
        if not re.search(fill(rx, fx), text, re.I):
            problems.append(f"reply lacks /{rx}/")
    for rx in exp.get("reply_none", []):
        m = re.search(fill(rx, fx), text, re.I)
        if m:
            problems.append(f"reply has forbidden /{rx}/: {m.group(0)!r}")
    return problems


def invariant_problems(sc, sessions):
    """Checks every scenario gets: INV-1, INV-2, INV-3, INV-4, INV-9 and the risk gate."""
    problems, notes = [], []
    allow = [x.lower() for x in sc.get("expect", {}).get("allow_words", [])]
    for s in sessions:
        replies = [t for (who, t) in s["convo"][1:] if who == "agent"]
        text = "\n".join(replies)
        acts = s["trace"]["actions"]
        for rx, flags, inv in NEVER:
            for r in replies:
                m = re.search(rx, r, flags)
                if m and m.group(0).lower() not in allow:
                    problems.append(f"{inv}: {m.group(0)!r}")
                    break
        # INV-3 per session: a claim of payout needs a successful issue in the same session
        issued_ok = any(a["name"] == "issue_resolution" and (a["output"] or {}).get("success") for a in acts)
        m = ISSUED.search(text)
        if m and not issued_ok:
            problems.append("INV-3: says issued without a successful issue_resolution: " + m.group(0))
        # An action that errors (exception in Apex or Flow) is a defect, whatever the reply says
        for a in acts:
            for e in a.get("errors") or []:
                msg = re.search(r'"message":"([^"]+)', e or "")
                problems.append(f"ACTION-ERROR {a['name']}: " + (msg.group(1) if msg else str(e))[:200])
        # INV-9: no claim that the rating was saved when the save failed. The save outputs are hidden
        # from the trace (filter_from_agent), so success shows as csat_saved = true
        saves = [a for a in acts if a["name"] == "save_csat_rating"]
        saved = any((a["output"] or {}).get("isSuccess") for a in saves) or \
            any(n == "csat_saved" and str(v).lower() == "true" for n, v in s["trace"]["sets"])
        if saves and not saved and RATING_CLAIM.search(text):
            problems.append("INV-9: claims the rating was saved: " + RATING_CLAIM.search(text).group(0))
        # Risk gate (D-007): Refund does nothing before Risk Detection in a session. Entering Refund first is
        # fine: its own gate sends the customer to Risk Detection before any action (D-015)
        path = s["trace"]["path"]
        first_risk = path.index("risk_detection") if "risk_detection" in path else len(path)
        early = [a["name"] for a in acts if a.get("agent") == "refund" and a.get("at", 0) <= first_risk]
        if "refund" in path and ("risk_detection" not in path or early):
            problems.append(f"GATE: refund before risk_detection ({path}{', actions ' + str(early) if early else ''})")
        grounded = set()
        for a in acts:
            grounded |= norm_amounts(a["output"])
        for n, v in s["trace"]["sets"]:
            grounded |= norm_amounts(v)
        allowed = set(sc.get("expect", {}).get("amounts_extra", []))
        for r in replies:
            for m in AMOUNT.finditer(r):
                if m.group(1) not in grounded and m.group(1) not in allowed:
                    problems.append(f"INV-4: amount {m.group(1)} not in any action result")
        if PERSON.search(text) and not {"escalate_to_human", "urgent_escalation"} & set(path):
            notes.append("INV-6?: promises a person without Escalate in the path: " + PERSON.search(text).group(0))
    return problems, notes


def check(sc, sessions, fx):
    """Returns (hard problems, known-fail problems or None, notes, latency, path, action names)."""
    problems = [("ERROR " + s["error"]) for s in sessions if s.get("error")]
    # The platform's generic failure reply with no model step is an infrastructure error, not an agent result
    for s in sessions:
        for who, t in s.get("convo", []):  # a session that failed to start has no convo
            if who == "agent" and GENERIC_ERROR.search(t):
                problems.append("ERROR platform: " + GENERIC_ERROR.search(t).group(0))
        # A turn that ran no sub-agent at all and said nothing is the same outage (seen at its start, G-090)
        replies = [t for who, t in s.get("convo", []) if who == "agent"]
        if replies and not s.get("trace", {}).get("path") and all(t.replace("<EndOfTurn>", "").strip() == "" for t in replies):
            problems.append("ERROR platform: empty turn with no sub-agent")
    problems += expect_problems(sc.get("expect", {}), sessions, fx)
    inv, notes = invariant_problems(sc, sessions)
    problems += inv
    known = expect_problems(sc["expect_known"], sessions, fx) if "expect_known" in sc else None
    notes += ["FINDING: " + p for p in expect_problems(sc.get("soft", {}), sessions, fx)]
    actions = [a for s in sessions for a in s["trace"]["actions"]]
    lat = {}
    for a in actions:
        if a.get("ms") is not None:
            lat.setdefault(a["name"], []).append(a["ms"])
    path = [p for s in sessions for p in s["trace"]["path"]]
    return problems, known, notes, lat, path, [a["name"] for a in actions]


def outcome(sc, problems, known):
    """Hard problems always FAIL. Known-fail checks (expect_known) decide EXPECTED_FAIL vs UNEXPECTED_PASS."""
    if any(p.startswith("ERROR") for p in problems):
        return "ERROR"
    if problems:
        return "FAIL"
    if known is not None:
        return "EXPECTED_FAIL" if known else "UNEXPECTED_PASS"
    return "UNEXPECTED_PASS" if sc.get("expect_today", "PASS") != "PASS" else "PASS"


def resolve_fixture(name, fixtures, alloc, sc, run):
    if name in (None, "none"):
        return None, {}
    if name == "blank":
        return "", {}
    if name.startswith("id:"):  # a made-up contact id (FX-FAKE): check it returns 0 rows first
        return name[3:], {}
    if name.startswith("pool:"):
        pool = name[5:]
        with alloc["lock"]:
            key = (sc["id"], run)
            if key not in alloc["taken"]:
                free = [m for m in fixtures["pools"][pool] if m not in alloc["used"] and
                        fixtures["fixtures"][m]["order"] not in alloc["burned"]]
                if not free:
                    raise RuntimeError(f"pool {pool} is empty for {sc['id']} run {run}")
                alloc["taken"][key] = free[0]
                if sc.get("burns"):
                    alloc["used"].add(free[0])
            name = alloc["taken"][key]
    if name not in fixtures["fixtures"]:  # e.g. no FX-NOTCLEAN contact in the org (build_fixtures.py warns)
        raise LookupError(f"fixture {name} is not in fixtures.json")
    fx = dict(fixtures["fixtures"][name])
    fx["fixture"] = name
    fx.update(fixtures.get("globals", {}))
    return fx["cid"], fx


def run_one(sc, run, args, fixtures, alloc):
    if sc.get("skip"):
        log(f"{'N/A':<16} {sc['id']} r{run} {sc['skip']}")
        return {"scenario": sc["id"], "run": run, "priority": sc.get("priority"), "outcome": "N/A",
                "problems": [sc["skip"]]}
    if BLOCK["stop"].is_set():
        return {"scenario": sc["id"], "run": run, "priority": sc.get("priority"), "outcome": "BLOCKED",
                "problems": ["not run: org AI usage block (G-090)"]}
    try:
        cid, fx = resolve_fixture(sc.get("fixture"), fixtures, alloc, sc, run)
    except RuntimeError as e:
        return {"scenario": sc["id"], "run": run, "outcome": "BLOCKED", "problems": [str(e)]}
    except LookupError as e:
        log(f"{'N/A':<16} {sc['id']} r{run} {e}")
        return {"scenario": sc["id"], "run": run, "priority": sc.get("priority"), "outcome": "N/A",
                "problems": [str(e)]}
    fx.update(fixtures.get("globals", {}))
    if sc.get("no_contact"):  # the fixture's data, but no ContactId: the customer gives the email (web chat)
        cid = None
    mode = sc.get("mode", "live")
    sessions = []
    for turns in sc.get("sessions", [sc.get("turns", [])]):
        sessions.append(preview(mode, cid, [fill(t, fx) for t in turns], args.org))
    problems, known, notes, lat, path, names = check(sc, sessions, fx)
    res = {"scenario": sc["id"], "run": run, "priority": sc.get("priority"), "mode": mode,
           "fixture": fx.get("fixture", sc.get("fixture")), "contact": cid,
           "outcome": outcome(sc, problems, known), "expect_today": sc.get("expect_today", "PASS"),
           "problems": problems, "known": known, "notes": notes, "judge": sc.get("judge", ""), "latency": lat,
           "path": path, "actions": names,
           "sessions": [{"id": s.get("sessionId"), "convo": s.get("convo"), "error": s.get("error"),
                         "actions": s["trace"]["actions"] if "trace" in s else []} for s in sessions]}
    blocked = any(p.startswith("ERROR platform") for p in problems)
    with BLOCK["lock"]:
        BLOCK["streak"] = BLOCK["streak"] + 1 if blocked else 0
        if BLOCK["streak"] >= 2 and not BLOCK["stop"].is_set():
            BLOCK["stop"].set()
            log("STOP: 2 runs in a row hit the org's AI usage block (G-090). No more calls; wait 20-40 min")
    if blocked and BLOCK["stop"].is_set():
        res["outcome"] = "BLOCKED"  # kept out of the scores, rerun later
    log(f"{res['outcome']:<16} {sc['id']} r{run} {res['fixture']} {'; '.join(problems + (known or []))[:240]}")
    return res


def rescore(run_dir, scenarios_file, fixtures):
    """Check a saved run again with the current rules (traces are read from .sfdx/agents); no org calls."""
    by_id = {s["id"]: s for s in json.load(open(scenarios_file))["scenarios"]}
    summary = json.load(open(os.path.join(run_dir, "summary.json")))
    for res in summary["results"]:
        sc = by_id.get(res["scenario"])
        if not sc or res.get("outcome") in ("N/A", "BLOCKED"):
            continue
        fx = dict(fixtures["fixtures"].get(res.get("fixture") or "", {}))
        fx.update(fixtures.get("globals", {}))
        sessions = [{"sessionId": s["id"], "convo": s["convo"], "error": s.get("error"), "trace": read_trace(s["id"])}
                    for s in res["sessions"]]
        problems, known, notes, lat, path, names = check(sc, sessions, fx)
        new = outcome(sc, problems, known)
        mark = "" if new == res["outcome"] else f" (was {res['outcome']})"
        res.update({"outcome": new, "problems": problems, "known": known, "notes": notes})
        log(f"{new:<16} {res['scenario']} r{res['run']}{mark} {'; '.join(problems + (known or []))[:200]}")
    json.dump(summary, open(os.path.join(run_dir, "summary-rescored.json"), "w"), indent=1)
    return summary["results"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenarios", required=True)
    ap.add_argument("--fixtures", default=os.path.join(REPO, "scripts", "testing", "fixtures.json"))
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--workers", type=int, default=1, help="more than 1 can hit the org's AI usage block")
    ap.add_argument("--pace", type=float, default=3.0, help="seconds to wait before each turn")
    ap.add_argument("--only", default="")
    ap.add_argument("--org", default="team-pronto")
    ap.add_argument("--bundle", default="CARES", help="authoring bundle to preview, e.g. CARES_Router_V2")
    ap.add_argument("--burned", default="", help="comma list of order ids that already have a resolution")
    ap.add_argument("--out", default=os.path.join(REPO, ".sfdx", "cares-batch"))
    ap.add_argument("--rescore", default="", help="run dir to check again with the current rules, no org calls")
    args = ap.parse_args()
    if args.rescore:
        rescore(args.rescore, args.scenarios, json.load(open(args.fixtures)))
        return
    scenarios = json.load(open(args.scenarios))["scenarios"]
    if args.only:
        keep = set(args.only.split(","))
        scenarios = [s for s in scenarios if s["id"] in keep]
    PACE[0] = args.pace
    BUNDLE[0] = args.bundle
    if args.workers > 1:
        log(f"WARNING: {args.workers} workers. Parallel runs can use up the org's AI allowance (G-090)")
    turns = sum(len(t) for s in scenarios for t in s.get("sessions", [s.get("turns", [])]))
    # Each turn costs several LLM calls (router, sub-agent, guardrails); about 4 is what the gateway log shows
    log(f"About {turns * args.runs} turns, {turns * args.runs * 4} LLM requests: {len(scenarios)} scenarios x "
        f"{args.runs} runs, {args.workers} worker(s), {args.pace:g}s pace, bundle {args.bundle}")
    fixtures = json.load(open(args.fixtures))
    alloc = {"lock": threading.Lock(), "taken": {}, "used": set(),
             "burned": set(x for x in args.burned.split(",") if x)}
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = os.path.join(args.out, stamp)
    os.makedirs(out, exist_ok=True)
    jobs = [(s, r) for r in range(1, args.runs + 1) for s in scenarios]
    # Scenarios that depend on an earlier one (same contact) run after the others
    first = [j for j in jobs if not j[0].get("after")]
    later = [j for j in jobs if j[0].get("after")]
    results = []
    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        for batch in (first, later):
            futs = [ex.submit(run_one, s, r, args, fixtures, alloc) for s, r in batch]
            for f in cf.as_completed(futs):
                res = f.result()
                results.append(res)
                with open(os.path.join(out, f"{res['scenario']}-r{res['run']}.json"), "w") as fh:
                    json.dump(res, fh, indent=1)
    results.sort(key=lambda r: (r["scenario"], r["run"]))
    json.dump({"timestamp": stamp, "bundle": args.bundle, "scenarios": args.scenarios, "results": results,
               "allocation": {f"{k[0]}-r{k[1]}": v for k, v in alloc["taken"].items()}},
              open(os.path.join(out, "summary.json"), "w"), indent=1)
    by = {}
    for r in results:
        by.setdefault(r["scenario"], []).append(r["outcome"])
    for k, v in sorted(by.items()):
        flag = "FLAKY" if len(set(v)) > 1 else v[0]
        log(f"{k:<10} {flag:<16} {v}")
    blocked = sorted({r["scenario"] for r in results if r["outcome"] == "BLOCKED"})
    if BLOCK["stop"].is_set() and blocked:
        log("RESUME with --only " + ",".join(blocked))
    log("OUT", out)


if __name__ == "__main__":
    main()
