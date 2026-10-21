# Node spec: Risk Detection

Short, factual description of how this subagent works as built on branch `feature/risk-detection-subagent`. For the why, the trade-offs and the rubric view, read [risk-detection.md](risk-detection.md). Decisions: D-007 to D-013 in [../DECISIONS.md](../DECISIONS.md).

State: built and validated (compiler, dry-run deploy, agent validate), **not deployed, not tested live**. Last updated: 2026-10-19.

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

Refund cannot be reached until `risk_checked` is True: the router hides it (D-011) and Refund itself sends anyone back to Risk Detection first (D-015), so no route skips the check.

## Node card

| Field                   | Value                                                  |
| ----------------------- | ------------------------------------------------------ |
| Type                    | Subagent used as a silent, deterministic step (D-007)  |
| Entered from            | Router action `go_to_risk_detection`                   |
| Leaves to               | Refund, by `transition to` in `before_reasoning`       |
| Also entered from       | Refund, when `risk_checked` is False (D-015)           |
| Talks to the customer   | No                                                     |
| Action                  | `get_risk_result` -> `flow://CARES_Get_Risk_Result`    |
| Reads                   | `ContactId` (set by the channel), `risk_lookback_days` |
| Writes                  | `risk_status`, `risk_issue_count`, `risk_checked`      |
| Data written to the org | None (read-only)                                       |
| Failure behavior        | `UNKNOWN`; the flow continues to Refund; no error text |

## Steps, in order

1. Router sends a refund request to Risk Detection (Refund is hidden until step 5 has happened).
2. `before_reasoning` runs. If `risk_checked == False`:
3. The script calls the Flow with `contactId = ContactId` and `lookbackDays = risk_lookback_days`.
4. The script copies the Flow outputs into `risk_status` and `risk_issue_count`, then sets `risk_checked = True`.
5. The script transitions to Refund.

If the subagent is entered a second time in the same conversation, step 3 is skipped (`risk_checked` is already True) and it goes straight to Refund.

## Flow `CARES_Get_Risk_Result`

|                 |                                                                                                                                                                 |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inputs          | `contactId` (text), `lookbackDays` (number)                                                                                                                     |
| Outputs         | `riskStatus` (text), `issueCount` (number)                                                                                                                      |
| Step 0          | Read the contact. If it does not exist -> `UNKNOWN`                                                                                                             |
| Query 1         | Cases where `ContactId` = input, `CreatedDate` >= now - `lookbackDays`, `Type` != `Refund / Compensation`, `CARES_Escalation__c` = false (D-077)                |
| Query 2 (D-013) | Only if the contact has an account and no other contact is on that account: cases with that `AccountId`, no `ContactId`, same date, type and escalation filters |
| Counting        | Loop over each result and add one per case                                                                                                                      |
| Rule            | 0 cases -> `CLEAN`; 1 or more -> `NOT_CLEAN`                                                                                                                    |
| `UNKNOWN` when  | `contactId` is blank, the contact does not exist, `lookbackDays` is not above 0, or any query fails (fault path)                                                |
| Status in file  | `Draft` (it must be activated after deploy)                                                                                                                     |

Why the recovery type is excluded: a recovery case created by CARES itself must not make the customer look risky next time (D-009).

Why CARES escalation cases are excluded: `CARES_Create_Escalation_Case` opens a case on every hand-off (failed identity, failed transfer, high value, safety report). Counted as issues, three hand-offs reached `risk_review_threshold` and removed the offer from a customer with no real complaint, and each `PATTERN_REVIEW` escalation added one more (D-077, G-100). The Flow marks those cases with `CARES_Escalation__c = true`; cases from before the field are marked once by `scripts/apex/backfill-cares-escalation-flag.apex`.

## Variables

| Variable             | Type    | Default   | Set by                                                 | Read by                     |
| -------------------- | ------- | --------- | ------------------------------------------------------ | --------------------------- |
| `risk_checked`       | boolean | False     | Script, in Risk Detection                              | Router gate, Risk Detection |
| `risk_status`        | string  | `UNKNOWN` | Flow output                                            | Refund (to be built)        |
| `risk_issue_count`   | number  | 0         | Flow output                                            | Refund / logging            |
| `risk_lookback_days` | number  | 30        | Agent default (placeholder, `[$]` confirm with Pronto) | Risk Detection              |

Rule: the model never sets these. A flag that drives money must come from an action (D-004).

## Contract for other owners

| Owner            | What you must do                                                                                                                                                                                                                                                                              |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Refund           | Your block now starts with a gate that sends anyone without a check to Risk Detection (D-015). Keep it, or move it, but do not drop it. Read `risk_status`. `CLEAN`: you may use the clean-record offer. `NOT_CLEAN` or `UNKNOWN`: standard offer only. Never say why to the customer (G-013) |
| Router           | Accept the gate on `go_to_refund` and the router text change (D-011)                                                                                                                                                                                                                          |
| Stolen & Delayed | Nothing to change: the gate at Refund covers your transition (G-012)                                                                                                                                                                                                                          |
| Merger           | Deploy the Flow before the agent, activate the Flow, use `--test-level NoTestRun` until the org's broken Apex is fixed (G-014)                                                                                                                                                                |

## When data is missing or something fails

The rule: a missing answer never unlocks the better offer. `UNKNOWN` is handled like `NOT_CLEAN` by Refund (standard offer).

