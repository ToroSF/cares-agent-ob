# Spec: Refund and Stolen & Delayed on real data, and a CARES Admin app (G-091, G-081, G-098, G-031)

Status date: 2026-10-21. Status: `PROPOSAL`, decisions B-D1 to B-D3 and C-D1 `DECIDED` 2026-10-21 by @lucasmpalomanes (sections B5 and C3). Branch: `fix/refund-sd-real-data`. Source: `main` at `fe62128`. Nothing in this file is built yet.

One branch, four parts. They are built and reviewed in this order, because each part's tests assume the one before it:

| Part | Gap | What | Owner | Decisions |
|---|---|---|---|---|
| A | G-091 | Refuse a second claim on a resolved order before any offer | @lucasmpalomanes (Refund) | None needed |
| B | G-081, G-098, G-077 | Stolen & Delayed reads the real orders; the escalation Case always has the order id; transitions that fire | @rojasC10 (Stolen & Delayed) | B-D1 to B-D3 decided (section B5) |
| C | G-031, V6 item 10 | What `apply_settlement` does with the driver and restaurant recommendations | @lucasmpalomanes / Team | C-D1 decided: record on the resolution (section C3) |
| D | — | A **CARES Admin** app with tabs to view and maintain the policy records in the org | @lucasmpalomanes | D-D1 to D-D4 decided (section D2) |

Part B edits another owner's block, so @rojasC10 reviews it (CONTRIBUTING.md).

# Part A. Refuse a second claim before the offer (G-091)

## A1. Problem
A customer can claim again on an order that already has a refund or credit (a `CARES_Resolution__c` row). Today only `issue_resolution` catches this, at the very end:

1. The agent calculates and shows an offer again ("a refund of 25.00 USD…").
2. The customer accepts and confirms.
3. `issue_resolution` returns "This order already has a resolution on file" (`CARES_Refund_IssueResolution.cls`, duplicate check before the insert, D-048).
4. Refund lands in "Issuing the resolution failed", apologizes and hands off to a person.
5. The escalation Case gets a **blank category**, because Refund never sets `escalation_category`.

Shown by batch scenario **B-RF-25** in both live runs (G-091, `docs/V6_FOCUS.md` item 5). The customer is shown money they can't get, then refused. That's the failure mode POL-P02 forbids ("do not promise what you can't confirm").

The same hole is on every path:
- **Direct path:** `find_order`, then `log_order_issue`, then the offer.
- **Stolen & Delayed STANDARD path:** same as direct, after "stolen or late?".
- **Stolen & Delayed READY path:** across conversations. `refund_handled_order_id` (D-032) only lasts one session, so in a new conversation the READY hand-off passes its guard (`CARES.agent`, READY entry in `subagent refund`), and the READY branch of `calculateOne` never returns ineligible.

## A2. Change

### A2.1 Where the check lives: `calculate_refund_offer`
The check goes **at the top of `CARES_Refund_CalculateOffer.calculateOne`, before the READY / direct split**. It's the one deterministic step that every path runs before any amount reaches the customer: the script `run`s it as soon as the outcome is known (D-021). It needs no new action and no new agent branch.

- **Query:** one bulk query in `execute()`, next to the existing tier, contact and policy queries:
  ```apex
  SELECT Order_Id__c FROM CARES_Resolution__c WHERE Order_Id__c IN :orderIds WITH USER_MODE
  ```
  It uses `req.orderId`, which is required today but unused.
- **No `Status__c` filter**, the same as `issue_resolution`: any row for the order blocks. Today only `Issued` rows are written. A `Failed` row, if one is ever written, blocks too, so a person reviews it instead of a second automatic payout.
- **Access:** `CARES_Refund_Access` already grants read on `CARES_Resolution__c`, and `Order_Id__c` is a required field, so it's always readable. No permission set change.
- **Backstop:** `issue_resolution` keeps its own check, plus the unique `Order_Id__c` (D-024, D-048), for races.

### A2.2 Apex contract
| | Change |
|---|---|
| Result | New field `alreadyResolved` (Boolean). False in every other case |
| When a resolution exists | `eligible = false`, `refundAmount = 0`, `creditAmount = 0`, `alreadyResolved = true`, `ineligibleReason` = "This order already has a refund or credit on file, so I can't offer another one. A team member can check it if something looks wrong." |
| Order of checks | Resolution first, then tier, then policy, then amounts. A resolved order never shows a tier or policy message |
| Batch | Results stay in request order (existing pattern) |

