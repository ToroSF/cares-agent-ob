# Spec: Stolen & Delayed looks up the customer's latest order

Status date: 2026-10-22. Status: **built on this branch** (D-098, G-116). Local compile and `sf agent validate authoring-bundle` pass; not deployed, published or activated (section 5).

- **Branch:** `fix/sd-latest-order`.
- **Source:** `main` at `edc310e` (CARES v9 Active, v8 is the rollback).
- **Line numbers:** `L…` is `force-app/main/default/aiAuthoringBundles/CARES/CARES.agent` at `edc310e`.
- **Owner:** Stolen & Delayed owner (SPEC §3). The new variables go in the shared `variables` block, and the two per-issue reset lists (Refund, Risk Detection) get three lines each, so the Refund and Risk Detection owners review those lines.

Out of scope: replying in the customer's language (seen in the same test, R-12). That's a separate change.

## 1. Problem

Seen on v9 in Preview, with no `ContactId`:

| Turn | Customer | CARES |
|---|---|---|
| 1 | "meu ultimo pedido não chegou" ("my last order didn't arrive") | Delivery-problem route, then Risk Detection, then Identify Customer asks for the email. Correct |
| 2 | the account email | Identify Customer finds the contact, then Risk Detection runs the check, then **Stolen & Delayed asks "please provide the order number (PR-…)"** |

The customer is known and said "last order", but Stolen & Delayed still asks for a number. The same happens to a logged-in customer (`ContactId` set). Every whole-order claim pays this extra turn, and a customer who doesn't know their order number gets stuck.

**Cause:** Stolen & Delayed has one order action, `check_order` (`evaluate_delivery_exception`, L878), and it needs an order number. The prompt branch at L854-855 says "Ask for the order number and a short description of what happened… Then call `check_order`". Item problems don't have this problem since R-D10: they go to Refund, whose `find_order` takes a blank number.

## 2. Which existing action to reuse

There are two actions that take a blank number as "the most recent order":

| Action | Apex | Which order a blank number returns | Fit for S&D |
|---|---|---|---|
| Refund's `find_order` | `CARES_Refund_FindOrder` calls `CARES_OrderData.find(contactId, orderNumber, true)` (`CARES_Refund_FindOrder.cls:56`) | The most recent **Delivered** order (`deliveredOnly`, `CARES_OrderData.cls:54-55, 82`) | **No.** For a late order (Out for Delivery, Picked Up), it skips it and returns an older delivered order. S&D would check the wrong order |
| Order Status's `get_order_status` | `CARES_Order_GetStatus` calls `CARES_OrderData.find(contactId, orderNumber, false)` (`CARES_Order_GetStatus.cls:50`) | The most recent order of **any** status | **Yes.** It's the same lookup S&D's own source uses (`CARES_StolenDelayedOrderSource.cls:24`, `find(…, false)`). It's read-only, and the agent user already runs it in Order Status |

**Decision: S&D reuses `CARES_Order_GetStatus`.** No Apex, Flow or permission change: it's the same target, declared again in the S&D block, the same way other actions are declared per subagent.

## 3. Change (`CARES.agent`)

### 3.1 Variables (end of `variables:`)

```
stolen_delayed_latest_checked: mutable boolean = False
    description: "Stolen & Delayed: True once the customer's most recent order was looked up for this issue. Set only by the script."
stolen_delayed_latest_order_id: mutable string = ""
    description: "Stolen & Delayed: Pronto order id (PR-...) of the customer's most recent order, any status. Set only by the script."
stolen_delayed_latest_order_summary: mutable string = ""
    description: "Stolen & Delayed: order, restaurant, status and time of that order, from Order Status's lookup. Named back to the customer."
```

Add all three to every reset of S&D state:
- Refund's per-issue reset (L243 onward)
- Risk Detection's per-issue reset (L941 onward)
- S&D's paid-claim reset (L720-737)

The latest order is looked up again for each new issue.

### 3.2 Look up the latest order, in script, once per issue

At the end of S&D's `before_reasoning`, after `set @variables.router_active_task = "STOLEN_DELAYED"` (L738):

