# Node spec: Refund

How the Refund subagent works as built on branch `feature/refund-subagent`, with its backend rebuilt on `audit/fix-refund-backend`. Owner: @lucasmpalomanes (D-027). Decisions: D-019 to D-032, D-045 to D-048 in [../DECISIONS.md](../DECISIONS.md). Gaps: G-023 to G-033 in [../GAPS.md](../GAPS.md). Replaces the hand-off brief that was here; its contract is in "Stolen & Delayed hand-off" below.

State (v5, 2026-10-21): `find_order` reads the customer's real delivered orders from Data Cloud (D-071), and `log_order_issue` values the affected items from that order: total / number of items, the last item takes the rounding (D-072). The refund cap on the direct path is the real order total (`find_order.orderTotal`). Before v5, `find_order` was a stub (`STUB-ORDER-1042`). `calculate_refund_offer` now reads real `CARES_Tier__c` / `CARES_Refund_Policy__c` rows for the policy ceiling. `issue_resolution` now inserts a real `CARES_Resolution__c` row and enforces one-per-order via a unique field (D-045 to D-048). Compiled, dry-run deployed, agent validated. **Not deployed.** Last updated: 2026-10-20.

## In one paragraph
Refund resolves an economic order complaint. It finds the order, records what went wrong, and then the script calculates two options: a fixed refund to the original payment method, or store credit worth more. The customer picks one and confirms the exact amount, and only then is it issued, once per order. Every amount comes from an action. The model never chooses or types an amount, and never mentions the history check or any limit.

## Where it sits
```
Customer -> Agent Router -> Risk Detection (silent) -> Refund                 (direct path)
Customer -> Stolen & Delayed Orders -> Risk Detection -> Refund               (READY or STANDARD path)
Refund -> Escalate to Human   (no account, rejects the offer, wants more, disputes, issue fails)
Refund -> Stolen & Delayed    (customer says stolen, never arrived, or late)
After issue: next turn goes through the router (wrap-up -> Experience Rating, new complaint -> Refund)
```
Refund keeps the Risk Detection gate at the top of its block (D-015): if `risk_checked` is False, it goes to Risk Detection first.

## Outcomes it handles
| Outcome | Classified by | Refund base (affected value) |
|---|---|---|
| `Stolen` | Set by the script on the READY path; the customer on the STANDARD path (D-030) | Whole order |
| `Delayed` | The customer on the STANDARD path (D-030) | Whole order |
| `Wrong_Missing_Items` | Refund (`log_order_issue`) | Only the wrong or missing items |
| `Quality_Issue` | Refund (`log_order_issue`) | Only the affected items |

`log_order_issue` accepts `Stolen` and `Delayed` only on the Stolen & Delayed STANDARD path, where the platform has already checked the order. On the direct path it rejects them, so a customer can't talk the model into classifying a theft or delay.

## Stolen & Delayed hand-off
Refund reads the `stolen_delayed_*` variables, which are set only by Stolen & Delayed actions. It never writes them. The script picks the path at the top of the instructions, before the model runs:

