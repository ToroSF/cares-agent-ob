"""Normalize a CARES Testing Center run into the dashboard shape (docs/metrics/data/testing-center/).

Usage: python3 -I normalize.py <spec.yaml> <raw_results.json> <out.json> <agentVersion>
No third-party deps (spec comments are parsed line by line).
"""
import ast
import html
import json
import re
import sys

spec_path, raw_path, out_path, agent_version = sys.argv[1:5]
run_path = sys.argv[5] if len(sys.argv) > 5 else None

# ---- case metadata from spec comments: "# <id> | <persona> | <tags>" before "- utterance:"
meta, pending = [], None
expected = []  # per case: (topic or None, actions list or None)
cur = None
for line in open(spec_path, encoding="utf-8"):
    m = re.match(r"\s*#\s*([A-Z]{1,3}-[A-Z0-9-]+)\s*\|\s*([^|]+)\|\s*(.+)$", line)
    if m:
        pending = {"id": m.group(1).strip(), "persona": m.group(2).strip(),
                   "tags": [t.strip() for t in m.group(3).split(",") if t.strip()]}
        continue
    if re.match(r"\s*- utterance:", line):
        meta.append(pending or {"id": None, "persona": None, "tags": []})
        pending = None
        cur = {"topic": None, "actions": None}
        expected.append(cur)
        continue
    if cur is not None:
        mt = re.match(r"\s{4}expectedTopic:\s*(\S+)", line)
        if mt:
            cur["topic"] = mt.group(1)
        ma = re.match(r"\s{4}expectedActions:\s*\[(.*)\]", line)
        if ma:
            cur["actions"] = [a.strip() for a in ma.group(1).split(",") if a.strip()]

raw = json.load(open(raw_path, encoding="utf-8"))
res = raw["result"]
cases_raw = sorted(res["testCases"], key=lambda c: c["testNumber"])
assert len(cases_raw) == len(meta), (len(cases_raw), len(meta))

EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
CARD = re.compile(r"\b(?:\d[ -]?){12,19}\b")


def scrub(text, n=200):
    t = html.unescape(text or "")
    t = EMAIL.sub("[email]", t)
    t = CARD.sub("[card]", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t if len(t) <= n else t[: n - 3].rstrip() + "..."


def parse_actions(s):
    s = html.unescape(s or "[]")
    try:
        v = ast.literal_eval(s)
        return list(v) if isinstance(v, (list, tuple)) else [str(v)]
    except Exception:
        return [a.strip(" '\"") for a in s.strip("[]").split(",") if a.strip()]


def verdict(r):
    if r is None:
        return None
    if r.get("result") == "PASS":
        return True
    if r.get("result") == "FAILURE":
        return False
    return "ERROR"


QUALITY = ["output_validation", "coherence", "completeness"]
by_metric = {m: {"passed": 0, "failed": 0, "error": 0, "notApplicable": 0}
             for m in ["topic_assertion", "actions_assertion"] + QUALITY}
by_metric_raw = {m: {"passed": 0, "failed": 0, "error": 0} for m in by_metric}
lat = []
out_cases = []
totals = {"cases": 0, "passed": 0, "failed": 0, "error": 0}

for tc, md, ex in zip(cases_raw, meta, expected):
    rs = {r["name"]: r for r in tc.get("testResults", [])}
    gd = tc.get("generatedData", {})
    v = {m: verdict(rs.get(m)) for m in by_metric}
    for m, val in v.items():
        k = "passed" if val is True else "failed" if val is False else "error"
        by_metric_raw[m][k] += 1
    # declared-only view for routing/action assertions
    topic_pass = v["topic_assertion"] if ex["topic"] else None
    action_pass = v["actions_assertion"] if ex["actions"] else None
    for m, val in (("topic_assertion", topic_pass), ("actions_assertion", action_pass)):
        if val is None:
            by_metric[m]["notApplicable"] += 1
        else:
            by_metric[m]["passed" if val is True else "failed" if val is False else "error"] += 1
    for m in QUALITY:
        val = v[m]
        by_metric[m]["passed" if val is True else "failed" if val is False else "error"] += 1
    latency = rs.get("output_latency_milliseconds", {}).get("score")
    if isinstance(latency, (int, float)):
        lat.append(latency)
    declared = [v["output_validation"], topic_pass, action_pass]
    declared = [d for d in declared if d is not None]
    totals["cases"] += 1
    if tc.get("status") != "COMPLETED" or "ERROR" in declared:
        status = "error"
    elif all(d is True for d in declared):
        status = "passed"
    else:
        status = "failed"
    totals[status] += 1
    out_cases.append({
        "id": md["id"],
        "testNumber": tc["testNumber"],
        "persona": md["persona"],
        "subagentExpected": ex["topic"],
        "subagentActual": gd.get("topic"),
        "actionsExpected": ex["actions"] or [],
        "actionsActual": parse_actions(gd.get("actionsSequence")),
        "outcomePass": v["output_validation"],
        "topicPass": topic_pass,
        "actionPass": action_pass,
        "casePass": status == "passed",
        "latencyMs": latency,
        "scores": {m: rs.get(m, {}).get("score") for m in QUALITY},
        "tags": md["tags"],
        "utterance": scrub(tc["inputs"]["utterance"], 400),
        "responseExcerpt": scrub(gd.get("generatedResponse") or gd.get("outcome")),
    })

lat_sorted = sorted(lat)
out = {
    "suite": f"CARES_Baseline_v{agent_version}",
    "agent": "CARES",
    "agentVersion": int(agent_version),
    "subjectVersion": f"v{agent_version}",
    "runAt": res.get("startTime"),
    "runEndedAt": res.get("endTime"),
    # No runId: it is an org record id and this file goes to a public repo
    "identityPath": "anonymous (no contextVariables; ContactId empty)",
    "totals": totals,
    "byMetric": by_metric,
    "byMetricRaw": by_metric_raw,
    "latencyMs": {
        "n": len(lat_sorted),
        "median": lat_sorted[len(lat_sorted) // 2] if lat_sorted else None,
        "p90": lat_sorted[int(len(lat_sorted) * 0.9) - 1] if lat_sorted else None,
        "max": lat_sorted[-1] if lat_sorted else None,
    },
    "targetBehaviorNotInV3": {
        "cases": sum("target_behavior_not_in_v3" in c["tags"] for c in out_cases),
        "passed": sum("target_behavior_not_in_v3" in c["tags"] and c["casePass"] for c in out_cases),
    },
    "notes": [
        "casePass = every declared assertion passes: output_validation always, topic_assertion only if expectedTopic was set, actions_assertion only if expectedActions was set.",
        "byMetric counts topic/action assertions only where the spec declared them (notApplicable otherwise). byMetricRaw is the platform's raw verdict for every case; with no expectation the platform asserts an empty topic / empty action list.",
        "Testing Center reports only real actions (not @utils.transition); before_reasoning runs appear under their definition names.",
        "coherence and completeness are LLM-judged quality metrics, reported but not part of casePass.",
        "Tag target_behavior_not_in_v3: expectation is the policy-branch target (Urgent Escalation, Pronto Help, global card rule); a FAIL on v3 is expected.",
        "Excerpts are HTML-unescaped; emails and card-like digit runs are masked.",
    ],
    "cases": out_cases,
}
json.dump(out, open(out_path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print(json.dumps({k: out[k] for k in ("totals", "byMetric", "latencyMs", "targetBehaviorNotInV3")}, indent=1))