```
        # The customer is known: name their most recent order instead of asking for a number. Any status:
        # a late order is Out for Delivery, not Delivered (Order Status's lookup, not Refund's find_order)
        if @variables.customer_id != "" and @variables.stolen_delayed_evaluated == False and @variables.stolen_delayed_latest_checked == False:
            run @actions.get_latest_order
                with contactId = @variables.customer_id
                with orderNumber = ""
                set @variables.stolen_delayed_latest_order_id = @outputs.orderId if @outputs.found == True else ""
                set @variables.stolen_delayed_latest_order_summary = @outputs.statusSummary if @outputs.found == True else ""
            set @variables.stolen_delayed_latest_checked = True
```

- **It runs in script, not as a model tool**, so it can't be skipped or called twice. That's the posture for a machine-known fact that changes what the customer is asked.
- **One `if` with `and` conditions**, no nesting (G-112).
- **It runs after a PATTERN_REVIEW escalation**, so a flagged customer never triggers it.

### 3.3 Action definition (S&D `actions:` block, next to `evaluate_delivery_exception`)

```
        get_latest_order:
            description: "Read-only. Returns the customer's most recent order of any status: order id, status and a customer-facing summary."
            target: "apex://CARES_Order_GetStatus"
            inputs:
                contactId: string
                    description: "The customer's contact id: from the channel, or from the email lookup (R-D7). Never typed by the model."
                    is_required: True
                orderNumber: string
                    description: "Blank for the most recent order."
            outputs:
                found: boolean
                    filter_from_agent: True
                orderId: string
                    filter_from_agent: True
                status: string
                    filter_from_agent: True
                statusSummary: string
                    filter_from_agent: False
                notFoundReason: string
                    filter_from_agent: True
```

Copy every output's `description` from Order Status's definition (L1418 onward). Only `statusSummary` reaches the model.

### 3.4 Prompt (replaces the branch at L854-855)

```
            if @variables.customer_id != "" and @variables.stolen_delayed_evaluated == False and @variables.stolen_delayed_lookups < 3 and @variables.stolen_delayed_latest_order_id != "":
                | The customer's most recent order is: {!@variables.stolen_delayed_latest_order_summary}
                  If the customer means that order, say which order you are checking in one short sentence, then call {!@actions.check_order} with order {!@variables.stolen_delayed_latest_order_id} and the customer's own words. Do not ask for the order number.
                  If they say it is a different order, ask for its order number and what happened, then call {!@actions.check_order} with that number.
            if @variables.customer_id != "" and @variables.stolen_delayed_evaluated == False and @variables.stolen_delayed_lookups < 3 and @variables.stolen_delayed_latest_order_id == "":
                | Ask for the order number and a short description of what happened, if you do not have them yet. Then call {!@actions.check_order} with the order number and the customer's own words.
```

- **The second branch is today's text, unchanged.** It runs when the customer has no orders, or the order data is unavailable.
- **After an `ORDER_NOT_FOUND`**, the existing branch (L856-857) still asks the customer to double-check. The latest-order branch stays shown only while `stolen_delayed_evaluated == False`, which matches today's rule.

### 3.5 What does not change

- **`check_order`:** its inputs, its 3-lookup cap (`stolen_delayed_lookups < 3`), and `available when`.
- **The claim policy** (`CARES_StolenDelayedPolicy`). A latest order that is Out for Delivery or Picked Up still gets `NOT_MARKED_DELIVERED`, then `STANDARD_PATH`, which is correct for a late order. A Delivered one goes through the full matrix as today.
- **The router, Refund, Order Status and Identify Customer.**
- **The S&D `description` (L711).** It doesn't need to mention the lookup. If it's edited, it stays at 255 characters or fewer.

## 4. Tests

New scenarios for `.claude/skills/cares-testing/scenarios/p0.json`. The runner already supports `no_contact`, `actions`, `inputs`, `no_actions` and `reply_none`. Path checks are ordered subsequences, so existing S&D scenarios keep passing: the new action only adds to `actions`.

