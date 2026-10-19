# Node spec: Refund

How the Refund subagent works as built on branch `feature/refund-subagent`. Decisions: D-019 to D-026 in [../DECISIONS.md](../DECISIONS.md). Gaps: G-023 to G-030 in [../GAPS.md](../GAPS.md).

State: built with **stub actions** (hardcoded values, no data read or written). Compiled, dry-run deployed, agent validated. **Not deployed.** Last updated: 2026-10-19.

## In one paragraph
Refund resolves an economic order complaint. It finds the order, records what went wrong, and then the script calculates two options: a fixed refund to the original payment method, or store credit worth more. The customer picks one and confirms the exact amount, and only then is it issued, once per order. Every amount comes from an action. The model never chooses or types an amount, and never mentions the history check or any limit.

## Where it sits
```
Customer -> Agent Router -> Risk Detection (silent) -> Refund
                     Stolen & Delayed Orders -------> Refund   (sets order + Stolen/Delayed)
Refund -> Escalate to Human   (no account, rejects the offer, wants more, disputes, issue fails)
Refund -> Stolen & Delayed    (customer says stolen, never arrived, or late)
After issue: next turn goes through the router (wrap-up -> Experience Rating, new complaint -> Refund)
```
Refund keeps the Risk Detection gate at the top of its block (D-015): if `risk_checked` is False, it goes to Risk Detection first.

## Outcomes it handles
| Outcome | Classified by | Refund base (affected value) |
|---|---|---|
| `Stolen` | Stolen & Delayed Orders | Whole order |
| `Delayed` | Stolen & Delayed Orders | Whole order |
| `Wrong_Missing_Items` | Refund (`log_order_issue`) | Only the wrong or missing items |
| `Quality_Issue` | Refund (`log_order_issue`) | Only the affected items |

`log_order_issue` rejects `Stolen` and `Delayed`, so a customer can't talk the model into classifying a theft or delay.

## Steps, in order
Each step is a branch in the instructions. Only one is shown to the model at a time, and the actions it needs are only available in that step.

0. **No `ContactId`** (blank or missing): apologize and hand off to a person. The order actions stay hidden. Identity comes from the channel, never from the chat (SPEC rule 1).
1. **Find the order.** `find_order` by order number, or most recent order. Writes `refund_order_id` and `refund_order_line_items`.
2. **Record what went wrong.** `log_order_issue` with the issue type and the affected items, named exactly as on the order. The action values the items. Writes `refund_order_outcome` and `refund_affected_value`.
3. **Calculate the offer (script, not model).** As soon as the outcome is known, the script runs `calculate_refund_offer` once, with `risk_status` from Risk Detection. Writes eligibility and both amounts.
4. **Not eligible:** say why (customer-safe text from the action) and offer a person.
5. **Offer both options**, with the amounts injected from variables. The customer picks one. The agent repeats the option and amount and asks for an explicit yes.
6. **Confirm.** `confirm_refund` or `confirm_store_credit` sets the choice as a literal (`Refund` / `Store_Credit`), so the model never types it (D-022).
7. **Issue.** `issue_resolution`, only available after confirmation and only once. All inputs come from variables.
8. **Done.** The agent tells the customer the confirmation message and reference number. Then `after_reasoning` clears all `refund_` variables. No direct transition (D-023).

At any step: rejects both options, asks for more, or disputes → hand off to a person. No negotiation, no counter-offer.

## Offer rule (owned by `calculate_refund_offer`)
`refund = min(affected value, ceiling)`, where the ceiling is the higher limit if `risk_status` is `CLEAN`, and the standard limit for `NOT_CLEAN` or `UNKNOWN` (D-008). Then `credit = refund × (1 + bonus %)`. If no active policy row matches, or the order already has a resolution, the offer is not eligible.

**Stub today:** always eligible, refund 15.00, credit 18.00 USD.

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
All four are invocable Apex **stubs** (D-020). Names match the `@InvocableVariable` fields.

| Action | Target | Inputs (source) | Outputs (shown to customer?) |
|---|---|---|---|
| `find_order` | `apex://CARES_Refund_FindOrder` | `contactId` (`ContactId`), `orderNumber` (chat, optional) | `orderId` (no), `orderSummary` (yes), `lineItems` (yes), `found` (no) |
| `log_order_issue` | `apex://CARES_Refund_LogOrderIssue` | `orderId` (variable), `issueType`, `issueDescription`, `affectedItems` (chat) | `orderOutcome` (no), `affectedValue` (no), `accepted` (no) |
| `calculate_refund_offer` | `apex://CARES_Refund_CalculateOffer` | `contactId`, `orderId`, `orderOutcome`, `riskStatus`, `affectedValue` (all variables) | `eligible` (no), `ineligibleReason`, `refundAmount`, `creditAmount`, `currencyCode` (yes), `tierName` (no) |
| `issue_resolution` | `apex://CARES_Refund_IssueResolution` | `contactId`, `orderId`, `resolutionType`, `refundAmount`, `creditAmount` (all variables) | `success` (no), `referenceNumber` (yes), `message` (yes) |

| Action | How it's called | Why |
|---|---|---|
| `find_order` | Model, slot-fill | Needs the order number from the chat |
| `log_order_issue` | Model, slot-fill | Understanding the complaint is a language task; the action checks the value |
| `calculate_refund_offer` | Script (`run`) | Money: must run exactly once, as soon as its inputs exist |
| `confirm_refund` / `confirm_store_credit` | Model, `setVariables` with literal values | Records consent; nothing to type |
| `issue_resolution` | Model, every input bound to a variable | Customer-initiated; the model can't change any input |

Access: permission set `CARES_Refund_Access` gives the agent user access to the four classes. Not assigned. Assigning it is a rollout step.

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

Reads, not owned: `ContactId` (channel), `risk_checked` and `risk_status` (Risk Detection).

## What other subagents must do
| Subagent | Must do | Status |
|---|---|---|
| Risk Detection | Set `risk_checked` and `risk_status`, then go to Refund | Built (main) |
| Stolen & Delayed Orders | For Stolen or Delayed: set `refund_order_id` and `refund_order_outcome` from its own action output, then go to Refund | Placeholder; not wired (G-026) |
| Agent Router | Send a reply to a Refund question (order number, affected items, choice, "yes") back to Refund | Not changed on this branch; proposal in G-025 |

## Tests
| ID | Case | Expected |
|---|---|---|
| R-01 | Wrong item, credit chosen | Find order → log `Wrong_Missing_Items` → offer → credit → read-back → yes → issued with reference → state cleared |
| R-02 | Stolen hand-off | Arrives with order + `Stolen` → skips intake → offer on whole order |
| R-03 | Delayed hand-off | Same as R-02 with `Delayed` |
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

Results: see [../TEST_PLAN.md](../TEST_PLAN.md).
