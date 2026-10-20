# Known gaps and risks

Keep this honest. A gap written here is better than a surprise in the demo.

| ID | Gap | Impact | Owner | Status |
|---|---|---|---|---|
| G-001 | Four subagents are placeholders (Refund, Stolen & Delayed, Risk Detection, Experience Rating) | Agent cannot resolve a case yet | Each owner | OPEN |
| G-002 | No actions call Flow, Apex or prompt templates | The agent cannot read or write any data | Each owner | OPEN |
| G-003 | No loyalty tier field in the org | Tier-based limits cannot be applied | Team | OPEN |
| G-004 | Test data is missing: no orders, only a few cases from one contact | Cannot test realistic cases | Team | OPEN |
| G-005 | Router can reach any subagent at any time; instruction says "make your best guess" when unclear | A money subagent can be reached by mistake or on purpose | Router owner | OPEN |
| G-006 | `VerifiedCustomerId` exists but nothing sets it; no verification step | Identity is not enforced | Team | OPEN |
| G-007 | Human transfer needs Omni-Channel routing; not checked | Escalation may not work live | Escalate owner | OPEN |
| G-008 | Nothing is saved (no case, no refund record, no rating) | No audit trail | Team | OPEN |
| G-009 | Repo `sourceApiVersion` is 67.0 and the org is 68.0 | Possible mismatch on deploy | Merger | OPEN |
| G-010 | 5 of 9 cases in the shared org have no contact (account only) | History by contact undercounts; Risk Detection could mark a customer clean by mistake | Risk Detection owner | PARTLY MITIGATED: D-013 counts 4 of the 5 (account with one contact). 1 case stays invisible (account with 3 contacts). Not tested live |
| G-011 | All test cases are dated the same day | The 30-day window cannot be tested without dated data | Team | OPEN |
| G-012 | Stolen & Delayed Orders could transition to Refund directly, skipping Risk Detection | Money subagent reachable without the check | Stolen & Delayed owner | MITIGATED on paper by D-015 (gate at Refund). Needs a live test (T-12, T-13) and Refund owner OK |
| G-013 | The Refund placeholder does not read `risk_status` yet | The result is computed but has no effect on the offer | Refund owner | CLOSED on `feature/refund-subagent`: Refund passes `risk_status` to the offer calculation (D-025) |
| G-014 | Org has Apex classes that fail to compile ("Variable does not exist") so a normal validate with tests fails for any deploy | Deploys need `--test-level NoTestRun` or the Apex must be fixed first | Merger | OPEN |
| G-015 | Flow and agent are only validated, not run: nothing has been deployed or tested live | Behavior is unproven | Risk Detection owner | OPEN |
| G-016 | Account-only cases on an account with several contacts cannot be assigned to one person | Those cases stay invisible to Risk Detection (false clean). Only a data fix at case creation closes it | Team | OPEN (1 case in the shared org) |
| G-017 | Not known what the script does when the action itself errors (Flow missing, inactive or crashing) | The agent could show a generic error, or stop before Refund. Safe direction (Refund closed) but not tested | Risk Detection owner | OPEN |
| G-018 | `ContactId` from the channel has not been checked live | If it is empty, every result is `UNKNOWN` and the clean-record offer never happens | Team | OPEN |
| G-019 | A new contact with no cases is `CLEAN` (see D-014) | Anyone who just signed up can get the clean-record offer | Team / Pronto | OPEN (decision) |
| G-020 | If the action errors, `risk_checked` may stay False; Refund then sends back to Risk Detection, which could loop | A loop, or a generic error, instead of a standard offer | Risk Detection owner | OPEN, test with Flow inactive (T-14) |
| G-021 | The gate edits the Refund block, owned by someone else | Merge conflict, or the Refund owner removes the lines | Refund owner | CLOSED on `feature/refund-subagent`: Refund owner kept the gate unchanged |
| G-022 | In the simulated preview the action `get_risk_result` left no trace and `risk_status` / `risk_issue_count` did not change, but `risk_checked` still became True | The gate can open without a result. Safe today only because `risk_status` defaults to `UNKNOWN` (D-008). Not known if this is a simulator limit or a real problem | Risk Detection owner | OPEN, must be checked in a live run |
| G-023 | Refund actions are stubs: always the same order, always a 15.00 refund or 18.00 credit, and issue writes nothing (D-020) | The flow works but amounts and orders are fake | Refund owner | OPEN |
| G-024 | Policy and resolution objects (D-024) are not built | Tier limits can't be applied (see G-003); one-per-order is not enforced; no refund audit trail (see G-008) | Refund owner | OPEN |
| G-025 | Every turn starts at the router. A reply to a Refund question ("yes", an order number, "the fries") can be answered by the router or sent elsewhere. Seen in preview on an earlier branch | The customer gets stuck mid-refund | Router owner | CLOSED on `fix/inter-subagent-contracts` (D-041), see G-047. Was OPEN. Proposal, not built: add to the router "If the customer is answering a question from an ongoing refund, choose Refund. Always choose a sub-agent; never answer the customer yourself" |
| G-026 | Stolen & Delayed Orders does not set `refund_order_id` and `refund_order_outcome` | The Stolen and Delayed paths can't run or be tested | Stolen & Delayed owner | CLOSED: wrong assumption. Refund now reads the existing `stolen_delayed_*` contract (D-030 to D-032). The paths are wired but untested until the platform exists (G-032) |
| G-027 | The full Refund flow can't be previewed on this branch: the `CARES_Refund_*` classes are not deployed, so the runtime withholds them (`NO_USER_ACCESS`) even in simulation | Only the gates are proven on this branch. The same logic under earlier class names passed a live preview (TEST_PLAN) | Merger | OPEN, needs deploy + `CARES_Refund_Access` assignment |
| G-028 | Leftovers in the shared org from an earlier Refund branch, deployed before the team rules were read: 5 Apex classes (`CARES_FindOrder`, `CARES_LogOrderIssue`, `CARES_CalculateRefundOffer`, `CARES_IssueResolution`, `CARES_VerifyCustomer`) and permission set `CARES_Agent_Actions`, assigned to the agent user. Stubs only; they write no data | Unused metadata and an extra permission on the agent user | Refund owner | OPEN, delete once the team agrees |
| G-029 | In preview `ContactId` is missing (null), not blank. Refund checks both | A check for `== ""` alone lets a missing contact through | Risk Detection owner (check the Flow input handles null; see G-018) | OPEN for Risk Detection; handled in Refund |
| G-031 | `apply_settlement` is a stub, and a failed settlement is not surfaced or retried | Driver pay and restaurant reimbursement don't happen yet; later, a failure after the customer was paid would go unnoticed | Refund owner | OPEN |
| G-032 | The READY and STANDARD paths can't be tested until the delivery platform and its Named Credential exist (SD-G1) | Only the direct path has test evidence | Stolen & Delayed owner / Refund owner | OPEN |
| G-033 | Offers are shown with `$`; the order currency from Stolen & Delayed isn't passed to the offer or issue | Wrong symbol for non-USD orders (today non-USD orders escalate, SD-G7) | Refund owner | OPEN |
| G-030 | The model sometimes fills gaps: in one run it assumed "most recent order" and the Cheeseburger from "wrong burger" without asking | Usually right; could pick the wrong order or item | Refund owner | OPEN, watch in tests |
| G-048 | A simulated preview cannot assert real amounts or policy results (an AI invents action outputs), and whether `--context-variables` applies to linked or mutable variables (`ContactId`, `risk_lookback_days`) has not been checked | The baseline batch can prove routing and gates now, and nothing about money or Flow results until the deploy. If `ContactId` cannot be injected, every account-dependent scenario is blocked | Risk Detection owner (batch), Merger (deploy) | OPEN: scenario B-SM-02 checks it first (D-043) |

