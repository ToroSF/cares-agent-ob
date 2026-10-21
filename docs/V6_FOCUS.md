# What to fix in v6

Written 2026-10-21, after the live test runs on v5 and the Account Read fix (G-084, G-089, PR #34).
v5 stays Active until the team agrees on v6. Each line points to its gap in `GAPS.md` and the scenario that shows it.

## 1. What the customer sees (first)

| #   | Fix                                                                                                                                                                                                                            | Gap                        | Shown by                                                                                                                                                                              |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Every escalation must end with a real sentence: what happens next and the case number. Today the turn ends with no text, or with the platform text "User requested escalation to human." (also on the new PATTERN_REVIEW path) **Built on `feature/escalation-handoff`, not deployed (D-083 to D-087).** | G-086, G-082               | B-ES-01, B-PO-01, B-SD-01, B-PO-06                                                                                                                                                    |
| 2   | Stop counting CARES's own escalation cases as issues in Risk Detection. Since G-084 was fixed, a customer escalated three times in 30 days goes to PATTERN_REVIEW and gets no offer                                            | G-074, G-045               | B-RD-14; 59 of 63 issue cases in the org come from CARES                                                                                                                              |
| 3   | Real requests blocked by the platform guard topics ("Sorry, I can't assist with that"): safety, fraud, "skip the check"                                                                                                        | G-088                      | B-PO-02, B-ES-03, B-AD-08, B-RD-04                                                                                                                                                    |
| 4   | Refund keeps or escalates things that are not a refund: two requests in one message, a late order mid-offer, whole-order complaints with no item                                                                               | G-097, G-096, G-087        | B-RT-09, B-CT-03, B-RT-02, B-RT-03                                                                                                                                                    |
| 5   | A second claim on a paid order is refused only after the customer accepts the offer. Check before the offer                                                                                                                    | G-091                      | B-RF-25                                                                                                                                                                               |
| 6   | Experience Rating: a typed "5 out of 5" saves nothing; "Thanks, you're great!" mid-offer asks for a rating (3 of 7 runs)                                                                                                       | G-099, G-047               | B-ER-06, B-CX-06 — **done on `fix/v6-rating-polish` (D-078, D-079), not yet re-run or deployed**                                                                                      |
| 7   | Small wording fixes: name the order when the latest one is canceled, a second email after a miss, a person promised but not called, Off Topic promising a hand-off                                                             | G-092, G-094, G-093, G-095 | B-RF-22, B-OS-08, B-ID-02 — **done on `fix/v6-rating-polish` (D-080, D-081), not yet re-run or deployed**; B-AD-14 (Off Topic hand-off, G-095) still open: the Off Topic promise is removed on `feature/escalation-handoff` (not deployed), the routing of the long message is not |

## 2. Data and back end

| #   | Fix                                                                                                  | Gap          |
| --- | ---------------------------------------------------------------------------------------------------- | ------------ |
| 8   | Set the order id on the Stolen & Delayed escalation case before the platform call **Built on `feature/escalation-handoff`, not deployed (D-083 to D-087).** | G-098        |
| 9   | Stolen & Delayed reads the real orders (`Order__dlm`), not the mock platform                         | G-081        |
| 10  | `apply_settlement` is still a stub: no payout is made, only the `CARES_Resolution__c` row            | —            |
| 11  | Human handoff design: where the summary goes, who gets it, members for the `CARES_Escalations` queue **Built on `feature/escalation-handoff`, not deployed (D-083 to D-087).** | G-082, G-068 |
| 12  | Orders are from 2024-25; shift the dates in a copy if the demo needs "last night"                    | G-080        |

## 3. Tests

- 153 of 180 scenarios are machine-checked. The rest need an org switch (a Flow off, a permission set removed), the FX-ACCT / FX-SHARED fixtures, or an LLM judge.
- `build_fixtures.py` now computes each fixture's risk (CLEAN, NOT_CLEAN, PATTERN_REVIEW) the way the Risk Flow does, so the expected offers follow the real cap. Rebuild before every run.
- After each fix above, re-run the scenario in the table, then the P0 set twice (pass rule in `personas.md`).

## Not for v6

- Account Read for the agent user is done (PR #34). The agent user can read Account records (Public Read/Write in this org), but no CARES action returns Account fields to the model.
