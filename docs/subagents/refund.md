# Node spec: Refund

How the Refund subagent works as built on branch `feature/refund-subagent`. Owner: @lucasmpalomanes (D-027). Decisions: D-019 to D-032 in [../DECISIONS.md](../DECISIONS.md). Gaps: G-023 to G-033 in [../GAPS.md](../GAPS.md). Replaces the hand-off brief that was here; its contract is in "Stolen & Delayed hand-off" below.

State: built with **stub actions** (hardcoded values, no data read or written). Compiled, dry-run deployed, agent validated. **Not deployed.** Last updated: 2026-10-19.

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
| `stolen_delayed_handoff_status == "READY_FOR_REFUND"` | READY | Order = `stolen_delayed_order_id`, outcome `Stolen`, approved amount and cap = `stolen_delayed_order_total`. Offer: the full total as a refund, or the full total + bonus as wallet credit (D-029). The script maps the customer's choice to `refund_chosen_resolution` (`WALLET_CREDIT` → `Store_Credit`, `REFUND` → `Refund`, D-035), and only that method is offered. Confirm once, then issue (D-028). Then `apply_settlement` with the driver and restaurant recommendations (D-031) |
| `stolen_delayed_decision == "STANDARD_PATH"` | STANDARD | Order = `stolen_delayed_order_id`, cap = `stolen_delayed_order_total`. Ask "stolen or late?" and log `Stolen` or `Delayed` (D-030). Then the normal offer, capped at the order total |
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
8. **Done.** The agent tells the customer the confirmation message and reference number. On the READY path, `after_reasoning` then runs `apply_settlement`. Then it clears the `refund_` variables (except `refund_handled_order_id`). No direct transition (D-023).

At any step: rejects both options, asks for more, or disputes → hand off to a person. No negotiation, no counter-offer.

## Offer rule (owned by `calculate_refund_offer`)
READY path: `refund = approved full amount`. Otherwise `refund = min(affected value, ceiling, order total cap)`, where the ceiling is the higher limit if `risk_status` is `CLEAN`, and the standard limit for `NOT_CLEAN` or `UNKNOWN` (D-008). Then `credit = refund × (1 + bonus %)`. If no active policy row matches, or the order already has a resolution, the offer is not eligible.

**Stub today:** always eligible. Refund is 15.00 (or the approved full amount), capped at the order total; credit is refund + 20%. USD only.

## Planned data model (not built, D-024)
CRM users manage the limits in two objects, so tiers and limits change without code.

`CARES_Tier__c`: one row per tier (Bronze, Silver, Gold, Platinum to start; users add or remove).
| Field | Type | Notes |
|---|---|---|
| `Name` | Text | Tier name |
| `Rank__c` | Number | Lowest to highest |
| `Active__c` | Checkbox | Inactive tiers are ignored |

Customer to tier: `Contact.CARES_Tier__c` (lookup). Blank → lowest active tier. Closes G-003 when built.

`CARES_Refund_Policy__c`: one row per tier × outcome.
| Field | Type | Notes |
|---|---|---|
| `Tier__c` | Lookup(`CARES_Tier__c`) | |
| `Order_Outcome__c` | Picklist | `Stolen`, `Delayed`, `Wrong_Missing_Items`, `Quality_Issue` |
| `Max_Refund__c` | Currency | Standard ceiling |
| `Clean_History_Max_Refund__c` | Currency | Ceiling when `risk_status` is `CLEAN` |
| `Store_Credit_Bonus_Pct__c` | Percent | Extra value for credit; the diagram suggests 20-25% |
| `Active__c` | Checkbox | |

`CARES_Resolution__c`: one row per issued refund or credit. Written by `issue_resolution`. Closes the Refund part of G-008.
| Field | Type | Notes |
|---|---|---|
| `Name` | Auto Number | Reference shown to the customer |
| `Contact__c` | Lookup(Contact) | |
| `Order_Id__c` | Text, External Id, **Unique** | One resolution per order, enforced by the database |
| `Order_Outcome__c` | Picklist | Same values as the policy |
| `Resolution_Type__c` | Picklist | `Refund`, `Store_Credit` |
| `Amount__c` | Currency | Amount issued |
| `Tier__c` | Lookup(`CARES_Tier__c`) | Tier at time of issue |
| `Risk_Status__c` | Text | Risk result used |
| `Messaging_Session__c` | Lookup(MessagingSession) | From `RoutableId`, for audit |
| `Status__c` | Picklist | `Issued`, `Failed` |

