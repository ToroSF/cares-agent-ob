#!/usr/bin/env python3
"""Collect one team member's repo evidence per Capstone rubric line (rubric-mentor skill).

Read-only. Standard library only. Prints JSON. The skill scores from this output, so the same
repo state always gives the same evidence.

  python3 collect_evidence.py --author "Mateus Curtolo de Goes" --github Mateus-Goes \
      --owns risk-detection [--focus refund] [--no-gh]

Evidence sources: git commits and files (--author), pull requests (--github, needs `gh`),
rows in docs/DECISIONS.md, GAPS.md and RISKS.md (owned by @handle or "<Subagent> owner"),
and docs/TEST_PLAN.md runs. A suggested level (1-4) per rubric line is computed from quality
signals, not volume: commit counts are context only (squash merges and co-authored commits
make volume misleading). Repo evidence alone stops at Practicing; Advanced needs answers.
"""
import argparse
import json
import os
import re
import subprocess
import sys

LINES = {
    "usecase": "Use Case & Business Framing",
    "configure": "Configure",
    "ground": "Ground",
    "risks": "Risks & Safeguards",
    "approach": "Recommended Approach",
    "justification": "Justification & Strategic Communication",
}
LEVELS = {1: "Beginning", 2: "Developing", 3: "Practicing", 4: "Advanced"}
EMPTY = {"", "-", "—", "n/a", "none"}


def run(cmd, cwd):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def repo_root(start):
    out = run(["git", "rev-parse", "--show-toplevel"], start)
    if not out:
        sys.exit("Not inside a git repository")
    return out.strip()


def commits(root, authors):
    """Non-merge commits by any alias: {hash: {date, subject, files}}."""
    found = {}
    for author in authors:
        out = run(["git", "log", "--no-merges", "--author=" + author, "--date=short",
                   "--format=@@%H|%ad|%s", "--name-only"], root) or ""
        current = None
        for line in out.splitlines():
            if line.startswith("@@"):
                h, date, subject = line[2:].split("|", 2)
                current = found.setdefault(h, {"date": date, "subject": subject, "files": []})
            elif line.strip() and current is not None and line.strip() not in current["files"]:
                current["files"].append(line.strip())
    return found


def table_rows(path, prefix):
    """Markdown table rows whose first cell starts with prefix (D-, G-, R-): list of cell lists."""
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as f:
        for line in f:
            if re.match(r"^\|\s*" + prefix + r"\d+\s*\|", line):
                rows.append([c.strip() for c in line.strip().strip("|").split("|")])
    return rows


def text_matches(text, keywords):
    low = text.lower()
    return any(k.lower() in low for k in keywords)


def owned(owner_cell, handles, owner_labels):
    cell = owner_cell.lower()
    return any(("@" + h.lower()) in cell for h in handles) or any(l.lower() in cell for l in owner_labels)


