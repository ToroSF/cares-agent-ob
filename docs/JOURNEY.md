# Journey: how we got here

Short dated log of what the team did and why. Add a line when something is decided or learned. No identifiers.

| Date | What happened | Why it matters |
|---|---|---|
| 2026-10-19 | Compared four individual designs; picked CARES as the base | Strongest structure for the team, one clear job per subagent |
| 2026-10-19 | Agreed the headline KPI is customer retention | Switching apps is free |
| 2026-10-19 | Agreed on one branch per subagent and one person merging, deploying, activating | Avoid conflicts in the shared org |
| 2026-10-19 | Started the docs set in `docs/` | So every teammate and assistant can follow what was done and why |
| 2026-10-19 | Built the first Risk Detection version on its branch: a read-only Flow, variables, the silent step and the router gate. Validated, not deployed | A first working draft to test. See D-007 to D-012 |
| 2026-10-19 | A flow file failed to parse because XML elements of one type must be grouped; fixed and revalidated | Small but a trap for anyone writing Flow XML by hand |
| 2026-10-19 | Found that normal validate fails because of old Apex classes in the shared org | Anyone deploying will hit it (G-014) |
| 2026-10-19 | Wrote the failure and missing-data table for Risk Detection and split failures into visible (handled) and invisible (not handled) | The invisible ones are the gap our safeguards do not catch |
| 2026-10-19 | Closed what we could without a deploy: counted account-only cases when the contact is alone on the account (D-013), moved the Refund gate to the destination (D-015), left the short-history rule as an open decision (D-014) | A gate on each door leaves new doors open; one gate at the destination covers all of them |
| 2026-10-19 | Corrected a wrong note: cases without a contact sit on 2 accounts, not 3 | Always re-run the query before writing a number into a decision |
| 2026-10-19 | First simulated preview: routing and the gate behave as designed, the customer hears nothing about risk. But the trace shows no action call, and only `risk_checked` changed | A gate that opens without a result is the exact failure we wanted to prevent. Safe by default (`UNKNOWN`), still to confirm live (G-022) |
| 2026-10-19 | Owner decisions: D-013 accepted, D-014 keep `CLEAN` for now, D-016 case types, D-017 simulated preview allowed. Team items recorded in GAPS.md | Clear split between what the owner decides and what the team closes |