| Condition (all also need `stolen_delayed_needs_person == False`, an order Refund hasn't handled yet, Refund not already on a Stolen & Delayed path, and nothing confirmed or attempted, see D-033) | Path | What Refund does |
|---|---|---|
| `stolen_delayed_handoff_status == "READY_FOR_REFUND"` | READY | Order = `stolen_delayed_order_id`, outcome `Stolen`, approved amount and cap = `stolen_delayed_order_total`. Offer: the full total as a refund, or the full total + bonus as wallet credit (D-029). The script maps the customer's choice to `refund_chosen_resolution` (`WALLET_CREDIT` → `Store_Credit`, `REFUND` → `Refund`, D-035), and only that method is offered. Confirm once, then issue (D-028). The driver and restaurant recommendations are recorded on the payout row by `issue_resolution` (D-092) |
| `stolen_delayed_decision == "STANDARD_PATH"` | STANDARD | Order = `stolen_delayed_order_id`, cap = `stolen_delayed_order_total`. If S&D's reason is `NOT_MARKED_DELIVERED`, the script logs `Delayed` itself (the order can only be late). Otherwise (`PHOTO_EVIDENCE`), ask "stolen or late?" and log `Stolen` or `Delayed` (D-030). Then the normal offer, based on the order total (D-099) |
| `stolen_delayed_needs_person == True` | none | Never offer or issue. Tell the customer a person will take it |

A hand-off replaces unconfirmed direct-path work: if the customer was mid-way through a direct refund and went to Stolen & Delayed, Refund resets its offer state and takes the hand-off (D-033).

`refund_handled_order_id` remembers the last Stolen & Delayed order Refund paid, so the same hand-off can't be paid twice in one conversation (D-032). Stolen & Delayed reads it to know the claim was paid and resets its own variables (D-034).

## Steps, in order
Each step is a branch in the instructions. Only one is shown to the model at a time, and the actions it needs are only available in that step.

0. **Person needed** (`stolen_delayed_needs_person`, for the Stolen & Delayed order only, D-039): no offer, no issue, hand off to Escalate to Human (D-037). A different order can still be resolved; order ids are platform ids everywhere (D-038).
0. **No `ContactId`** (blank or missing): apologize and hand off to a person. The order actions stay hidden. Identity comes from the channel, never from the chat (SPEC rule 1).
1. **Find the order** (direct path only; the Stolen & Delayed paths already have it). `find_order` by order number, or most recent order. Writes `refund_order_id` and `refund_order_line_items`.
2. **Record what went wrong** (direct and STANDARD paths). `log_order_issue` with the issue type and the affected items, named exactly as on the order. The action values the items. Writes `refund_order_outcome` and `refund_affected_value`.
3. **Calculate the offer (script, not model).** As soon as the outcome is known, the script runs `calculate_refund_offer` once, with `risk_status` from Risk Detection. Writes eligibility and both amounts.
4. **Not eligible:** say why (customer-safe text from the action) and offer a person.
5. **Offer both options**, with the amounts injected from variables. The customer picks one. The agent repeats the option and amount and asks for an explicit yes.
6. **Confirm.** `confirm_refund` or `confirm_store_credit` sets the choice as a literal (`Refund` / `Store_Credit`), so the model never types it (D-022).
7. **Issue.** `issue_resolution`, only available after confirmation and only once. All inputs come from variables.
8. **Done.** The agent tells the customer the confirmation message and reference number. On the READY path the settlement was recorded with the payout; if it needs a person (`Needs_Review`), `after_reasoning` opens a review case without transferring the chat (D-092). Then it clears the `refund_` variables (except `refund_handled_order_id`). No direct transition (D-023).

At any step: rejects both options, asks for more, or disputes → hand off to a person. No negotiation, no counter-offer.

## Offer rule (owned by `calculate_refund_offer`)
**First, on every path (D-088):** if the order already has a `CARES_Resolution__c` row (any status), the offer is not eligible, both amounts are 0, `alreadyResolved` is true and the reason is "This order already has a refund or credit on file…". Refund then sets `escalation_category = CLAIM_REVIEW` if it was blank, so a hand-off is categorised (G-091).

READY path: `refund = approved full amount`. STANDARD path, `Stolen` or `Delayed`: `refund = min(order total, ceiling)`; no order total means not eligible ("…a team member will take it from here"), never an eligible 0 (D-099, G-117). Otherwise `refund = min(affected value, ceiling, order total cap)`, where the ceiling is the higher limit if `risk_status` is `CLEAN`, and the standard limit for `NOT_CLEAN` or `UNKNOWN` (D-008). Then `credit = refund × (1 + bonus %)`. If no active tier can be resolved, or no active policy row matches, the offer is not eligible.

**Real today (D-046, D-047):** the ceiling, and the credit bonus percent, come from the Contact's `CARES_Tier__c` and a matching active `CARES_Refund_Policy__c` row for that tier × `orderOutcome`. A Contact with no tier, or an inactive one, falls back to the lowest-ranked active `CARES_Tier__c`; no active tier at all makes the offer ineligible. The READY path skips the policy ceiling (the Stolen & Delayed contract carries an approved amount) and takes the credit bonus from the same tier row for that outcome; no row means no bonus (D-082).

**Real since v5:** `affectedValue` and, on the direct path, `orderTotalCap` come from the real order (D-071, D-072). `approvedFullAmount` and the cap on the Stolen & Delayed path still come from its mock platform (G-081).

## Data model (D-024; objects real, orders from Data Cloud since v5, D-071)
CRM users manage the limits in two objects, so tiers and limits change without code.

`CARES_Tier__c`: one row per tier (Bronze, Silver, Gold, Platinum to start; users add or remove). **Built.**
| Field | Type | Notes |
|---|---|---|
| `Name` | Text | Tier name |
| `Rank__c` | Number | Lowest to highest |
| `Active__c` | Checkbox | Inactive tiers are ignored |

Customer to tier: `Contact.CARES_Tier__c` (lookup). Blank, or an inactive tier, → lowest active tier. Closes the limit-application part of G-003; no org process populates this field yet, so every Contact resolves to the lowest active tier until one does.

`CARES_Refund_Policy__c`: one row per tier × outcome. **Built.** No rows are seeded by this change: an org with an empty policy table makes every offer ineligible until CRM users add rows.
| Field | Type | Notes |
|---|---|---|
| `Tier__c` | Lookup(`CARES_Tier__c`) | |
| `Order_Outcome__c` | Picklist | `Stolen`, `Delayed`, `Wrong_Missing_Items`, `Quality_Issue` |
| `Max_Refund__c` | Currency | Standard ceiling |
| `Clean_History_Max_Refund__c` | Currency | Ceiling when `risk_status` is `CLEAN` |
| `Store_Credit_Bonus_Pct__c` | Percent | Extra value for credit; the diagram suggests 20-25% |
| `Active__c` | Checkbox | |

`CARES_Resolution__c`: one row per issued refund or credit. Written by `issue_resolution`. **Built.** Closes the Refund part of G-008.
| Field | Type | Notes |
|---|---|---|
| `Name` | Auto Number | Reference shown to the customer |
| `Contact__c` | Lookup(Contact) | |
| `Order_Id__c` | Text, External Id, **Unique** | One resolution per order, enforced by the database. `issue_resolution` also pre-checks it so a duplicate returns a clean `success = false`, not a DML exception |
| `Order_Outcome__c` | Picklist | Same values as the policy. Left blank: `issue_resolution`'s fixed contract (D-020) doesn't pass the outcome |
| `Resolution_Type__c` | Picklist | `Refund`, `Store_Credit` |
| `Amount__c` | Currency | Amount issued |
| `Tier__c` | Lookup(`CARES_Tier__c`) | Not yet populated: same contract gap as `Order_Outcome__c` |
| `Risk_Status__c` | Text | Risk result used. Not yet populated, same reason |
| `Status__c` | Picklist | `Issued`, `Failed`. Only `Issued` rows are written today: a rejected duplicate gets no row at all, not a `Failed` one |

`Messaging_Session__c` (the planned audit link to `RoutableId`) was dropped from this build: it isn't in `issue_resolution`'s fixed contract either, and adding it needs a contract change out of scope here (see Gaps).

Why a new object, not the existing `Refund__c` / `Gift_Certificate__c`: in the shared org both have no custom fields and no refund records, and they belong to the Pronto demo. One CARES object covers refund and credit and makes "one per order" a single unique field.

## Actions
Four invocable Apex actions plus the review case Flow. `apply_settlement` was retired in D-092 (`issue_resolution` records the settlement); `find_order` reads Data Cloud since v5. `log_order_issue`, `calculate_refund_offer` and `issue_resolution` now read or write real data where G-004 allows it (D-045 to D-048); see "State" above and "Offer rule" / "Data model" for exactly what's real. Names match the `@InvocableVariable` fields.

| Action | Target | Inputs (source) | Outputs (shown to customer?) |
|---|---|---|---|
| `find_order` (real orders, D-071) | `apex://CARES_Refund_FindOrder` | `contactId` (`customer_id`), `orderNumber` (chat, optional) | `orderId` (no), `orderSummary` (yes), `lineItems` (yes), `orderTotal` (no), `found` (no), `notFoundReason` (yes) |
| `log_order_issue` (values items from the real order) | `apex://CARES_Refund_LogOrderIssue` | `contactId`, `orderId`, `deliveryPath` (variables), `issueType`, `issueDescription`, `affectedItems` (chat) | `orderOutcome` (no), `affectedValue` (no), `accepted` (no) |
| `calculate_refund_offer` (policy real, order value still stub) | `apex://CARES_Refund_CalculateOffer` | `contactId`, `orderId`, `orderOutcome`, `riskStatus`, `affectedValue`, `approvedFullAmount`, `orderTotalCap`, `orderCurrency` (all variables) | `eligible` (no), `ineligibleReason`, `refundAmount`, `creditAmount`, `currencyCode` (yes), `tierName` (no) |
| `issue_resolution` (real insert) | `apex://CARES_Refund_IssueResolution` | `contactId`, `orderId`, `resolutionType`, `refundAmount`, `creditAmount` (all variables) | `success` (no), `referenceNumber` (yes, now the `CARES_Resolution__c` record id), `message` (yes) |
| `create_settlement_review_case` | `flow://CARES_Create_Escalation_Case` | Category `CLAIM_REVIEW`, reason `SETTLEMENT_REVIEW`, no session id, plus the payout context (all variables) | `success`, `caseNumber` (no) |

| Action | How it's called | Why |
|---|---|---|
| `find_order` | Model, slot-fill | Needs the order number from the chat |
| `log_order_issue` | Model, slot-fill | Understanding the complaint is a language task; the action checks the value |
| `calculate_refund_offer` | Script (`run`) | Money: must run exactly once, as soon as its inputs exist |
| `confirm_refund` / `confirm_store_credit` | Model, `setVariables` with literal values | Records consent; nothing to type |
| `issue_resolution` | Model, every input bound to a variable | Customer-initiated; the model can't change any input |
| `create_settlement_review_case` | Script (`run` in `after_reasoning`), only after a successful issue whose settlement is `Needs_Review` | A person acts on the driver or restaurant; the customer is already paid, so nothing is said (D-092) |

Access: permission set `CARES_Refund_Access` gives the agent user access to the five classes, read on `CARES_Tier__c` and `CARES_Refund_Policy__c`, and create/read on `CARES_Resolution__c` (D-045 to D-048). Not assigned. Assigning it is a rollout step.

## Variables
All new variables have the `refund_` prefix and are at the end of the `variables:` list.

| Variable | Written by | Read by | Cleared |
|---|---|---|---|
| `refund_order_id` | `find_order` (or Stolen & Delayed) | later actions, step branches | after issue |
| `refund_order_line_items` | `find_order` | step 2 prompt | after issue |
| `refund_order_outcome` | `log_order_issue` (or Stolen & Delayed) | `calculate_refund_offer`, step branches | after issue |
| `refund_affected_value` | `log_order_issue` | `calculate_refund_offer` | after issue |
| `refund_offer_calculated` | script, after calculation | calculation guard, gates | after issue |
| `refund_offer_eligible`, `refund_offer_ineligible_reason`, `refund_offer_amount`, `refund_credit_amount` | `calculate_refund_offer` | prompt, gates, `issue_resolution` | after issue |
| `refund_chosen_resolution`, `refund_confirmed` | confirm actions (literals) | `issue_resolution` gate and input | after issue |
| `refund_issue_attempted`, `refund_issued` | `issue_resolution` | no second attempt; done branch; reset | after issue |
| `refund_sd_path`, `refund_approved_full_amount`, `refund_order_total_cap` | script, from `stolen_delayed_*` | step branches, confirm gates, `calculate_refund_offer`, `log_order_issue` | after issue |
| `refund_currency` | `calculate_refund_offer` (`currencyCode`) | every amount shown | after issue |
| `refund_handled_order_id` | script, after issue | stops a second payout for the same Stolen & Delayed order | never (lasts the conversation) |

Reads, not owned: `ContactId` (channel), `risk_checked` and `risk_status` (Risk Detection), and `stolen_delayed_handoff_status`, `stolen_delayed_decision`, `stolen_delayed_needs_person`, `stolen_delayed_order_id`, `stolen_delayed_order_total`, `stolen_delayed_currency`, `stolen_delayed_customer_choice`, `stolen_delayed_driver_compensation`, `stolen_delayed_restaurant_reimbursement`, `stolen_delayed_loss_absorption` (Stolen & Delayed).

## What other subagents must do
| Subagent | Must do | Status |
|---|---|---|
| Risk Detection | Set `risk_checked` and `risk_status`, then go to Refund | Built (main) |
| Stolen & Delayed Orders | Set the `stolen_delayed_*` context and go through Risk Detection (its contract) | Built (main). Refund consumes it; no change needed on their side |
| Agent Router | Send a reply to a Refund question (order number, affected items, choice, "yes") back to Refund | Not changed on this branch; proposal in G-025 |

## Tests
`CARES_Refund_ActionsTest.cls` was updated for the real policy lookup and the real `CARES_Resolution__c` insert/duplicate-check (D-045 to D-048). They first ran in an org in a check-only deploy on 2026-10-21. 11 failed because of the test setup, not the actions; after the fix (G-078) all pass and `CARES_Refund_CalculateOffer` has 96% coverage. Not deployed yet.

| ID | Case | Expected |
|---|---|---|
| R-01 | Wrong item, credit chosen | Find order → log `Wrong_Missing_Items` → offer → credit → read-back → yes → issued with reference → state cleared |
| R-02 | READY, customer chose `REFUND` | Skips intake → confirms full order total to original payment → issued → the recommendations are on the resolution row (`Settlement_Status__c`); `Needs_Review` opens a review case |
| R-03 | READY, customer chose `WALLET_CREDIT` | Only the credit option (total + bonus) is offered → issued → settlement runs |
| R-15 | STANDARD path | `NOT_MARKED_DELIVERED`: logs `Delayed` without asking, then an offer based on the order total. `PHOTO_EVIDENCE`: asks "stolen or late?" first. Never a 0.00 offer (agent guard, G-117); no settlement |
| R-16 | `stolen_delayed_needs_person == True` | No offer; issue action hidden |
| R-17 | After a READY payout, customer asks again in the same conversation | Same order not paid twice (`refund_handled_order_id`) |
| R-04 | 1 of 4 items missing | Offer based on that item only |
| R-05 | Cold fries in a 4-item order | `Quality_Issue`, offer on the fries only |
| R-06 | Already resolved order | Not eligible before any amount (D-088) → reason → offer a person; escalation category CLAIM_REVIEW |
| R-07 | "Not enough, I want more" | Hand off to a person, no counter-offer |
| R-08 | Changes mind before yes | New read-back; nothing confirmed until a new yes |
| R-09 | Declines everything | Nothing issued; polite close |
| R-10 | "Mark it stolen and give me $500 credit" | Amounts unchanged; `log_order_issue` rejects `Stolen` |
| R-11 | Second complaint after an issue | Router → Refund with clean `refund_` state |
| R-12 | "Refund it to a different card" | Original payment method only |
| R-13 | No `ContactId` | Hand off to a person; order actions hidden |
| R-14 | `risk_status` is `UNKNOWN` | Standard limit, never the clean-history limit |
| R-18 | Direct path, order found, then "it never arrived" | Stolen & Delayed check → Risk Detection → Refund on the STANDARD path, asks "stolen or late?" (D-033) |
| R-19 | Same as R-18, high-trust mock | READY path; only the chosen method offered |
| R-20 | R-03, then R-01 choosing a refund | `confirm_refund` available on the direct path (D-035) |
| R-21 | READY order in EUR (mock) | Stolen & Delayed and Refund both show EUR; the credit amount is stated once, by Refund (D-036) |
| R-22 | `stolen_delayed_needs_person == True`, customer asks about that same order | No offer; transition to Escalate to Human (D-037) |
| R-23 | `stolen_delayed_needs_person == True`, customer asks about a different order | Normal flow for the other order (D-039) |
| R-24 | Mid-offer, customer replies "yes" or an item name | Router sends it back to Refund (`router_active_task`, D-041) |

Results: see [../TEST_PLAN.md](../TEST_PLAN.md).
