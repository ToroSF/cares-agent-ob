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
| G-013 | The Refund placeholder does not read `risk_status` yet | The result is computed but has no effect on the offer | Refund owner | OPEN |
| G-014 | Org has Apex classes that fail to compile ("Variable does not exist") so a normal validate with tests fails for any deploy | Deploys need `--test-level NoTestRun` or the Apex must be fixed first | Merger | OPEN |
| G-015 | Flow and agent are only validated, not run: nothing has been deployed or tested live | Behavior is unproven | Risk Detection owner | OPEN |
| G-016 | Account-only cases on an account with several contacts cannot be assigned to one person | Those cases stay invisible to Risk Detection (false clean). Only a data fix at case creation closes it | Team | OPEN (1 case in the shared org) |
| G-017 | Not known what the script does when the action itself errors (Flow missing, inactive or crashing) | The agent could show a generic error, or stop before Refund. Safe direction (Refund closed) but not tested | Risk Detection owner | OPEN |
| G-018 | `ContactId` from the channel has not been checked live | If it is empty, every result is `UNKNOWN` and the clean-record offer never happens | Team | OPEN |
| G-019 | A new contact with no cases is `CLEAN` (see D-014) | Anyone who just signed up can get the clean-record offer | Team / Pronto | OPEN (decision) |
| G-020 | If the action errors, `risk_checked` may stay False; Refund then sends back to Risk Detection, which could loop | A loop, or a generic error, instead of a standard offer | Risk Detection owner | OPEN, test with Flow inactive (T-14) |
| G-021 | The gate edits the Refund block, owned by someone else | Merge conflict, or the Refund owner removes the lines | Refund owner | OPEN, flagged in the PR |
| G-022 | In the simulated preview the action `get_risk_result` left no trace and `risk_status` / `risk_issue_count` did not change, but `risk_checked` still became True | The gate can open without a result. Safe today only because `risk_status` defaults to `UNKNOWN` (D-008). Not known if this is a simulator limit or a real problem | Risk Detection owner | OPEN, must be checked in a live run |

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
