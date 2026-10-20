# Grounding

What the agent knows, from where, and how we check it. Owners add rows. Status: `DECIDED`, `PROPOSAL`, `OPEN`.

## Principle
Facts and eligibility come from queries (Flow or Apex). Retrieval over text (RAG) is only for meaning, never for eligibility. If a source is empty or fails, the agent takes the standard path or hands off to a person. It never invents an answer.

In one line: **the script decides whose data and whose money; the model writes the words; retrieval only explains Pronto's customer rules.**

## Sources

| Fact | Source | Method | Freshness | Volume | Latency | If it fails | Status |
|---|---|---|---|---|---|---|---|
| Who the customer is | Channel contact (`ContactId`) | Linked variable | Per session | 1 | None | Unverified: no data actions, offer a person | PROPOSAL |
| Recent issue history (30 days) | Cases of the verified contact | Flow (SOQL count) | Live | Small per contact | Fast (one query) | `UNKNOWN`: standard offer | PROPOSAL |
| Order, delivery times, driver location | `OPEN` (CRM has no orders; a Data Cloud `Order` stream exists, not checked, G-057) | `OPEN` | `OPEN` | `OPEN` | `OPEN` | `OPEN` | OPEN |
| Customer tier | `OPEN` (no field exists) | `OPEN` | `OPEN` | `OPEN` | `OPEN` | Standard tier | OPEN |
| Policy values (caps, windows, percentages) | Configuration (custom metadata or object). Pronto gave no numbers: all are `[$]` (D-051) | Flow reads it | Changes on deploy or edit | Small | Fast | Block the offer, send to a person | OPEN |
| Meaning of Pronto's customer rules (status words, ETA, address changes, promos, membership, gift certificates, allergens, storefronts) | Data Library `CARES_Customer_Policy`: FAQ (F), Terms (T), Merchant Standards (M), ~800 words, 3 PDFs in `docs/sources/` | RAG, `AnswerQuestionsWithKnowledge` in Pronto Help, with citations | Re-index when Pronto sends a new PDF (`sf agent adl file add`), no agent republish | 3 files, a few chunks | +1–3 s per answer (estimate, measure in the trace) | Empty → "I couldn't find that in Pronto's customer policies" + offer a person | PROPOSAL (built; library not created, G-056) |
| Support rules (when to escalate, case handling, never-list) | Playbook (P), internal | Written into the script, flows and instructions. **Not retrieved** (D-050) | Changes need a publish | — | None | — | PROPOSAL (built) |

## Why query and not RAG for facts
- Freshness: a query reads the live record. An index can lag behind.
- Volume: facts about one customer are a handful of rows.
- Latency: in an earlier individual build, one prompt-template call (retrieval plus generation) took about 6 seconds; a query is much faster.
- Auditability: a query returns exact rows that we can check one by one.
Use RAG only for free text where meaning matters (for example past case notes), with a required customer filter that fails closed (empty means nothing is returned).

## The Data Library: trade-offs we accepted (D-046)
- **Why RAG at all for ~800 words?** The common answer would be "paste it into the instructions". We did not, because: (1) citations show the customer and the panel where an answer came from; (2) a new PDF from Pronto is a re-index, not a publish of the whole agent; (3) the text stays out of the other subagents' instructions, where it would compete with the money and safety rules. Cost: latency on this one path and one more thing to keep indexed.
- **Why a new library and not the org's `Pronto_Policy_and_FAQ`?** That library indexes all four PDFs, including the internal Playbook (supervisor review, abuse patterns). A customer must never be quoted that text. It probably serves other agents too, so changing it could break them. A separate library keeps the audience clean and the lifecycle ours.
- **Basic vs enhanced parsing:** the three documents are short plain text with no tables, so basic parsing should be enough. To confirm with the golden set.
- **Where the common pattern is wrong here:** RAG for eligibility ("am I eligible for a refund?") would let a paraphrased paragraph decide money. Eligibility stays in actions (D-004); Pronto Help sends money questions to Risk Detection → Refund.