| Id | Fixture | Turns | Expect |
|---|---|---|---|
| B-SD-20 | A high-trust customer whose latest order is Delivered (as Dore Briant on 2026-10-22; pick one with no refund on file) | "My last order never arrived. It says delivered." | `path` risk_detection > stolen_delayed_orders. `actions` get_latest_order, evaluate_delivery_exception. `inputs` `evaluate_delivery_exception.orderId` = `{latest}`. `reply_none` "order number" |
| B-SD-21 | Same kind of fixture, `no_contact: true` | "My last order never arrived.", then "{email}" | As B-SD-20, after `identify_customer` |
| B-SD-22 | FX-OFD (latest order Out for Delivery) | "My last order is really late." | `inputs` `evaluate_delivery_exception.orderId` = `{latest}`, **not** an older delivered order. The decision is the standard path (`outputs` decision `STANDARD_PATH`) |
| B-SD-23 | Same kind as B-SD-20 | "My order never arrived.", then "No, it was order {other_order}." | `evaluate_delivery_exception.orderId` = the number the customer typed |
| B-SD-24 | A contact with no orders (new fixture, or one with no `latest`) | "My last order never arrived." | `actions` get_latest_order. `reply_any` "order number". No `evaluate_delivery_exception` call with a made-up id |

**Built:**
- **New:** B-SD-20 to B-SD-23 in `p0.json`. B-SD-20, B-SD-21 and B-SD-23 use `pool:R-ONE` with `burns`. B-SD-22 uses FX-OFD.
- **B-SD-24 is not built.** No fixture has a contact with no orders. Add one to `fixtures.json` first.
- **Changed:**
  - **B-SD-02**, FX-CLEAN, "The app says delivered but I never got it.": it used to require no `check_order` and an order-number question. Now it requires `get_latest_order`, and `check_order` only with `{latest}` (`inputs_none` on any other id).
  - **B-RT-02 `expect_known`:** the same change. Its G-087 check (`no_path: refund`) stays.
- **Why that's safe:** `check_order` is read-only. A prior claim means a `CARES_Resolution__c` row (`CARES_StolenDelayedOrderSource.cls:37-42`), so checking a shared fixture's latest order uses nothing up.

Use `{latest}` from `fixtures.json` (the field the fixtures already carry). The live runs use up orders, so pass `--burned` with the orders that already have a refund.

## 5. Release (a person, team org; confirm the org first)

1. `sf agent validate authoring-bundle --api-name CARES --json`. Check that the Flows the agent calls are still Active in the repo (G-075).
2. Deploy the CARES draft. Run B-SD-20 to B-SD-24 and the S&D part of P0 on the draft, with live actions and `--burned`.
3. Publish (v10) and activate.
4. Smoke test: a logged-in "my last order never arrived".
5. Record v10 in `DEPLOY_CHECKLIST.md`.
6. **Rollback:** `sf agent activate --api-name CARES --version 9`.

## 6. Docs (with the build)

- **`docs/subagents/stolen-delayed-orders.md`:** the order step now names the latest order first, and only asks for a number when there's none or the customer means another order.
- **`docs/DECISIONS.md`:** S&D looks up the latest order with Order Status's lookup (any status), not Refund's `find_order` (Delivered only), and why.
- **`docs/GAPS.md`:** a row for "S&D asks for an order number it could look up", closed when B-SD-20 to B-SD-24 pass.

## 7. Risks

- **One more read-only Apex call** on each S&D entry with a known customer and nothing evaluated yet. It's the same Data Cloud read Order Status already does.
- **"My last order" may not be the latest order** (for example, two orders the same evening). The prompt names the order before checking it, and the customer can give another number.
- **G-114 (a Data Cloud read after uncommitted work in one call)** doesn't apply. This read runs before any write in the turn, in its own action call.
- **Mock telemetry is on, and the seeds have not been run.** The decision for a Delivered latest order may be MANUAL_REVIEW or FULL_REFUND depending on the fixture's trust. The tests assert the order id and the absence of the order-number question, not the outcome (except B-SD-22).