Why a new object, not the existing `Refund__c` / `Gift_Certificate__c`: in the shared org both have no custom fields and no refund records, and they belong to the Pronto demo. One CARES object covers refund and credit and makes "one per order" a single unique field.

## Actions
All five are invocable Apex **stubs** (D-020). Names match the `@InvocableVariable` fields.

| Action | Target | Inputs (source) | Outputs (shown to customer?) |
|---|---|---|---|
| `find_order` | `apex://CARES_Refund_FindOrder` | `contactId` (`ContactId`), `orderNumber` (chat, optional) | `orderId` (no), `orderSummary` (yes), `lineItems` (yes), `found` (no) |
| `log_order_issue` | `apex://CARES_Refund_LogOrderIssue` | `orderId`, `deliveryPath` (variables), `issueType`, `issueDescription`, `affectedItems` (chat) | `orderOutcome` (no), `affectedValue` (no), `accepted` (no) |
| `calculate_refund_offer` | `apex://CARES_Refund_CalculateOffer` | `contactId`, `orderId`, `orderOutcome`, `riskStatus`, `affectedValue`, `approvedFullAmount`, `orderTotalCap`, `orderCurrency` (all variables) | `eligible` (no), `ineligibleReason`, `refundAmount`, `creditAmount`, `currencyCode` (yes), `tierName` (no) |
| `issue_resolution` | `apex://CARES_Refund_IssueResolution` | `contactId`, `orderId`, `resolutionType`, `refundAmount`, `creditAmount` (all variables) | `success` (no), `referenceNumber` (yes), `message` (yes) |
| `apply_settlement` | `apex://CARES_Refund_ApplySettlement` | `orderId`, `driverCompensation`, `restaurantReimbursement`, `lossAbsorption` (all variables) | `success` (no) |

| Action | How it's called | Why |
|---|---|---|
| `find_order` | Model, slot-fill | Needs the order number from the chat |
| `log_order_issue` | Model, slot-fill | Understanding the complaint is a language task; the action checks the value |
| `calculate_refund_offer` | Script (`run`) | Money: must run exactly once, as soon as its inputs exist |
| `confirm_refund` / `confirm_store_credit` | Model, `setVariables` with literal values | Records consent; nothing to type |
| `issue_resolution` | Model, every input bound to a variable | Customer-initiated; the model can't change any input |
| `apply_settlement` | Script (`run` in `after_reasoning`), READY path only, after a successful issue | Driver pay and restaurant reimbursement depend on the refund actually happening (SD-D2) |

Access: permission set `CARES_Refund_Access` gives the agent user access to the five classes. Not assigned. Assigning it is a rollout step.

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
| ID | Case | Expected |
|---|---|---|
| R-01 | Wrong item, credit chosen | Find order → log `Wrong_Missing_Items` → offer → credit → read-back → yes → issued with reference → state cleared |
| R-02 | READY, customer chose `REFUND` | Skips intake → confirms full order total to original payment → issued → `apply_settlement` runs with the recommendations |
| R-03 | READY, customer chose `WALLET_CREDIT` | Only the credit option (total + bonus) is offered → issued → settlement runs |
| R-15 | STANDARD path | Asks "stolen or late?" → logs it → offer capped at the order total; no settlement |
| R-16 | `stolen_delayed_needs_person == True` | No offer; issue action hidden |
| R-17 | After a READY payout, customer asks again in the same conversation | Same order not paid twice (`refund_handled_order_id`) |
| R-04 | 1 of 4 items missing | Offer based on that item only |
| R-05 | Cold fries in a 4-item order | `Quality_Issue`, offer on the fries only |
| R-06 | Already resolved order | Not eligible → reason → offer a person |
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
