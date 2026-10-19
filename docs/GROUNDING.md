# Grounding

What the agent knows, from where, and how we check it. Owners add rows. Status: `DECIDED`, `PROPOSAL`, `OPEN`.

## Principle
Facts and eligibility come from queries (Flow or Apex). Retrieval over text (RAG) is only for meaning, never for eligibility. If a source is empty or fails, the agent takes the standard path or hands off to a person. It never invents an answer.

## Sources

| Fact | Source | Method | Freshness | Volume | Latency | If it fails | Status |
|---|---|---|---|---|---|---|---|
| Who the customer is | Channel contact (`ContactId`) | Linked variable | Per session | 1 | None | Unverified: no data actions, offer a person | PROPOSAL |
| Recent issue history (30 days) | Cases of the verified contact | Flow (SOQL count) | Live | Small per contact | Fast (one query) | `UNKNOWN`: standard offer | PROPOSAL |
| Order, delivery times, driver location | `OPEN` (the shared org has no orders yet) | `OPEN` | `OPEN` | `OPEN` | `OPEN` | `OPEN` | OPEN |
| Customer tier | `OPEN` (no field exists) | `OPEN` | `OPEN` | `OPEN` | `OPEN` | Standard tier | OPEN |
| Policy values (caps, windows, percentages) | Configuration (custom metadata or object) | Flow reads it | Changes on deploy or edit | Small | Fast | Block the offer, send to a person | OPEN |

## Why query and not RAG for facts
- Freshness: a query reads the live record. An index can lag behind.
- Volume: facts about one customer are a handful of rows.
- Latency: in an earlier individual build, one prompt-template call (retrieval plus generation) took about 6 seconds; a query is much faster.
- Auditability: a query returns exact rows that we can check one by one.
Use RAG only for free text where meaning matters (for example past case notes), with a required customer filter that fails closed (empty means nothing is returned).

## What we audit (and what we found)
Audit each source before building on it. Record date, what we checked, result.

| Date | Source | What we checked | Result |
|---|---|---|---|
| 2026-10-19 | Shared org data | Objects, custom fields, record counts | No orders, no tier field, few cases from one contact (gap G-003, G-004) |
| 2026-10-19 | Cases | Fields, dates, contact link | 9 cases, all from 2026-09-28; 5 of 9 have no contact (only an account); types in use listed in `subagents/risk-detection.md` |
| | Any indexed text | Sensitive data (card numbers, personal data) | `OPEN` |
| | Dates | Are the date fields correct? | `OPEN` |

Lessons from an earlier individual build, to repeat here: in that org about 97% of one order date field was wrong, so sorting by it gave wrong answers; a card number was found inside an indexed case text. Both were found only by checking rows, not by asking the agent. So we audit rows before we trust a source.

## Failure behavior
| Failure | Agent does |
|---|---|
| Empty result | Say it cannot find the information; standard path or a person |
| Action error | Same; no error details to the customer |
| Wrong or stale data | Not detected by the agent: caught by audits and tests |

## Grounding risks that remain
- Present but wrong data (see [RISKS.md](RISKS.md) R-09).
- Sensitive data inside indexed text (R-10).
- Duplicate customer records (R-11).

## Addendum 2026-10-19: how contact-less cases are spread
Cases without a contact sit on 2 accounts: one account has 1 contact (4 cases) and one has 3 contacts (1 case). So 4 of the 5 account-only cases can be attributed safely and 1 cannot. (Correction: an earlier note said 3 accounts; the third account already had contacts on its cases.) See D-013 and G-016.