### A2.3 Agent (`subagent refund`, `CARES.agent`)
- **New variable** `refund_order_already_resolved: mutable boolean = False` (prefix `refund_`, at the end of `variables:`).
  - Description: "Refund: True when the order already has a resolution, from calculate_refund_offer. Set by the script."
- **In the existing** `run @actions.calculate_refund_offer` block: `set @variables.refund_order_already_resolved = @outputs.alreadyResolved`.
- **Script rule, right after that block:**
  ```
  if @variables.refund_order_already_resolved == True and @variables.escalation_category == "":
      set @variables.escalation_category = "CLAIM_REVIEW"
  ```
  `CLAIM_REVIEW` is an existing allowed value: the escalation Flow maps it to the Case Type, Reason, Priority and queue. The check for blank keeps a stronger category set earlier (`URGENT`, `PATTERN_REVIEW`).
- **No new prompt branch:** the existing "can't offer" branch already shows `{!@variables.refund_offer_ineligible_reason}` and offers a person.
- **Action definition:** add the output `alreadyResolved: boolean` with `filter_from_agent: True`.
- **Resets:** clear `refund_order_already_resolved` wherever the other `refund_` offer variables reset: the `after_reasoning` reset, and the READY and STANDARD hand-off blocks.

### A2.4 What does not change
- **D-032 stays:** `refund_handled_order_id` still stops a same-session double payout before any query.
- **D-048 stays:** `issue_resolution` keeps its check as the backstop.
- **No new subagent**, and no change to the router or to Stolen & Delayed.

### A2.5 Out of scope (follow-ups)
- **Telling the customer earlier:** on the direct path the customer still describes the problem before hearing "already on file". No amount is shown, so this is acceptable. Checking in `find_order` would be earlier, but it would miss the READY path and duplicate the rule.
- **Writing `Status__c = Failed` rows:** never written today (see the readiness findings).

## A3. Tests

### A3.1 Apex (`CARES_Refund_ActionsTest`)
Reuse `refundUser()`, `makeTier`, `makePolicy`, `makeContact`, `offer(...)` and `issue(...)`. Add an `offer(...)` overload that takes an order id. The insert of a resolution row uses `issue(...)` as `refundUser()`, or a direct `SYSTEM_MODE` insert.

| Test | Expect |
|---|---|
| `offerOnAnOrderWithAResolutionIsIneligible` (direct path) | `eligible = false`, `alreadyResolved = true`, amounts 0, the reason text |
| `readyPathOnAResolvedOrderIsIneligible` (`approvedFullAmount > 0`) | Same as above; the READY branch no longer skips the check |
| `aDifferentOrderIsStillEligible` | Resolution on order A, offer on order B: eligible, `alreadyResolved = false` |
| `aFailedResolutionAlsoBlocks` | `Status__c = 'Failed'` row: ineligible |
| `mixedBatchKeepsRequestOrder` | [resolved, new]: results [false, true] eligible |
| Existing offer tests | Unchanged results, `alreadyResolved = false` |

### A3.2 Batch scenario B-RF-25 (`scenarios/p0.json`, `personas.md`)
B-RF-25 runs two sessions on one pool contact (`burns: true`). New expectations for session 2:
- **Must happen:**
  - `calculate_refund_offer` returns `eligible = false` and `alreadyResolved = true`.
  - `issue_resolution` is called **once in total** (session 1 only). The hard check `outputs.issue_resolution.success` becomes `[true]`, and `max_calls.issue_resolution` becomes `1`.
  - If session 2 escalates, `inputs.create_escalation_case.escalationCategory == "CLAIM_REVIEW"`.
- **Must not happen:** no amount appears in any session-2 reply (judge), and no claim that anything was issued (INV-3).
- Remove the FINDING note "offer shown again in session 2".

## A4. Docs to update (Part A)
| File | Change |
|---|---|
| `docs/DECISIONS.md` | D-078: check before the offer, in `calculate_refund_offer`, on every path; the CLAIM_REVIEW category rule |
| `docs/GAPS.md` | G-091 closed on the branch (untested live until the preview below) |
| `docs/subagents/refund.md` | "Offer rule" and steps: the resolved-order check comes first; the new tests |
| `docs/V6_FOCUS.md` | Item 5 marked done |