| Situation                                                                                       | Result                                                                                                                                                                                                                           | Customer sees                            | Status                                                                                              |
| ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `ContactId` is empty (no contact linked by the channel, or a preview without a channel)         | `UNKNOWN`                                                                                                                                                                                                                        | Nothing                                  | By design in the Flow. Not tested live                                                              |
| `lookbackDays` is empty or below 1                                                              | `UNKNOWN`                                                                                                                                                                                                                        | Nothing                                  | By design in the Flow. Not tested live                                                              |
| The case query fails (fault path in the Flow)                                                   | `UNKNOWN`                                                                                                                                                                                                                        | Nothing                                  | By design in the Flow. Not tested live                                                              |
| The Flow is not deployed, not active, or the action itself errors                               | **Unknown behavior.** The script may stop with an error instead of moving on. `risk_checked` may stay False, so Refund stays closed, and the gate at Refund could send the conversation back to Risk Detection in a loop (G-020) | Possibly the generic agent error message | **Assumption, not tested (G-017).** Safe direction: Refund stays closed, nobody gets a better offer |
| Contact has no cases in the window                                                              | `CLEAN`                                                                                                                                                                                                                          | Nothing                                  | Correct result                                                                                      |
| Contact has only `Refund / Compensation` cases in the window                                    | `CLEAN`                                                                                                                                                                                                                          | Nothing                                  | By design (D-009)                                                                                   |
| Contact has only CARES escalation cases in the window (`CARES_Escalation__c` = true)            | `CLEAN`                                                                                                                                                                                                                          | Nothing                                  | By design (D-077). Built, not deployed                                                              |
| A real repeat claimer whose earlier claims CARES refunded (no case, only `CARES_Resolution__c`) | `CLEAN`                                                                                                                                                                                                                          | Nothing                                  | **False clean.** Refunds are not counted yet (open item in D-077)                                   |
| Case linked only to an account, contact is the only one on that account                         | Counted (D-013)                                                                                                                                                                                                                  | Nothing                                  | Mitigated. Not tested live                                                                          |
| Case linked only to an account, account has several contacts                                    | `CLEAN`                                                                                                                                                                                                                          | Nothing                                  | **False clean.** Known gap (G-016)                                                                  |
| Contact id does not exist                                                                       | `UNKNOWN`                                                                                                                                                                                                                        | Nothing                                  | By design                                                                                           |
| New contact, no cases                                                                           | `CLEAN`                                                                                                                                                                                                                          | Nothing                                  | Open decision (D-014, G-019)                                                                        |
| Problem never logged as a case, or logged in another system                                     | `CLEAN`                                                                                                                                                                                                                          | Nothing                                  | **False clean.** Not fixable here: the check cannot see it                                          |
| Two contact records for the same person                                                         | Counts only the one in `ContactId`                                                                                                                                                                                               | Nothing                                  | **False clean.** Data quality problem (R-11)                                                        |
| Case dates are wrong or have no type                                                            | Date wrong: window is wrong. No type: it is counted as an issue                                                                                                                                                                  | Nothing                                  | Needs a data audit                                                                                  |
| Customer asks about the check, their "risk" or the limit                                        | No answer; the step is silent                                                                                                                                                                                                    | A normal reply from the next step        | Instruction + silent step. Adversarial test open                                                    |

Two different kinds of failure, treated differently:

1. **Failures the system can see** (empty input, query error). Handled: `UNKNOWN`.
2. **Failures the system cannot see** (unlogged problems, account-only cases, duplicate contacts). Not handled: they look like `CLEAN`. This is the gap our safeguards do not catch. The only fixes are better data (link every case to a contact, add order and delivery data) and a cap on what the clean-record offer can cost.

Where `ContactId` really comes from: the messaging channel links the end user to a Contact. We have not checked this live, and there is no verification step in the agent yet (G-006). If the channel does not set it, every conversation ends as `UNKNOWN` and the better offer is never used. That is safe but gives no business value (see the coverage KPI in [risk-detection.md](risk-detection.md)).

## What the first preview showed (2026-10-19, simulated actions)

- The router did not offer `go_to_refund` before the check. Good.
- Order of nodes: Router -> Risk Detection -> Refund. Good.
- The customer saw only the Refund placeholder reply. Nothing about risk. Good.
- **The action call left no trace and `risk_status` / `risk_issue_count` did not change, while `risk_checked` became True (G-022).** The result stays `UNKNOWN` by default, so nobody gets the better offer, but the gate opened without a real check. We do not yet know whether this is a limit of simulated actions or a real flaw. A live run decides. If it is real, set `risk_checked` from the action result instead of from the script.

## How to test it (when a deploy is allowed)

1. Deploy the Flow (new, additive). Activate it.
2. Also test the broken cases: Flow inactive, empty `ContactId`, empty window (G-017).
3. Run the Flow alone with the cases T-01 to T-10 in [risk-detection.md](risk-detection.md), section 5.
4. Publish a draft agent version and preview with a messaging contact; read the trace: did the action run, what did it return, did Refund open only after.
5. T-09 is expected to show a false clean. It proves G-016. T-14 shows what really happens when the action errors (G-020).

## Known limits

- Cases with only an account are counted only when the contact is alone on the account (D-013). One case in the shared org stays invisible (G-016).
- A brand-new contact is `CLEAN` (D-014 open).
- The 30-day window and the issue types are placeholders.
- Cases never logged, or logged in another system, are invisible.
- Nothing has run live. Dry-run deploy of the Flow and agent validation passed; the logic was only simulated with read-only queries.