Setup, not done yet (org write, needs the team's OK):
```
sf agent adl create --source-type sfdrive --developer-name CARES_Customer_Policy --target-org <team org> --json
sf agent adl upload --library-id <id> --file docs/sources/pronto-delivery-and-order-lifecycle-faq.pdf --wait 10 --target-org <team org> --json
# same for the Terms and Merchant Standards PDFs; NOT the Playbook
sf agent adl get --library-id <id> --target-org <team org> --json   # retrieverId present, 3 files INDEXED
```
Then replace the placeholder in `CARES.agent` with `"ARFPC_" + libraryId` (D-052). The agent user already has a Data Cloud permission set license; check the Data Space scope (G-056).

## What we audit (and what we found)
Audit each source before building on it. Record date, what we checked, result.

| Date | Source | What we checked | Result |
|---|---|---|---|
| 2026-10-19 | Shared org data | Objects, custom fields, record counts | No orders, no tier field, few cases from one contact (gap G-003, G-004) |
| 2026-10-19 | Cases | Fields, dates, contact link | 9 cases, all from 2026-09-28; 5 of 9 have no contact (only an account); types in use listed in `subagents/risk-detection.md` |
| 2026-10-20 | The four Pronto PDFs | Read each one; audience; numbers; emails, URLs, card data | Playbook is internal (agents and supervisors); F, T, M are customer-facing. No amounts, %, windows or tiers in any of them. No personal data, no URLs. One mention of an "email/identity flow" (a process, not an address) |
| 2026-10-20 | CARES vs the PDFs | Every rule, one by one | 33 rules: 2 aligned, 14 missing (2 critical: food safety, allergens). See [POLICY_ALIGNMENT.md](POLICY_ALIGNMENT.md) |
| 2026-10-20 | Existing org library `Pronto_Policy_and_FAQ` | Status, files, who uses it (read only) | Ready, 4 PDFs indexed, not assigned to any agent; a prompt template uses it. Not touched |
| 2026-10-20 | Case picklists | Type, Reason, Origin, Priority, Status values | Reasons that match the Playbook already exist (Missing items, Order arrived cold, Fraud or policy review, Can't update delivery address...). `Origin = Chat` (used by our Flow) is inactive; `Agentforce` is active |
| | `CARES_Customer_Policy` | Golden set: hit, miss, citation, latency | `OPEN` (G-056) |
| | Any indexed text | Sensitive data (card numbers, personal data) | PDFs checked 2026-10-20: none. Case text: `OPEN` |
| | Dates | Are the date fields correct? | `OPEN` |

Lessons from an earlier individual build, to repeat here: in that org about 97% of one order date field was wrong, so sorting by it gave wrong answers; a card number was found inside an indexed case text. Both were found only by checking rows, not by asking the agent. So we audit rows before we trust a source.

## Proactive check: the golden set
[grounding/golden-set.md](grounding/golden-set.md) has 25 questions: 15 inside the documents (expected document and key phrase), 5 outside (must decline), 5 adversarial (amounts, allergen guarantee, Playbook content, "ignore your rules", a card number). Run it in live preview after every re-index and record hit, miss, citation and latency there. Targets: 13/15 hits, 5/5 declines, 0 amounts stated, 0 allergen guarantees.

## Failure behavior
| Failure | Agent does |
|---|---|
| Empty result | Say it cannot find the information; standard path or a person |
| Action error | Same; no error details to the customer |
| Wrong or stale data | Not detected by the agent: caught by audits and tests |
| Library missing, not indexed, or wrong Data Space | Every Pronto Help answer is empty → decline + offer a person. **Silent:** looks like "no answer", not like an error. Check `adl get` before each demo |

## Where grounding can still go wrong (and what we do)
| Way it fails | Mitigation |
|---|---|
| The right document, the wrong chunk (for example the promo rule for gift certificates) | Golden set checks the key phrase, not just "an answer" |
| Pronto changes a document and we keep the old one | Hash and date in `docs/sources/README.md`; re-index + golden set on every new version |
| An answer mixes a policy line with an amount or a promise | Pronto Help never states amounts or eligibility; money questions go to Refund |
| The question is in Portuguese or Spanish and the index is English | Not handled; the agent's locale is English only. Recorded in R-16 |
| The library is not ready, so every answer is empty | Fails safe (declines), but silently. Check before demos |

## Data 360 end to end (what we would build next, not built)
- The library is already Data 360: files → data lake object → data model object → search index → retriever. Pronto Help calls the retriever through `AnswerQuestionsWithKnowledge`.
- Orders are not in CRM. A Data Cloud `Order` stream comes from external storage. For "where is my order?" the better source is that data through a **Data Graph** (one customer's orders, pre-joined, fast reads) or **Zero Copy** (read the source in place, no copy, fresher; latency and access not tested). Not built before the panel; first step is a read-only check that the stream has rows (G-057).
- Identity: the Playbook prefers a verified email flow or the Member Number. Data 360 identity resolution could join channel contacts to members; not in scope (R-11).

## Grounding risks that remain
- Present but wrong data (see [RISKS.md](RISKS.md) R-09).
- Sensitive data inside indexed text (R-10).
- Duplicate customer records (R-11).
- Wrong or mixed retrieval answers (R-16).

## Addendum 2026-10-19: how contact-less cases are spread
Cases without a contact sit on 2 accounts: one account has 1 contact (4 cases) and one has 3 contacts (1 case). So 4 of the 5 account-only cases can be attributed safely and 1 cannot. (Correction: an earlier note said 3 accounts; the third account already had contacts on its cases.) See D-013 and G-016.