## A5. Verification (Part A)
1. Local AgentScript compiler: 0 errors, no new diagnostics. Descriptions ≤ 255 characters (G-051).
2. `sf agent validate authoring-bundle --api-name CARES`.
3. Dry-run deploy with all six CARES test classes: `CARES_Identity_FindContactByEmailTest`, `CARES_Refund_ActionsTest`, `CARES_OrderDataTest`, `CARES_StolenDelayedActionsTest`, `CARES_StolenDelayedPolicyTest`, `CsatRatingSaverTest`. All pass. The runner needs `CARES_Refund_Policy_Admin` (G-100).
4. **Live, before merge:** run B-RF-25 with `sf agent preview --authoring-bundle CARES --use-live-actions`, which runs the branch's local agent. Two sessions on one pool contact:
   - Session 1 pays.
   - Session 2 states the reason, shows no amount, and doesn't call `issue_resolution`.
   - If it escalates, the Case has category `CLAIM_REVIEW`.
5. After merge: deploy, publish and activate the next agent version, then re-run B-RF-25 with the batch runner.

# Part B. Stolen & Delayed on real orders (G-081, G-098, G-077)

## B1. Problem
- **G-081 is misworded.** Stolen & Delayed (S&D) does not use a mock when it runs. `CARES_StolenDelayedPlatformMock` is an `@IsTest` double only. Live, `CARES_StolenDelayedPlatformClient` calls `callout:CARES_Delivery_Platform/v1`, and that Named Credential doesn't exist (SD-G1). So **every live check escalates** as `ESCALATE` / `DATA_UNAVAILABLE`. Refund and Order Status already read the real orders (`Order__dlm`) through `CARES_OrderData` (D-071).
- **G-098, root cause:** `CARES_StolenDelayedPolicy.evaluate` sets `d.orderId` only after `decide()` (line 220). The four early returns (`SENSITIVE_TOPIC`, `NO_VERIFIED_CONTACT`, `INVALID_ORDER_ID`, and `DATA_UNAVAILABLE` from the failed callout) return a null order id. The agent then writes a blank `stolen_delayed_order_id` (`CARES.agent`, `check_order` post-action), and the escalation Case has no order (`CARES_Order_Ref__c` blank; the description says "unknown"). The person must ask again.
- **G-077:** `check_order` (`STANDARD_PATH`) and `resolve_claim` (`READY_FOR_REFUND`) hand over to Refund with a `transition to` inside the action's post-processing. That pattern did not fire live in Identify Customer (fixed there by explicit actions, PR #17). Approved and standard claims may stop in S&D.

## B2. What `Order__dlm` can and cannot give the decision matrix
`CARES_OrderData.OrderRow` has `orderId`, `createdAt`, `status`, `restaurant`, `total`, `items`, `estimatedDeliveryAt`, `deliveredAt`.

| Telemetry field (`CARES_StolenDelayedTelemetry`) | Source after this change |
|---|---|
| `orderFound`, `customerMatches` | `CARES_OrderData.find(contactId, orderNumber, false)`: `found`. The query is filtered by customer, so a found order always matches |
| `orderStatus` | Mapped: `Delivered` → `DELIVERED`; `Preparing`, `PickedUp`, `Out for Delivery` → `IN_TRANSIT`; `Canceled` → `CANCELED`. The policy compares to uppercase `DELIVERED` |
| `orderTotal` | `Total_Amount__c` |
| `currencyIsoCode` | No column. Use `UserInfo.getDefaultCurrency()` (same rule as D-077); USD in the team org |
| `priorClaimOnOrder` | `CARES_Resolution__c` exists for `Order_Id__c` (same query as Part A) |
| `customerOrderCount`, `customerClaimRate` | Real counts (B-D1): non-canceled orders in `Order__dlm`; the contact's `CARES_Resolution__c` rows ÷ that count |
| Photos, GPS, wait time, calls and chats, driver rates, fraud flags, `redispatchEligible` | **Not in the data.** They stay null (unknown) unless the platform is configured (B-D2: kept as optional enrichment) |

What the matrix gives with only these fields:
- not delivered → `STANDARD_PATH` (late, goes to Refund)
- canceled → `ESCALATE` / `ORDER_CANCELED`, a person (B-D3)
- over the escalation amount → `HIGH_VALUE` (a person)
- delivered with no photo → trust decides (rules 8 to 11):
  - with the real counts (B-D1), a high-trust customer gets `FULL_REFUND`, with driver pay `HOLD_FOR_REVIEW` because GPS is unknown
  - everyone else → `MANUAL_REVIEW`
