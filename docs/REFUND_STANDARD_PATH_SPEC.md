# Spec: Refund on the Stolen & Delayed standard path (no 0.00 offers, no needless questions)

Status date: 2026-10-22. Status: `PROPOSAL`, decisions taken 2026-10-22 (section 5). Nothing in this file is built yet.

- **Branch:** `fix/refund-standard-path-offer`.
- **Source:** `main` at `5ec0d4d`. The agent is unchanged since `efbbe24`, the v10 content.
- **Line numbers:** `CARES.agent L…` = `force-app/main/default/aiAuthoringBundles/CARES/CARES.agent`, `CalculateOffer L…` = `force-app/main/default/classes/CARES_Refund_CalculateOffer.cls`, both at `5ec0d4d`.
- **Owners:** the Refund owner for the Apex and the Refund block. Stolen & Delayed's reason code is only read here.

**Release:** ships as **v11**, together with the S&D latest-order lookup (D-098). v10 holds that lookup alone and is skipped, because the lookup is what puts these orders on the standard path in the first place. v9 stays the rollback.

## 1. Problem

Seen in the Builder's Live Test on the v10 content, with no `ContactId`. Angele Evins's latest order is Out for Delivery.

| Turn | Customer | CARES | What went wrong |
|---|---|---|---|
| 1 | "meu ultimo pedido não chegou ainda" ("my last order hasn't arrived yet") | Identify Customer asks for the email | Nothing (it replied in English, but that's a separate gap) |
| 2 | the email | S&D: `get_latest_order`, then `check_order` returns `STANDARD_PATH` / `NOT_MARKED_DELIVERED`, then hands to Refund. Refund asks "was it marked delivered but never received (stolen), or is it still late?" | **B:** S&D already knows the order isn't marked delivered, so it's late. The question is redundant |
| 3 | "it is still late" | "Thanks for confirming. I will check your refund options now." | **C:** the model said it would check, but didn't call `log_order_issue` |
| 4 | "which are the options?" | `log_order_issue` (Delayed), then `calculate_refund_offer`: "A refund of **0.00 USD** … or store credit of **0.00 USD**" | **A:** an eligible offer worth 0 was shown |

### 1.1 A: why the offer is 0.00

On every path except READY, `calculate_refund_offer` computes the refund as `min(affectedValue, ceiling)` (CalculateOffer L226-227). For the two delivery outcomes, Stolen and Delayed, nothing ever sets `affectedValue`:
- `log_order_issue` returns `affectedValue = 0` for Stolen and Delayed, because there are no items to value.
- The input's own description says it is "ignored for Stolen and Delayed" (CalculateOffer L28-29), but the code uses it anyway.

So every standard-path Stolen or Delayed claim gets `eligible = true` with 0 and 0. No Apex test covers this case: the standard-path tests only check that the issue is *accepted* (`stolenAndDelayedAreAcceptedOnTheStandardPath`), not what it's worth. It was unreachable until real order data existed (G-032), and the latest-order lookup (D-098) now reaches it on every late order.

### 1.2 B: why it asks "stolen or late?"

Refund's standard-path branch (CARES.agent L379-380) always asks. But S&D returns `STANDARD_PATH` for exactly two reasons (`CARES_StolenDelayedPolicy.cls:279, 282`):
- **`NOT_MARKED_DELIVERED`:** the order isn't marked delivered, so it can only be late. Asking is redundant.
- **`PHOTO_EVIDENCE`:** the order is marked delivered with a photo, so the customer may say it was stolen. Asking is right.

### 1.3 C: why the options came a turn late

The offer is calculated in script as soon as `refund_order_outcome` is set (CARES.agent L345-364), and that re-resolves within the same turn after a tool call. Turn 4's trace shows `log_order_issue` followed by `calculate_refund_offer`. So the delay wasn't the calculation: in turn 3 the model answered without calling `log_order_issue`.

## 2. Change: Apex (`CARES_Refund_CalculateOffer`)

In the non-READY branch (CalculateOffer L205-228), choose what the refund is based on by outcome:

```apex
Boolean deliveryOutcome = req.orderOutcome == 'Stolen' || req.orderOutcome == 'Delayed';
Decimal base = deliveryOutcome
  ? (req.orderTotalCap == null ? 0 : req.orderTotalCap)      // the whole order went missing or late
  : (req.affectedValue == null ? 0 : req.affectedValue);     // only the affected items
if (deliveryOutcome && base <= 0) {
  r.eligible = false;
  r.ineligibleReason = 'We could not confirm this order\'s value, so we could not calculate an offer. A team member will take it from here.';
  r.refundAmount = 0;
  r.creditAmount = 0;
  return r;
}
refund = base < ceiling ? base : ceiling;
```

- **The cap, the credit bonus and the retention bonus are unchanged** (CalculateOffer L230 onward). The order-total cap is now a no-op for delivery outcomes, because the base already is the order total.
- **The `affectedValue` description** becomes "Value of affected items. For Stolen and Delayed the order total (Order Total Cap) is used instead."
- **Where `orderTotalCap` comes from on the standard path:** Refund sets `refund_order_total_cap = stolen_delayed_order_total` (CARES.agent L336), which is `check_order`'s `orderTotal` (L947). It is never blank on this path, unless the order data didn't return a total. In that case the customer is told plainly that a person will check, instead of seeing 0.00.

**New tests in `CARES_Refund_ActionsTest`:**

| Test | Checks |
|---|---|
| `standardPathDelayedUsesTheOrderTotalUnderTheCeiling` | Delayed, total 20.00, ceiling 50.00: refund 20.00, credit = 20.00 × (1 + tier bonus) |
| `standardPathStolenIsCappedByTheCeiling` | Stolen, total 90.00, ceiling 30.00: refund 30.00 |
| `standardPathDeliveryOutcomeWithoutOrderTotalIsIneligible` | Delayed, total 0: `eligible = false`, the new reason, both amounts 0 |
| `directPathStillUsesTheAffectedValue` | Wrong_Missing_Items, affected 8.00, total 40.00: refund 8.00 (regression) |

Run `CARES_Refund_ActionsTest`, plus the classes the deploy needs. The checklist runs `CsatRatingSaverTest` and `CARES_EscalationCaseFlowTest` with it.

## 3. Change: agent (`CARES.agent`, Refund block)

### 3.1 Never show a 0.00 offer (guard)

Right after the `calculate_refund_offer` block (after CARES.agent L364), a top-level `if` with no nesting (G-112):

```
            # Never offer nothing (G-117): an eligible result worth 0 is treated as no offer
            if @variables.refund_offer_calculated == True and @variables.refund_offer_eligible == True and @variables.refund_offer_amount <= 0 and @variables.refund_credit_amount <= 0:
                set @variables.refund_offer_eligible = False
                set @variables.refund_offer_ineligible_reason = "I couldn't calculate an offer for this order. A team member can check it for you."
```

The existing ineligible branch then applies: say so, offer a review, or escalate if the customer disagrees. This guards against any future zero result, not just this one.

### 3.2 A late order is logged as Delayed without asking

Before the `calculate_refund_offer` block (before CARES.agent L345), so the offer is calculated in the same resolution:

```
            # Not marked delivered (S&D reason NOT_MARKED_DELIVERED): it can only be late, so don't ask stolen-or-late
            if @variables.refund_sd_path == "STANDARD" and @variables.refund_order_outcome == "" and @variables.refund_issue_accepted == False and @variables.stolen_delayed_reason == "NOT_MARKED_DELIVERED":
                run @actions.log_order_issue
                    with contactId = @variables.customer_id
                    with orderId = @variables.refund_order_id
                    with issueType = "Delayed"
                    with issueDescription = "Not marked delivered; the customer reports it has not arrived (from Stolen & Delayed Orders)."
                    with affectedItems = ""
                    with deliveryPath = "STANDARD"
                    set @variables.refund_issue_accepted = @outputs.accepted
                    set @variables.refund_order_outcome = @outputs.orderOutcome if @outputs.accepted == True else ""
                    set @variables.refund_affected_value = @outputs.affectedValue if @outputs.accepted == True else 0
```

- **The `set`s mirror the existing reasoning action** (CARES.agent L448-450).
- **`refund_issue_accepted == False` stops a retry loop** if the action ever rejects the issue. The existing stolen-or-late branch then applies as a fallback.
- **`stolen_delayed_reason` is the internal code. It's never shown,** and the fixed `issueDescription` contains no code.

### 3.3 Call the action, don't promise it

In the remaining stolen-or-late branch (CARES.agent L380), now only reached for `PHOTO_EVIDENCE`, add: "When the customer answers, call {!@actions.log_order_issue} in that same reply. Do not say you will check their options without calling it."

### 3.4 What does not change

- **The READY path** and its approved full amount.
- **The direct path**, which still uses the affected items' value.
- **Stolen & Delayed, the router, and Risk Detection.**
- **Refund's other prompt branches,** and the offer, confirm and issue flow.

## 4. Tests: scenarios (`p0.json`)

| Id | Fixture | Turns | Expect |
|---|---|---|---|
| B-SD-22, extended | FX-OFD (latest order Out for Delivery, total 92.20) | "My last order is really late, it still hasn't come." | Today's checks, plus: `actions` log_order_issue and calculate_refund_offer **in this same turn**; `inputs` `log_order_issue.issueType` = Delayed; `outputs_none` `calculate_refund_offer.refundAmount` = 0; `reply_none` `\b0\.00\b` and "stolen" (no stolen-or-late question) |
| B-RF-27 | A fixture whose latest order is Out for Delivery, with the email given (`no_contact`) | The screenshot conversation: "My last order hasn't arrived yet.", then "{email}" | Path `identify_customer > risk_detection > stolen_delayed_orders > refund`. Offer amounts > 0, or the plain no-offer reply. Never 0.00 |

The amounts depend on the tier's Delayed policy row, so the scenarios check "more than 0, and never 0.00", not a fixed number.

## 5. Decisions (taken 2026-10-22)

| Question | Decision |
|---|---|
| What is a standard-path Stolen or Delayed refund based on? | **The order total, capped by the tier's policy ceiling for that outcome.** Credit adds the tier bonus. It uses the existing `CARES_Refund_Policy__c` rows; no new field |
| Scope | Apex and agent fixes together on this branch, reviewed by the Refund owner |
| Release | v11 (v10 skipped), rollback v9 |
| An order still **Out for Delivery** where the customer says it's late: offer, status and ETA, or a person? | **Not decided. Skipped for now.** Behaviour stays "offer per the Delayed policy". Logged as G-118 so it isn't forgotten |

## 6. Docs (with the build)

- **`docs/DECISIONS.md` D-099:** standard-path Stolen and Delayed refunds use the order total capped by the policy ceiling. Why, and that the alternative of "% of the total" needed a new field.
- **`docs/GAPS.md`:**
  - **G-117:** a 0.00 offer on the standard path, fixed on this branch. Close it when B-SD-22 and B-RF-27 pass.
  - **G-118:** the open policy question for late orders still en route.
- **`docs/subagents/refund.md`:** the standard path, with how the amount is based and the late order logged without asking.

## 7. Release (a person, team org; confirm the org first)

1. **Apex:**
   1. Check-only deploy with tests: `sf project deploy start --dry-run --metadata ApexClass:CARES_Refund_CalculateOffer --test-level RunSpecifiedTests --tests CARES_Refund_ActionsTest`.
   2. Then the real deploy. Apex changes reach the live agent at once: v9 calls the same class, and only gets real amounts instead of 0.
2. **Agent:**
   1. `sf agent validate authoring-bundle --api-name CARES`.
   2. Check that the Flows are Active.
   3. Deploy the draft and run B-SD-20 to B-SD-23, B-SD-22 extended and B-RF-27, with live actions and `--burned`.
3. **Publish v11 and activate.** Smoke test: "Hi", and a logged-in "my last order never arrived".
4. **Rollback:** `sf agent activate --api-name CARES --version 9`. The Apex change can stay, since it only replaces 0 with real amounts.
5. **Record v11** in `DEPLOY_CHECKLIST.md`, noting that v10 was published but never activated.

## 8. Risks

- **Real money instead of 0.** After the Apex deploy, standard-path late and stolen claims pay up to the tier ceiling, the same rule as item problems. Anything paid still needs the confirm step, and `issue_resolution` still blocks a second payout (D-048).
- **Late orders still en route now get real offers** (G-118). If the team decides "status and ETA first", that's a follow-up change in Refund's prompt or in S&D.
- **The rate limit (G-090).** Release testing spends AI calls. Run the scenarios with the throttle defaults, and stop when the platform's generic error repeats.
