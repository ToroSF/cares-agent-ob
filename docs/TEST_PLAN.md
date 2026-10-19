# Test plan

Strategy: happy path + edge cases + adversarial, per subagent (details in each subagent doc), then end to end on the merged agent before activation.

| Level | What | Who | When | Result |
|---|---|---|---|---|
| Subagent | Cases listed in `subagents/<name>.md` | Subagent owner | Before the PR | `OPEN` |
| End to end | Full flows: late order, stolen order, refund accepted, refund refused, human handoff | Team | After merge, before activation | `OPEN` |
| Adversarial | Tier claims, another person's data, asking for limits, prompt override, off-topic | Team | After merge | `OPEN` |
| Regression | Re-run all cases after any change to the router | Merger | Before activation | `OPEN` |

Record for each run: date, agent version, case, expected, actual, pass/fail. Note that results can vary between runs because the model varies; run important cases more than once.
Where the suite lives: `OPEN`.

## Run log
| Date | Subagent | Check | Result |
|---|---|---|---|
| 2026-10-19 | Risk Detection | Local Agent Script compiler | Pass (only hints about unused variables) |
| 2026-10-19 | Risk Detection | Flow dry-run deploy, no tests, shared org (no change made) | Pass |
| 2026-10-19 | Risk Detection | `sf agent validate authoring-bundle` | Pass |
| 2026-10-19 | Risk Detection | Flow dry-run deploy with default tests | Fail: unrelated Apex classes in the org do not compile (G-014) |
| | Risk Detection | Live tests (see `subagents/risk-detection.md` section 5) | `OPEN`: needs deploy and dated test data |
| | Risk Detection | Missing-data tests: empty `ContactId`, empty window, Flow inactive, Flow error (G-017, G-018) | `OPEN`: needs deploy |
| 2026-10-19 | Risk Detection | After D-013 and D-015: local compiler | Pass |
| 2026-10-19 | Risk Detection | After D-013 and D-015: Flow dry-run deploy, no tests | Pass |
| 2026-10-19 | Risk Detection | After D-013 and D-015: `sf agent validate authoring-bundle` | Pass |
| 2026-10-19 | Risk Detection | Read-only simulation of D-013 on real data: account with one contact has 4 account-only issue cases (30 days); account with 3 contacts has 1 | Matches the design: 4 counted, 1 not counted |