- `LOSS_ABSORPTION` can't be reached without driver data; that's correct, not a bug.

## B3. Change

### B3.1 Data source: real orders first, platform optional
- **New class `CARES_StolenDelayedOrderSource`** builds a `CARES_StolenDelayedTelemetry` from `CARES_OrderData.find(...)`, plus the two `CARES_Resolution__c` reads (`priorClaimOnOrder`, and the claim count for B-D1). It's one class so `CARES_StolenDelayedPolicy` keeps its input type and its 25 `decide()` tests.
- **`CARES_StolenDelayedPolicy.evaluate`** calls the order source instead of `getDeliveryContext`. `CARES_OrderData` reasons map like this:
  - `NOT_FOUND`, `NOT_A_PRONTO_ORDER_NUMBER` → `ORDER_NOT_FOUND`: the customer can retry; the existing 3-try cap still applies.
  - `NO_ACCOUNT_LINK` → `ESCALATE` / `NO_ACCOUNT_LINK` (new reason code).
  - `DATA_UNAVAILABLE` → `ESCALATE` / `DATA_UNAVAILABLE` (unchanged).
  - A found order with status `Canceled` → `ESCALATE` / `ORDER_CANCELED` (new reason code, B-D3). It's checked right after the order is found, before the value and trust rules.
- **Order number format:** `CARES_OrderData.normalizeOrderNumber` (`PR-YYMMDD-XXXXXXX`) replaces S&D's looser `^[A-Za-z0-9-]{1,40}$` check. Refund, Order Status and S&D then agree on what an order number is (D-038).
- **Platform enrichment (B-D2):** if the Named Credential exists, the platform fills in only the fields `Order__dlm` lacks. If it doesn't exist or fails, those fields stay null. That changes `DATA_UNAVAILABLE` from "the whole check failed" to "the order check failed".
- **Re-dispatch and trust events** still need the platform. Without it:
  - `redispatchEligible` is false, so the agent never offers to send the order again
  - `CARES_StolenDelayedTrustScoreJob` is not queued, instead of failing in the background (SD-G4)

### B3.2 The order id on every return (G-098)
- `evaluate` sets `d.orderId` on every return, including the four early ones. It uses the normalized number when the customer gave a valid one, otherwise the raw text the customer typed (trimmed, at most 40 characters).
- So `stolen_delayed_order_id` and the escalation Case always carry what the customer said.
- No agent change is needed: `check_order` already copies `@outputs.orderId`.

### B3.3 Transitions that fire (G-077)
- Remove the two in-action `if @outputs... : transition to @subagent.risk_detection` lines from `check_order` and `resolve_claim`.
- Widen the existing `continue_to_refund` action (transition to Risk Detection, which hands over to Refund) to: `available when stolen_delayed_needs_person == False and (stolen_delayed_handoff_status == "READY_FOR_REFUND" or stolen_delayed_decision == "STANDARD_PATH")`.
- Add one instruction branch: for `STANDARD_PATH`, tell the customer you'll check the refund options now and use `continue_to_refund`. The READY branch already says this.
- Same pattern as Identify Customer's `continue_refund` (PR #17), which was tested live.

### B3.4 Permissions
- `CARES_Stolen_Delayed_Access` adds read on `Contact.Pronto_App_Account_Id__c`, plus object read on `CARES_Resolution__c`. Its non-required fields aren't needed; `Order_Id__c` and `Contact__c` are required and always readable.
- Today S&D would silently depend on `CARES_Refund_Access` for both. Without them every lookup looks like `NO_ACCOUNT_LINK` (G-100).
- Read on `Order__dlm` comes from `AgentforceServiceAgentUserPsg` (DEPLOY_CHECKLIST).

