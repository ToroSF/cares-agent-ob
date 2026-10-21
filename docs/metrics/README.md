# CARES metrics dashboard

`index.html` is one self-contained page (no internet needed) with the agent's metrics. Open it in a browser. It works offline, so it can be shown in the panel.

## What it shows
| Section | Source | Refreshed by |
|---|---|---|
| Quality: Testing Center | Normalized suite results in `data/testing-center/*.json`; our reading of each run in `data/findings.json` | Running a suite, then the build |
| Test coverage we planned | Scenarios in `.claude/skills/cares-testing/personas.md`, the golden set | The build |
| Policy alignment | `docs/POLICY_ALIGNMENT.md` (v0 vs v1 status per rule) | The build |
| Architecture | `CARES.agent`: subagents, actions by type, hand-offs | The build |
| In the org | SOQL counts, read only: agent versions, conversations from the platform's session log (`ConversationDefinitionSession` and its event log: hand-offs, transfers, messages per conversation), cases logged by CARES, messaging sessions, CSAT | The build (without `--offline`) |
| Decisions, gaps and risks | `DECISIONS.md`, `GAPS.md`, `RISKS.md`, the run log in `TEST_PLAN.md` | The build |

## Run a Testing Center suite
1. The suite spec is in `suites/` (synthetic data only). Deploy and run it with `sf agent test create` and `sf agent test run` on the team org. A run creates test Cases and calls live actions.
2. Save the raw result as `data/testing-center/<suite>.raw.json` (ignored by git).
3. Normalize it: `python3 -I scripts/metrics/normalize-testing-center.py docs/metrics/suites/<suite>.yaml <raw.json> docs/metrics/data/testing-center/<suite>.json <agent version>`.
4. Add what you learned to `data/findings.json` under the suite name, then rebuild.

## Runs so far
| Suite | Agent | Run | Result |
|---|---|---|---|
| `CARES_Baseline_v3` | v3 | 2026-10-20 | 21/39 (54%); 19/25 on cases v3 was meant to handle |
| `CARES_Baseline_v5` | v5 | 2026-10-21 | 24/39 (62%); policy-branch target cases 6/14 (v3: 2/14). Results move by 2 to 3 cases between runs |

v5 uses the same 39 utterances. The only expectation changed is the Pronto Help action name (`AnswerQuestionsWithKnowledge`, the name Testing Center reports). The dashboard shows the newest run in detail and compares it with the one before.

## What is not measured yet
Session Tracing (Data Cloud) is not on in the team org. It would add, for real conversations, which subagent ran, which actions fired and how long each turn took. Turning it on is an org change, so it needs the team's OK.

## Rebuild
```
node scripts/metrics/build-dashboard.mjs --target-org <team org alias>
```
- `--offline`: skip the org and reuse `data/org.json`.
- `--docs-ref <git ref>`: read the docs from another branch (the agent stays the checkout's).
- `--compare-ref <git ref>`: show the agent from another branch and the change from the checkout.

## Rules (public repo)
- Only counts and aggregates are written. No record ids, names, emails or message text.
- Raw Testing Center exports (`*.raw.json`) are ignored by git. Commit only the normalized file.
- A Testing Center pass shows routing, actions and outcome on test utterances. It is not live behavior with real data.
- Each suite is pinned to one agent version. To compare versions, run the same suite on the new version and add its normalized result next to the old one.
