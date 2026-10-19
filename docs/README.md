# CARES docs: start here

CARES is the Pronto customer care agent. A router sends each customer to one specialist subagent. This folder explains what we built, how, why, and what is still missing.

| File | What it answers |
|---|---|
| [SPEC.md](SPEC.md) | What is CARES? Architecture, subagents, variables, rules, status per subagent |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branches, PRs, who edits what, how we deploy |
| [DECISIONS.md](DECISIONS.md) | Every decision, with the reason and what we gave up |
| [GAPS.md](GAPS.md) | Known gaps and risks, with owner |
| [subagents/](subagents/) | One doc per subagent: purpose, inputs, outputs, tests, gaps. Risk Detection has a short [node spec](subagents/risk-detection-node-spec.md) and a full design doc |
| [RISKS.md](RISKS.md) | Risk Diagnostic: People, Business, Tech, Data, one concrete failure each |
| [GROUNDING.md](GROUNDING.md) | Data sources, how accuracy is checked, what happens on failure |
| [TEST_PLAN.md](TEST_PLAN.md) | Happy, edge and adversarial tests, results per run |
| [JOURNEY.md](JOURNEY.md) | Dated log of how we got here |
| [PANEL_QA.md](PANEL_QA.md) | Team answers to expected panel questions |

Reading order for a new teammate or assistant: this file -> SPEC.md -> your subagent doc -> DECISIONS.md.

Headline goal: keep the customer loyal to Pronto. Switching apps is free, so a bad order handled badly can lose the customer. Guardrail: compensation must stay inside policy.