### Items the team will close together (agreed to register, not decided yet)
| Item | Owner | Gaps |
|---|---|---|
| Router accepts the gate on `go_to_refund` | Router owner | G-005, D-011 |
| Refund keeps the gate at the top of its block and reads `risk_status` | Refund owner | G-021, G-013, D-015 |
| Check that the channel fills `ContactId` with a real conversation | Team | G-018, G-006 |
| Link every case to a contact at creation | Team | G-010, G-016 |
| Create test cases with different dates | Team | G-011 |
| Fix the Apex that does not compile, or deploy with `--test-level NoTestRun` | Merger | G-014 |
| Real Pronto numbers (order value, margin, window, cost per case) and the new-contact rule | Pronto | `[$]`, D-014 |
| Remove `default_agent_user` from the public repo | Team | PR note |
| Allow a deploy of the Flow plus test data, so G-015, G-017, G-020, G-022 can be closed | Team | G-015 |
| G-022 option | See D-018: gate on the action result instead of `risk_checked` | | | OPEN |

### Contract problems between subagents (2026-10-20, see [CONTRACTS_FIX_SPEC.md](CONTRACTS_FIX_SPEC.md))
| ID | Gap | Impact | Owner | Status |
|---|---|---|---|---|
| G-034 | `save_csat_rating.ratingId` is `string` in the agent, `Id` in `CsatRatingSaver` (C-01) | The agent fails validation in the simulator | Experience Rating owner | CLOSED on `fix/inter-subagent-contracts`: `object` + `lightning__recordIdType`. Needs a simulator reset to confirm |
| G-035 | Refund ignores a Stolen & Delayed handoff when `refund_order_id` is already set (C-02) | Refund → S&D → Refund dead-ends; a promised READY refund is never offered | @lucasmpalomanes | CLOSED on `fix/inter-subagent-contracts` (D-033). Untested live |
| G-036 | Nothing resets `stolen_delayed_*` (C-03) | A second S&D claim in the same conversation can't be checked | @rojasC10 | CLOSED on `fix/inter-subagent-contracts` (D-034). Untested live |
| G-037 | `confirm_refund` reads a stale `stolen_delayed_customer_choice` on every path (C-04) | After a wallet-credit payout, a later refund to card can't be confirmed | @lucasmpalomanes | CLOSED on `fix/inter-subagent-contracts` (D-035). Untested live |
| G-038 | `stolen_delayed_needs_person` is not tied to an order (C-05) | One escalated order blocks every later refund in the conversation | @lucasmpalomanes / @rojasC10 | CLOSED on `fix/inter-subagent-contracts` (D-039). Untested live |
| G-039 | Refund's needs-person branch tells the customer a person is coming but does not escalate (C-06) | Customer waits for nobody | @lucasmpalomanes | CLOSED on `fix/inter-subagent-contracts` (D-037). Untested live |
| G-040 | `find_order` and the delivery platform may return different order id spaces (C-07) | Same order could be paid twice once real data exists | Team | DECIDED (D-038): platform id everywhere. The `find_order` stub returns a fixed id; the real action must return the platform id |
| G-041 | S&D says "full order value"; Refund then offers total + bonus as credit; the choice values are mapped only in instruction text (C-08) | Customer hears two different amounts | @lucasmpalomanes / @rojasC10 | CLOSED on `fix/inter-subagent-contracts` (D-035, D-036). Also closes G-033 for the Stolen & Delayed paths; the direct path is still USD from the stub |
| G-042 | Experience Rating checks `ContactId == ""` only, not null (C-09, see G-029) | With a null contact it asks for a rating it can't save | Experience Rating owner | CLOSED on `fix/inter-subagent-contracts`. Risk Detection Flow and Stolen & Delayed Apex already treat null as blank (`IsBlank`, `String.isBlank`) |
| G-043 | Escalations carry no summary, and the "log a support case" fallback has no action (C-11) | The person has to ask the customer to repeat the story | Team | CLOSED on `fix/inter-subagent-contracts` (D-040). Flow not deployed or run (G-046) |
| G-044 | `csat_attempted` is per conversation, described as per case (C-13) | Second case in a conversation is not rated | Experience Rating owner | CLOSED on `fix/inter-subagent-contracts`: description now says per conversation (behavior kept) |
| G-045 | Escalation cases created by CARES (D-040) have no Type, so Risk Detection counts them as issues (D-016) | An escalated customer looks NOT_CLEAN in the next conversation | Team / @Mateus-Goes | OPEN: pick a Case Type for CARES escalations and decide whether Risk Detection excludes it |
| G-046 | `CARES_Create_Escalation_Case` is `Draft` and `CARES_Escalation_Access` (Case create/read) is not assigned. Not deployed. The Flow action uses bare `number` inputs, like `get_risk_result`; check them with org validation | Escalation logs no case until deployed, activated and assigned | Merger | OPEN |
| G-047 | `router_active_task` is a hint: the router still decides whether a message continues the task. It stays REFUND after a customer declines an offer, until another subagent clears it | A new request could still be misrouted, or a goodbye sent back to Refund | Router owner | OPEN, watch in preview |
| G-049 | On the Stolen & Delayed READY path only the method chosen in Stolen & Delayed can be confirmed (D-035). If the customer changes their mind in Refund, there is no designed behavior | The agent may refuse awkwardly, or the customer is stuck between methods | @lucasmpalomanes / @rojasC10 | OPEN: decide whether Refund may switch method (re-confirm) or hands to a person. Scenario B-IN-12 records today's behavior |
| G-050 | The agent user had no access to any of the 8 Apex classes behind CARES actions. `CsatRatingSaver` and the two Stolen & Delayed action classes were in no permission set at all | The agent checks every action at startup, so it could not run in Testing Center or a live channel | Team | CLOSED on `fix/agent-class-access`: class access added to `CARES_Experience_Rating_Access` and a new `CARES_Stolen_Delayed_Access`; all four CARES permission sets assigned at rollout |
| G-051 | Publish enforces a 255-character limit on variable, action and subagent descriptions; the local compiler, `sf agent validate authoring-bundle` and deploy do not | Publish failed on three descriptions (`router_active_task`, the Stolen & Delayed subagent, `evaluate_delivery_exception`) | Team | CLOSED on `fix/agent-description-length` (shortened). Check description length before each publish |
