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
| G-010 | 5 of 9 cases in the shared org have no contact (account only) | History by contact undercounts; Risk Detection could mark a customer clean by mistake | Risk Detection owner | OPEN |
| G-011 | All test cases are dated the same day | The 30-day window cannot be tested without dated data | Team | OPEN |
| G-012 | Stolen & Delayed Orders can still transition to Refund directly, skipping Risk Detection | The Refund gate is only enforced on the router | Stolen & Delayed owner | OPEN |
| G-013 | The Refund placeholder does not read `risk_status` yet | The result is computed but has no effect on the offer | Refund owner | OPEN |
| G-014 | Org has Apex classes that fail to compile ("Variable does not exist") so a normal validate with tests fails for any deploy | Deploys need `--test-level NoTestRun` or the Apex must be fixed first | Merger | OPEN |
| G-015 | Flow and agent are only validated, not run: nothing has been deployed or tested live | Behavior is unproven | Risk Detection owner | OPEN |
| G-016 | Cases with only an account and an account with several contacts cannot be assigned to one person | Those cases stay invisible to Risk Detection (false clean). Needs a data fix at case creation, or D-013 for single-contact accounts | Risk Detection owner / Team | OPEN |
| G-017 | Not known what the script does when the action itself errors (Flow missing, inactive or crashing) | The agent could show a generic error, or stop before Refund. Safe direction (Refund closed) but not tested | Risk Detection owner | OPEN |
| G-018 | `ContactId` from the channel has not been checked live | If it is empty, every result is `UNKNOWN` and the clean-record offer never happens | Team | OPEN |
