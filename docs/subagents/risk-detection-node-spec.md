# Node spec: Risk Detection

Short, factual description of how this subagent works as built on branch `feature/risk-detection-subagent`. For the why, the trade-offs and the rubric view, read [risk-detection.md](risk-detection.md). Decisions: D-007 to D-013 in [../DECISIONS.md](../DECISIONS.md).

State: built and validated, **not deployed, not tested live**. Last updated: 2026-10-19.

## In one paragraph
Before Refund makes an offer, CARES checks how many issue cases the verified customer had in the last N days. The result is `CLEAN`, `NOT_CLEAN` or `UNKNOWN`. The customer is never told. The script runs the check, not the model, and the result is stored in variables that only the action sets.

## Where it sits
```
Customer -> Agent Router
              | refund request
              v
        Risk Detection   (silent: no reply to the customer)
              | runs Flow once, stores result
              v
           Refund        (reads risk_status; today a placeholder)
```
Refund cannot be reached from the router until `risk_checked` is True (D-011).

## Node card
| Field | Value |
|---|---|
| Type | Subagent used as a silent, deterministic step (D-007) |
| Entered from | Router action `go_to_risk_detection` |
| Leaves to | Refund, by `transition to` in `before_reasoning` |
| Talks to the customer | No |
| Action | `get_risk_result` -> `flow://CARES_Get_Risk_Result` |
| Reads | `ContactId` (set by the channel), `risk_lookback_days` |
| Writes | `risk_status`, `risk_issue_count`, `risk_checked` |
| Data written to the org | None (read-only) |
| Failure behavior | `UNKNOWN`; the flow continues to Refund; no error text |

## Steps, in order
1. Router sends a refund request to Risk Detection (Refund is hidden until step 5 has happened).
2. `before_reasoning` runs. If `risk_checked == False`:
3. The script calls the Flow with `contactId = ContactId` and `lookbackDays = risk_lookback_days`.
4. The script copies the Flow outputs into `risk_status` and `risk_issue_count`, then sets `risk_checked = True`.
5. The script transitions to Refund.

If the subagent is entered a second time in the same conversation, step 3 is skipped (`risk_checked` is already True) and it goes straight to Refund.

## Flow `CARES_Get_Risk_Result`
| | |
|---|---|
| Inputs | `contactId` (text), `lookbackDays` (number) |
| Outputs | `riskStatus` (text), `issueCount` (number) |
| Query | Cases where `ContactId` = input, `CreatedDate` >= now - `lookbackDays`, `Type` != `Refund / Compensation` |
| Counting | Loop over the result and add one per case |
| Rule | 0 cases -> `CLEAN`; 1 or more -> `NOT_CLEAN` |
| `UNKNOWN` when | `contactId` is blank, `lookbackDays` is not above 0, or the query fails (fault path) |
| Status in file | `Draft` (it must be activated after deploy) |

Why the recovery type is excluded: a recovery case created by CARES itself must not make the customer look risky next time (D-009).

## Variables
| Variable | Type | Default | Set by | Read by |
|---|---|---|---|---|
| `risk_checked` | boolean | False | Script, in Risk Detection | Router gate, Risk Detection |
| `risk_status` | string | `UNKNOWN` | Flow output | Refund (to be built) |
| `risk_issue_count` | number | 0 | Flow output | Refund / logging |
| `risk_lookback_days` | number | 30 | Agent default (placeholder, `[$]` confirm with Pronto) | Risk Detection |

Rule: the model never sets these. A flag that drives money must come from an action (D-004).

## Contract for other owners
| Owner | What you must do |
|---|---|
| Refund | Read `risk_status`. `CLEAN`: you may use the clean-record offer. `NOT_CLEAN` or `UNKNOWN`: standard offer only. Never say why to the customer (G-013) |
| Router | Accept the gate on `go_to_refund` and the router text change (D-011) |
| Stolen & Delayed | Your transition to Refund bypasses the gate. Send it to Risk Detection instead (G-012) |
| Merger | Deploy the Flow before the agent, activate the Flow, use `--test-level NoTestRun` until the org's broken Apex is fixed (G-014) |

## How to test it (when a deploy is allowed)
1. Deploy the Flow (new, additive). Activate it.
2. Run the Flow alone with the cases T-01 to T-10 in [risk-detection.md](risk-detection.md), section 5.
3. Publish a draft agent version and preview with a messaging contact; read the trace: did the action run, what did it return, did Refund open only after.
4. Expected false clean for account-only cases (T-08, T-09). They prove G-016.

## Known limits
- Cases with only an account are not counted (G-010, G-016; fix proposed in D-013, not built).
- The 30-day window and the issue types are placeholders.
- Cases never logged, or logged in another system, are invisible.
- Nothing has run live. Dry-run deploy of the Flow and agent validation passed; the logic was only simulated with read-only queries.