def filled(cell):
    return cell.strip().strip("`").lower() not in EMPTY


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--author", action="append", default=[], help="git author name or email (repeat for aliases)")
    p.add_argument("--github", action="append", default=[], help="GitHub handle without @ (repeat)")
    p.add_argument("--owns", action="append", default=[], help="subagent key the member owns, from areas.json (repeat)")
    p.add_argument("--focus", help="area key from areas.json (subagent or section)")
    p.add_argument("--repo", default=".", help="path inside the repository")
    p.add_argument("--no-gh", action="store_true", help="skip pull requests (no gh call)")
    a = p.parse_args()

    root = repo_root(a.repo)
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "..", "areas.json"), encoding="utf-8") as f:
        areas = json.load(f)
    allareas = {**areas["subagents"], **areas["sections"]}
    if a.focus and a.focus not in allareas:
        sys.exit("Unknown --focus '%s'. Use one of: %s" % (a.focus, ", ".join(sorted(allareas))))
    focus = allareas.get(a.focus) if a.focus else None
    lines_in_scope = focus["rubric"] if focus else list(LINES)

    owner_labels, own_keywords = [], []
    for key in a.owns:
        sub = areas["subagents"].get(key)
        if not sub:
            sys.exit("Unknown --owns '%s'. Use one of: %s" % (key, ", ".join(sorted(areas["subagents"]))))
        owner_labels += sub.get("owner", [])
        own_keywords += sub.get("keywords", [])
    keywords = focus["keywords"] if focus else []

    # 1. Commits and files, mapped to rubric lines by path
    found = commits(root, a.author)
    def in_focus(path):
        return not focus or any(path.startswith(pp) for pp in focus["paths"]) or (
            "block" in focus and path.endswith("CARES.agent"))
    per_line = {k: {"commits": set(), "files": set()} for k in LINES}
    for h, c in found.items():
        for path in c["files"]:
            if not in_focus(path):
                continue
            for line, prefixes in areas["rubric_paths"].items():
                if any(path.startswith(pp) for pp in prefixes):
                    per_line[line]["commits"].add(h)
                    per_line[line]["files"].add(path)

    # 2. Rows the member owns (DECISIONS, GAPS) or that match their areas (RISKS has no owner column)
    docs = os.path.join(root, "docs")
    def scope_ok(text):
        return not focus or text_matches(text, keywords)
    decisions = []
    for r in table_rows(os.path.join(docs, "DECISIONS.md"), "D-"):
        if len(r) >= 7 and owned(r[-1], a.github, owner_labels) and scope_ok(" ".join(r)):
            decisions.append({"id": r[0], "status": r[2], "has_why": filled(r[4]), "has_gave_up": filled(r[5]),
                              "decision": r[3][:140]})
    gaps = []
    for r in table_rows(os.path.join(docs, "GAPS.md"), "G-"):
        if len(r) >= 5 and owned(r[-2], a.github, owner_labels) and scope_ok(" ".join(r)):
            status = r[-1]
            gaps.append({"id": r[0], "status": status[:60], "has_impact": filled(r[2]),
                         "explained": len(status) > 12, "closed": bool(re.match(r"\s*(FIXED|CLOSED)", status)),
                         "gap": r[1][:140]})
    risks = []
    risk_keywords = keywords or own_keywords
    for r in table_rows(os.path.join(docs, "RISKS.md"), "R-"):
        if len(r) >= 7 and risk_keywords and text_matches(" ".join(r), risk_keywords):
            risks.append({"id": r[0], "has_safeguard": filled(r[3]), "names_what_is_not_caught": filled(r[5]),
                          "failure": r[1][:140]})

    # 3. Test runs that mention the member's areas
    test_runs = []
    tp = os.path.join(docs, "TEST_PLAN.md")
    run_keywords = keywords or own_keywords
    if os.path.exists(tp) and run_keywords:
        with open(tp, encoding="utf-8") as f:
            for line in f:
                if re.match(r"^\|\s*20\d\d-\d\d-\d\d\s*\|", line) and text_matches(line, run_keywords):
                    cells = [c.strip() for c in line.strip().strip("|").split("|")]
                    test_runs.append({"date": cells[0], "what": cells[1][:80],
                                      "passed": bool(re.search(r"\bPass\b|PASS", cells[-1]))})

    # 4. Pull requests (descriptions are the team's written justification)
    prs = []
    if not a.no_gh:
        for handle in a.github:
            out = run(["gh", "pr", "list", "--author", handle, "--state", "all", "--limit", "100",
                       "--json", "number,title,state,body"], root)
            for pr in json.loads(out) if out else []:
                if focus and not text_matches(pr["title"] + " " + (pr.get("body") or ""), keywords):
                    continue
                body = pr.get("body") or ""
                prs.append({"number": pr["number"], "state": pr["state"], "title": pr["title"][:100],
                            "has_why": "why" in body.lower(),
                            "has_testing": bool(re.search(r"How it was tested[\s\S]{40,}", body))})

    # 5. Suggested level per line, from quality signals
    d_quality = [d for d in decisions if d["has_why"] and d["has_gave_up"]]
    g_explained = [g for g in gaps if g["has_impact"] and g["explained"]]
    r_honest = [r for r in risks if r["names_what_is_not_caught"]]
    t_pass = [t for t in test_runs if t["passed"]]
    pr_tested = [x for x in prs if x["has_testing"]]
    signals = {
        "usecase": [("business docs touched", len(per_line["usecase"]["files"]) > 0),
                    ("decisions tied to the business case", any(text_matches(d["decision"], ["KPI", "retention", "ROI", "cost", "value"]) for d in decisions))],
        "configure": [("agent or Apex/Flow work", len(per_line["configure"]["files"]) > 0),
                      ("structural decisions with why and trade-off", len(d_quality) >= 2),
                      ("tests behind the build", len(pr_tested) >= 1 or len(t_pass) >= 1)],
        "ground": [("grounding or data-access work", len(per_line["ground"]["files"]) > 0),
                   ("verification recorded (passing runs)", len(t_pass) >= 1),
                   ("data gaps named", any(text_matches(g["gap"], ["data", "Data Cloud", "order", "field", "source"]) for g in gaps))],
        "risks": [("risks or gaps owned", len(gaps) + len(risks) > 0),
                  ("gaps explained with impact and status", len(g_explained) >= 2),
                  ("says what a safeguard does not catch", len(r_honest) >= 1)],
        "approach": [("test or deploy evidence", len(per_line["approach"]["files"]) > 0 or len(test_runs) > 0),
                     ("failures fixed and closed", any(g["closed"] for g in gaps)),
                     ("deferred failures explained", any((not g["closed"]) and g["explained"] for g in gaps))],
        "justification": [("decisions owned", len(decisions) > 0),
                          ("decisions with why and what was given up", len(d_quality) >= 2),
                          ("PRs that explain why and how it was tested", len(pr_tested) >= 2)],
    }
    result_lines = {}
    for key in lines_in_scope:
        met = [name for name, ok in signals[key] if ok]
        # The repo shows what was built; only the member's answers show they can explain it,
        # so repo evidence alone tops out at Practicing (Advanced is earned in review/roleplay)
        level = 1 if not met else (2 if len(met) == 1 else 3)
        result_lines[key] = {
            "label": LINES[key],
            "suggested_level": level,
            "suggested_label": LEVELS[level],
            "signals_met": met,
            "signals_missing": [name for name, ok in signals[key] if not ok],
            "commits": len(per_line[key]["commits"]),
            "files": sorted(per_line[key]["files"])[:12],
        }

    print(json.dumps({
        "member": {"authors": a.author, "github": a.github, "owns": a.owns},
        "focus": {"key": a.focus, "label": focus["label"]} if focus else None,
        "repo_head": (run(["git", "rev-parse", "--short", "HEAD"], root) or "").strip(),
        "commits_total": len(found),
        "lines": result_lines,
        "decisions": decisions,
        "gaps": gaps,
        "risks": risks,
        "test_runs": test_runs[-15:],
        "pull_requests": prs,
        "note": "Suggested levels come from quality signals only and stop at Practicing (3): Advanced needs the member's answers (review or roleplay).",
    }, indent=2))


if __name__ == "__main__":
    main()