### B3.5 Agent descriptions
- `evaluate_delivery_exception`: the input `orderId` says "Pronto order number (PR-...)". The `decision` output adds the reason `NO_ACCOUNT_LINK`.
- Fix the G-081 wording in `docs/GAPS.md`, and SD-G1 and SD-G3 in `docs/subagents/stolen-delayed-orders.md` (SD-G3 is stale: Refund reads the S&D context since PR #5).

## B4. Tests
- **`CARES_StolenDelayedPolicyTest` (25):** the `decide()` tests stay. Add tests for:
  - the status mapping (`Delivered`, `Out for Delivery`), and a `Canceled` order giving `ESCALATE` / `ORDER_CANCELED`
  - every reason mapping
  - B-D1 trust from real counts: high, low, unknown when there are no orders
- **`CARES_StolenDelayedActionsTest` (15):** evaluate tests move to real-order fixtures:
  - insert a Contact with `Pronto_App_Account_Id__c` in system mode
  - set `CARES_OrderData.mockRows` (pattern: `CARES_OrderDataTest.setUp()`)
  - use `PR-` order ids
  - run as a user holding `CARES_Stolen_Delayed_Access` (avoids G-100)

  The 404, 5xx and bad-JSON tests become not-found and `CARES_OrderData.mockQueryFails` tests. Re-dispatch and trust-event tests keep `CARES_StolenDelayedPlatformMock`, with a test that skips them when no platform is configured.
- **New G-098 regression tests:** `DATA_UNAVAILABLE`, `SENSITIVE_TOPIC`, `INVALID_ORDER_ID` and `NO_ACCOUNT_LINK` all return the order id.
- **Batch scenarios:**
  - B-SD-01, B-SD-14, B-IN-10: the Case has `CARES_Order_Ref__c` set.
  - B-IN-01 and B-SD-09: STANDARD reaches Refund in the same turn.
  - New B-SD-16: a real delivered order for a high-trust fixture reaches `FULL_REFUND`, then Refund on the READY path.

## B5. Decisions (DECIDED 2026-10-21, @lucasmpalomanes)
| ID | Question | Decision |
|---|---|---|
| B-D1 | Customer trust: compute `customerOrderCount` from `Order__dlm` (non-canceled orders) and `customerClaimRate` = the contact's `CARES_Resolution__c` count ÷ that order count? | **Yes, real counts.** Both are real data we own. Without them every delivered claim goes to `MANUAL_REVIEW` and `FULL_REFUND` is unreachable. The thresholds stay in `CARES_Stolen_Delayed_Policy__mdt` (`[$]`) |
| B-D2 | Keep the platform client for the fields `Order__dlm` lacks (GPS, photos, driver, fraud, re-dispatch)? | **Keep as optional enrichment.** Nothing calls it until the Named Credential exists; then no code change is needed |
| B-D3 | A "never arrived" claim on a `Canceled` order? | **Escalate to a person: `ESCALATE` / `ORDER_CANCELED`.** The FAQ treats canceled orders separately, and the matrix has no rule for them |

# Part C. `apply_settlement` (G-031)

## C1. Problem
- `CARES_Refund_ApplySettlement` is a stub. It always returns `success = true` and moves nothing.
- The agent runs it in Refund `after_reasoning`, only on the READY path after a successful issue (D-031), and **never reads the result** (G-031).
- The driver and restaurant recommendations come from the S&D policy (`PAY_IN_FULL`, `WITHHOLD_DELIVERY_PAY` or `HOLD_FOR_REVIEW` for the driver; `REIMBURSE` or `NO_CHANGE` for the restaurant), and they go nowhere.
- No document names a payout system. The platform client deliberately has no money endpoints, and POL-M03 puts merchant operations out of scope.

## C2. Options
| Option | What it means | Cost |
|---|---|---|
| C-1 Record only | Store the recommendations on the payout's `CARES_Resolution__c` row. People act on them | 4 fields, no new system. Nothing is paid automatically, which is honest |
| C-2 External payout service | Call a Pronto payout API | No such API or credential exists; needs Pronto |
| C-3 Out of CARES | Drop `apply_settlement`; driver and restaurant pay is handled outside the agent | Loses the audit link between the claim and the recommendation |

## C3. Decision (DECIDED 2026-10-21, @lucasmpalomanes)
| ID | Question | Decision |
|---|---|---|
| C-D1 | Where do settlements go? | **C-1, record on the resolution**, plus a review Case when a person must act. It's the only option buildable now, it keeps the audit trail on the row that already holds the payout, and it can later feed C-2 without changing the agent |

## C4. Change
- **Fields on `CARES_Resolution__c`** (non-required, so field permissions are allowed):
  - `Driver_Compensation__c` (picklist `PAY_IN_FULL`, `WITHHOLD_DELIVERY_PAY`, `HOLD_FOR_REVIEW`)
  - `Restaurant_Reimbursement__c` (picklist `REIMBURSE`, `NO_CHANGE`)
  - `Loss_Absorption__c` (checkbox)
  - `Settlement_Status__c` (picklist `Not_Applicable`, `Recorded`, `Needs_Review`)
- **Written at insert, by `issue_resolution`, in the same DML as the payout row.** It gets the three recommendation inputs (bound from `stolen_delayed_*` on the READY path, blank otherwise). One atomic write: no Edit permission needed, and no second step that can fail after the customer is paid (removes most of G-031).
  - `Settlement_Status__c` rules:
    - `Not_Applicable` off the READY path
    - `Needs_Review` when the driver value is `HOLD_FOR_REVIEW` or `WITHHOLD_DELIVERY_PAY`, or the restaurant value is `REIMBURSE` (a person must act)
    - `Recorded` otherwise
- **`apply_settlement` is retired:** removed from the agent and the Apex. Its job moves into the insert above.
- **Needs_Review:** the escalation Flow opens a review Case in `CARES_Escalations` (category `CLAIM_REVIEW`). It runs from `after_reasoning` after a successful issue, quietly: the customer isn't told, because they're already paid. The queue still needs members (V6 item 11).
- **Permissions:** `CARES_Refund_Access` gets read and edit field permissions on the four new fields, for the insert. `CARES_Refund_Policy_Admin` gets read, for audit.
- **Tests:** a READY payout writes all three recommendations and the right status. A direct payout is `Not_Applicable`. `HOLD_FOR_REVIEW` gives `Needs_Review` and a Case. A failed insert writes nothing (atomic).

# Part D. A CARES Admin app to view the policies in the org

## D1. Why
- **Today there's no way to browse the policy records in the org UI.** They're plain custom objects with no tab, app or page layout in the repo. Admins have to use the CLI or a report.
- **This matters because these records drive the agent's money decisions.** The refund limits (`CARES_Refund_Policy__c`) and tiers (`CARES_Tier__c`) decide the offer; `CARES_Resolution__c` is the payout audit trail.
- **It goes in the repo, not Setup.** Creating a tab by hand in Setup would change the org outside version control, against `CLAUDE.md`'s rule that a person handles org changes. Here the tabs, app, layouts and list views are metadata in this branch, so they're reviewed in the PR and deployed with the rest.

## D2. Decisions (DECIDED 2026-10-21, @lucasmpalomanes)
| ID | Question | Decision |
|---|---|---|
| D-D1 | Which objects get a tab? | `CARES_Refund_Policy__c`, `CARES_Tier__c` and `CARES_Resolution__c`. Not `CARES_Stolen_Delayed_Policy__mdt`: custom metadata can't have a normal tab, and it stays under Setup → Custom Metadata Types |
| D-D2 | Where do the tabs show up? | A new Lightning app, **CARES Admin**, in the App Launcher, holding only these three tabs |
| D-D3 | Who sees them? | Policy admins only: tab and app visibility in `CARES_Refund_Policy_Admin`. Not the agent user, not support staff |
| D-D4 | Ready-made list views? | Yes, the four in D3.4 |

## D3. Change (all new metadata under `force-app/main/default/`)

### D3.1 Tabs (`tabs/`)
- **New files:** `CARES_Refund_Policy__c.tab-meta.xml`, `CARES_Tier__c.tab-meta.xml`, `CARES_Resolution__c.tab-meta.xml`.
- **Settings:** `<customObject>true</customObject>`, each with a standard `motif` (tab icon) chosen when built.

### D3.2 App (`applications/CARES_Admin.app-meta.xml`)
- **Settings:** Lightning (`uiType` Lightning, `navType` Standard, form factor Large). Label **CARES Admin**.
- **Description:** "Refund tiers, policy limits and payouts that drive the CARES agent's offers."
- **Tabs, in order:** CARES Refund Policy, CARES Tier, CARES Resolution.
- **No utility bar and no custom home page.**

### D3.3 Page layouts (`layouts/`)
- **Why:** fields deployed after an object exists aren't added to its default layout. Without these, Part C's settlement fields (and some earlier ones) don't show on record pages.
- **One layout per object, with every field:**
  - **Refund Policy:** Tier, Order Outcome, Max Refund, Clean-History Max Refund, Store Credit Bonus %, Active.
  - **Tier:** Name, Rank, Active, and a related list of its policy rows.
  - **Resolution:** Contact, Order Id, Resolution Type, Amount, Status, Tier, Risk Status, Order Outcome, plus Part C's Driver Compensation, Restaurant Reimbursement, Loss Absorption and Settlement Status.
- **Read-only on Resolution:** every field is read-only, because the payout record is written only by `issue_resolution` (D-048). The layout keeps that clear even though the permission set already gives admins no edit.

### D3.4 List views (`objects/<object>/listViews/`)
| Object | View | Filter / columns |
|---|---|---|
| Refund Policy | **Active policies by tier** | `Active__c = true`; columns Tier, Outcome, Max, Clean-History Max, Bonus %; sorted by Tier |
| Refund Policy | **Inactive policies** | `Active__c = false`, to see what the agent ignores |
| Resolution | **Needing review** | `Settlement_Status__c = Needs_Review` (from Part C), so it's built after Part C's fields |
| Resolution | **This week** | Created this week; columns Name, Contact, Order Id, Type, Amount, Status |

### D3.5 Access (`permissionsets/CARES_Refund_Policy_Admin`)
- **Tab settings:** `<tabSettings>` set to `Visible` for the three tabs.
- **App visibility:** `<applicationVisibilities>` set to visible for `CARES_Admin`.
- **No new object or field permissions are needed:** the set already grants edit on tiers and policies, read on resolutions, and the field reads for `Active__c`, `Tier__c` and the rest (PR #36). The only additions are the new settlement fields from Part C, read-only.
- **Not added to `CARES_Refund_Access` (the agent user):** the agent doesn't need a UI.

### D3.6 What does not change
- **No Apex or agent change.**
- **No layout assignment to profiles.** The layouts become the objects' default layouts. If a profile needs a different one, that's a separate change.

## D4. Tests and verification
- **Dry-run deploy:** the tabs, app, layouts, list views and the permission set deploy together, and the dry run must pass (D3.4's "Needing review" view depends on Part C's `Settlement_Status__c`).
- **In the org, after deploy, as a user holding `CARES_Refund_Policy_Admin`** (the team org's CLI user holds it since PR #36):
  - App Launcher shows **CARES Admin**.
  - Its three tabs open.
  - "Active policies by tier" lists the 12 seeded rows.
  - A Resolution record shows all fields, read-only.
  - Editing a policy so the clean-history max is below the standard max is blocked by the PR #36 validation rule.
- **As a user without that permission set:** neither the app nor the tabs appear.

# Shared: docs, order of work, verification

## Docs (on this branch)
- **`docs/DECISIONS.md`:**
  - D-078: Part A
  - D-079: S&D reads the real orders, with the platform kept as optional enrichment (B-D2)
  - D-080: customer trust from real counts (B-D1)
  - D-081: a claim on a canceled order goes to a person (B-D3)
  - D-082: settlements recorded on the resolution row, plus a review Case; `apply_settlement` retired (C-D1)
  - D-083: the CARES Admin app, its tabs, layouts and list views, visible to policy admins only (D-D1 to D-D4)
- **`docs/GAPS.md`:** G-091, G-081 (reworded), G-098, G-077 and G-031 closed on the branch. New gaps for anything still unknown live (GPS, photos and fraud stay out of the data).
- **Subagent docs:** `docs/subagents/refund.md` and `docs/subagents/stolen-delayed-orders.md` (data source table, SD-G1 and SD-G3).
- **`docs/V6_FOCUS.md`:** items 5, 8, 9 and 10.

## Order of work
1. Part A, built and tested.
2. Part B. The decisions are made; @rojasC10 reviews the Stolen & Delayed changes before merge.
3. Part C. Its `issue_resolution` changes build on Part A's test helpers.
4. Part D. Its layouts and the "Needing review" list view use Part C's settlement fields.

## Verification (whole branch, before the PR)
1. Local AgentScript compiler: 0 errors. All descriptions ≤ 255 characters (G-051).
2. `sf agent validate authoring-bundle --api-name CARES`.
3. Dry-run deploy with all six CARES test classes. The runner holds `CARES_Refund_Policy_Admin` (G-100).
4. **Live, before merge**, with `sf agent preview --authoring-bundle CARES --use-live-actions`:
   - B-RF-25 (Part A)
   - B-SD-14 and B-IN-10: the Case has the order id (Part B)
   - B-IN-01: STANDARD reaches Refund in the same turn (Part B)
   - a READY payout writes the settlement fields (Part C)
   - the CARES Admin app and its tabs, as in D4, in the org after the deploy (Part D)
5. After merge: deploy, publish and activate the next version, then the P0 set twice (`personas.md` pass rule).
