# Focus areas (`--focus <key>`)

`--focus` scopes evidence, scores and questions to one subagent or one business section. The machine-readable map is [areas.json](areas.json): path prefixes for git evidence, the `CARES.agent` block, keywords that find rows in `DECISIONS.md` / `GAPS.md` / `RISKS.md` / `TEST_PLAN.md`, how the `Owner` column names the area, and the rubric lines it feeds. With a focus, only those rubric lines are scored.

## Subagents
| Key | Subagent | Feeds |
|---|---|---|
| `router` | Agent Router (HyperClassifier, router redesign) | Configure, Risks, Approach |
| `refund` | Refund (offers, tiers, policy rows, resolutions) | Use Case, Configure, Ground, Risks, Justification |
| `stolen-delayed` | Stolen & Delayed Orders (timing, geofence, mock telemetry) | Configure, Ground, Risks, Approach, Justification |
| `risk-detection` | Risk Detection (history check, retention context) | Configure, Ground, Risks, Justification |
| `experience-rating` | Experience Rating (CSAT) | Use Case, Configure, Approach |
| `escalation` | Escalate to Human / Urgent Escalation (cases, Omni-Channel, alerts) | Configure, Risks, Approach |
| `pronto-help` | Pronto Help (policy RAG, golden set) | Ground, Risks, Justification |
| `order-status` | Order Status (status and ETA from Data Cloud) | Ground, Configure |
| `identify-customer` | Identify Customer (email lookup) | Risks, Configure |

## Business sections
| Key | Section | Main docs | Feeds |
|---|---|---|---|
| `roi` | ROI & cost | `MARKET_BENCHMARKS.md`, `metrics/data/value.json`, `PANEL_QA.md` | Use Case, Justification |
| `retention` | Retention & KPIs | `SPEC.md`, `metrics/` | Use Case, Justification |
| `security` | Security & governance | `RISKS.md`, permission sets, `CLAUDE.md` | Risks, Configure |
| `data` | Data & grounding | `GROUNDING.md`, `grounding/`, `CARES_OrderData` | Ground |
| `quality` | Quality & testing | `TEST_PLAN.md`, `BASELINE_BATCH_TEST.md`, `scripts/testing/` | Approach |
| `roadmap` | Roadmap & trade-offs | `ARCHITECTURE_NOTES.md`, `OPEN_ITEMS.md`, `GAPS.md`, `DECISIONS.md` | Approach, Justification |

To add an area, add an entry to `areas.json` and a row here.
