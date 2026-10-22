# CARES metrics dashboard

`index.html` is one self-contained page (no internet needed) with the agent's metrics. Open it in a browser. It works offline, so it can be shown in the panel. Business value comes first, engineering evidence after.

## What it shows
| Section | Source | Refreshed by |
|---|---|---|
| Why it matters | The value chain: customers keep ordering → CARES resolves inside policy → fewer cases need a person → dollars kept | Static text |
| Business KPIs | Resolved without a person (active version's conversations), average refund or credit (`CARES_Resolution__c`), CSAT. Two tiles say "Measured from v6" until their data exists (see below) | The build |
| Headline KPI and sizing | `data/value.json` (benchmarks in `docs/MARKET_BENCHMARKS.md`), with the two measured inputs as reference | Editing `value.json`, then the build |
| Quality: Testing Center | Normalized suite results in `data/testing-center/*.json`; our reading of each run in `data/findings.json`. Findings are split over two slides: what still fails, and what works | Running a suite, then the build |
| Live batch runs and personas | `.claude/skills/cares-testing/test-results.json` (outcome counts only) | Running `run_batch.py`, then the build |
| Policy alignment | `docs/POLICY_ALIGNMENT.md` (v0 vs v1 status per rule) | The build |
| Architecture and subagents | `CARES.agent`: subagents, actions by type, hand-offs | The build |
| In the org | SOQL counts, read only: agent versions, conversations from the platform's session log (`ConversationDefinitionSession` and its event log: hand-offs, transfers, messages per conversation), cases logged by CARES, refunds and credits, messaging sessions, CSAT | The build (without `--offline`) |
| Decisions, gaps and risks | `DECISIONS.md`, `GAPS.md`, `RISKS.md`, the run log in `TEST_PLAN.md` | The build |
| Appendix | Every Testing Center case (synthetic utterances), collapsed | The build |

## The dollar figure (`data/value.json`)
The headline is the value of CARES per year, for a marketplace with 1M orders a year:

```
(customers kept × orders per year × average order value × margin)
+ (cases not handled by a person × cost per case)
− (cases CARES resolves × compensation above what a person would pay)
− (conversations × agent cost)
```

- Customers kept = complaints per year × spend lost after a bad order × share CARES wins back.
- Each input has `low`, `value` (base) and `high`. The headline shows the base case, and the subtitle shows the range. A scenario is computed only when every input in it is a number; otherwise the headline is "$ —".
- The sources and the reasoning are in [../MARKET_BENCHMARKS.md](../MARKET_BENCHMARKS.md). Write where each number came from in `source`, and mark team assumptions `[$]`.
- The measured "resolved without a person" and "average refund or credit" are shown as reference rows only: they come from test traffic.
- Units: `count` and `usd` are plain numbers. `pct` is a fraction: `0.3` means 30%.

## Measured from v6
Two escalation KPIs have tiles now and data later:

- **Escalations with the case number in the reply.** From live batch runs: scenarios whose spec has a hard `reply_any` check for a case number (`0\d{7}`), and how many of those passed. Shows a value once a run with that check is recorded.
- **Alerts delivered.** `Case.CARES_Alert_Status__c`, counted as sent or failed. Until the field is deployed the query fails, is skipped, and the tile stays "Measured from v6".

## Presentation mode
- Press **P** or the **Present** button. Each section becomes one slide.
- **→ / Space / Page Down** next, **← / Page Up** back, **Esc** to leave. The counter shows where you are.
- Print (Cmd+P, landscape) gives one slide per page, for a PDF.
- At 1440×900 a few dense slides scroll a little. On a 1080p screen they fit.

## Brand build (`presentation.html`, local only)
The Salesforce fonts (Avant Garde for Salesforce, Salesforce Sans) and brand art (logo, Agentforce ball, sparkles) are licensed, and this repo is public. So they never enter git:

- Put the files in `docs/metrics/brand/` (ignored by git): `avantgarde.woff`, `sfsans-regular.woff`, `sfsans-bold.woff`, `salesforce-horizontal-mono.svg`, `agentforce-ball.png` and `sparkle-*.png`.
- When that folder exists, the build also writes `presentation.html` (ignored by git) with them inlined. **Present from that file.**
- `index.html` (committed) has the same content and colours, with system fonts and no brand art.

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
| `CARES_Baseline_v12` | v12 | 2026-10-22 | 28/39 (72%), no platform errors; topic checks 20/25. Fails: glass asks for an email first (G-127, fixed in v13), platform guard (2), knowledge action not called on 4 right answers, 3 stale expectations |

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
- Only counts and aggregates are written. No record ids, names, emails or message text. The dashboard shows no customer data.
- Licensed fonts and brand art stay in the ignored `brand/` folder and `presentation.html`.
- Raw Testing Center exports (`*.raw.json`) are ignored by git. Commit only the normalized file.
- A Testing Center pass shows routing, actions and outcome on test utterances. It is not live behavior with real data.
- Each suite is pinned to one agent version. To compare versions, run the same suite on the new version and add its normalized result next to the old one.
