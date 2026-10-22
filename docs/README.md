# CARES docs: start here

CARES is the Pronto customer care agent. A router sends each customer to one specialist subagent. This folder explains what we built, how, why, and what is still missing.

> **Deploy status (2026-10-21): nothing new is deployed yet.** `main` now has PR #15 (policy alignment, Pronto Help, Urgent Escalation) and PR #18 (real Refund backend). Both passed a check-only deploy with tests (81/81), but the team org still runs the published v1 agent and the Refund stubs. Deploy steps and blockers: [DEPLOY_CHECKLIST.md](DEPLOY_CHECKLIST.md).

| File | What it answers |
|---|---|
| [SPEC.md](SPEC.md) | What is CARES? Architecture, subagents, variables, rules, status per subagent |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branches, PRs, who edits what, how we deploy |
| [DECISIONS.md](DECISIONS.md) | Every decision, with the reason and what we gave up |
| [GAPS.md](GAPS.md) | Known gaps and risks, with owner |
| [OPEN_ITEMS.md](OPEN_ITEMS.md) | What's left after merging the Risk Detection, Experience Rating and Stolen & Delayed Orders PRs: unbuilt subagents, connections wired in code with no real org config behind them yet, tagged by GitHub username |
| [ARCHITECTURE_NOTES.md](ARCHITECTURE_NOTES.md) | Suggestions for splitting subagents into more specific pieces, each tied to a real symptom already in this repo and to a named Agent Script pattern, tagged by GitHub username |
| [REFUND_SD_REAL_DATA_SPEC.md](REFUND_SD_REAL_DATA_SPEC.md) | Spec for one branch: refuse a second claim before the offer (G-091), Stolen & Delayed on real orders with the order id always on its Case (G-081, G-098, G-077), what `apply_settlement` should do (G-031), and a CARES Admin app with tabs for the policy records, with the decisions each part needs |
| [CONTRACTS_FIX_SPEC.md](CONTRACTS_FIX_SPEC.md) | Proposed fixes for every broken contract between subagents (shared variables, handoffs, ids, enum values, action types), with owner and tests |
| [subagents/](subagents/) | One doc per subagent: purpose, inputs, outputs, tests, gaps. Risk Detection has a short [node spec](subagents/risk-detection-node-spec.md) and a full design doc. [Refund](subagents/refund.md) is a handoff brief for the subagent still to be built, explaining the context Risk Detection and Stolen & Delayed Orders already produce for it |
| [RISKS.md](RISKS.md) | Risk Diagnostic: People, Business, Tech, Data, one concrete failure each |
| [GROUNDING.md](GROUNDING.md) | Data sources, how accuracy is checked, what happens on failure |
| [sources/](sources/) | The four official Pronto documents (PDF), with date, owner and hash. The only official rules we build on |
| [POLICY_ALIGNMENT.md](POLICY_ALIGNMENT.md) | Every official Pronto rule vs what CARES does, before and after this branch, with owner and next step |
| [grounding/golden-set.md](grounding/golden-set.md) | 25 fixed questions to check Pronto Help's retrieval and guardrails, with a results table |
| [DEPLOY_CHECKLIST.md](DEPLOY_CHECKLIST.md) | What to check and in which order when the policy alignment branch is deployed, including the Flow version step |
| [TEST_PLAN.md](TEST_PLAN.md) | Happy, edge and adversarial tests, results per run |
| [BASELINE_BATCH_TEST.md](BASELINE_BATCH_TEST.md) | The whole-agent baseline batch test: personas, tiers, invariants, scenarios that fail on purpose, how to run and record |
| [JOURNEY.md](JOURNEY.md) | Dated log of how we got here |
| [PANEL_QA.md](PANEL_QA.md) | Team answers to expected panel questions |
| [../.claude/skills/rubric-mentor/](../.claude/skills/rubric-mentor/SKILL.md) | Presentation coaching: `/rubric-mentor` scores each member on the Capstone rubric from repo evidence, asks Socratic questions by Slack DM, gives tips, can focus on one subagent or business area, and role-plays the Pronto C-suite (D-101). Scores stay local and private |

Reading order for a new teammate or assistant: this file -> SPEC.md -> your subagent doc -> DECISIONS.md.

Headline goal: keep the customer loyal to Pronto. Switching apps is free, so a bad order handled badly can lose the customer. Guardrail: compensation must stay inside policy.
