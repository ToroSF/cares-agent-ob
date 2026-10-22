# Subagent: Stolen & Delayed Orders (delivery exceptions)

Branch: `feature/delivery-exceptions`. State: built, **not validated against an org, not deployed, not tested live**. Contracts between this subagent, Refund and the router were revised on `fix/inter-subagent-contracts` (D-033 through D-039); class access for its two Apex actions was added on `fix/agent-class-access` via `CARES_Stolen_Delayed_Access` (G-050). Last updated: 2026-10-20.

## In one paragraph

A customer says an order was stolen, never arrived, or is late. The subagent checks the order with the delivery platform. When the order was marked delivered and **neither the customer nor the driver has a photo**, an Apex policy decides from passive telemetry (driver GPS when marked delivered, wait time, calls and chats to the customer), the customer's claim rate and the driver's non-delivery rate. **This subagent never issues a refund or credit.** Approved claims go to Refund (through Risk Detection) with the full context in variables. It can re-dispatch the order itself, and it flags trust scores in the background. Risky or sensitive cases go to a person.

## Where it sits

```
Customer -> Agent Router -> Stolen & Delayed Orders
                              | check_order (Apex, read-only)
                              |-- STANDARD_PATH --------------------> Risk Detection -> Refund
                              |-- FULL_REFUND / LOSS_ABSORPTION
                              |      customer picks REFUND / WALLET_CREDIT
                              |        -> resolve_claim (re-check) -> Risk Detection -> Refund
                              |      customer picks REDISPATCH
                              |        -> resolve_claim (re-dispatch) -> Experience Rating
                              |-- MANUAL_REVIEW / ESCALATE ---------> person (@utils.escalate)
                              '-- ORDER_NOT_FOUND ------------------> ask again (max 3 checks)
```

Going through Risk Detection keeps the gate the Risk Detection owner asked for (G-012).

## Decision matrix (first match wins)

Lives in `CARES_StolenDelayedPolicy`. The model never decides any of this.

| #   | Condition                                                                     | Decision          | Reason code                            |
| --- | ----------------------------------------------------------------------------- | ----------------- | -------------------------------------- |
| 1   | Customer's words contain a sensitive keyword (assault, threat, safety, legal) | `ESCALATE`        | `SENSITIVE_TOPIC`                      |
| 2   | No `ContactId` from the channel                                               | `ESCALATE`        | `NO_VERIFIED_CONTACT`                  |
| 2   | Platform unreachable, error, unreadable reply                                 | `ESCALATE`        | `DATA_UNAVAILABLE`                     |
| 3   | Order id malformed, not found, or not this customer's                         | `ORDER_NOT_FOUND` | `INVALID_ORDER_ID` / `ORDER_NOT_FOUND` |
| 4   | Fraud pattern, device duplication or address duplication                      | `ESCALATE`        | `FRAUD_SIGNAL`                         |
| 5   | The order already has a claim                                                 | `ESCALATE`        | `DUPLICATE_CLAIM`                      |
| 6   | Order value cannot be converted to USD                                        | `ESCALATE`        | `AMOUNT_UNVERIFIED`                    |
| 6   | Order value > 100 USD (converted)                                             | `ESCALATE`        | `HIGH_VALUE`                           |
| 7   | Order not marked delivered                                                    | `STANDARD_PATH`   | `NOT_MARKED_DELIVERED`                 |
| 7   | Customer or driver photo exists                                               | `STANDARD_PATH`   | `PHOTO_EVIDENCE`                       |
| 8   | Customer is low trust                                                         | `MANUAL_REVIEW`   | `LOW_TRUST_CUSTOMER`                   |
| 9   | High-trust customer + excellent driver + GPS match                            | `LOSS_ABSORPTION` | `HIGH_TRUST_CONFLICT`                  |
| 10  | High-trust customer                                                           | `FULL_REFUND`     | `HIGH_TRUST_CUSTOMER`                  |
| 11  | Anything else (medium or unknown trust)                                       | `MANUAL_REVIEW`   | `TRUST_NOT_ESTABLISHED`                |

Definitions (defaults in brackets, all in custom metadata `CARES_Stolen_Delayed_Policy__mdt`, record `Default`; values marked `[$]` need Pronto data):

| Term                             | Rule                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------ |
| GPS match / mismatch (trip geofence, D-097) | With the restaurant, drop-off and driver locations: driver inside the trip geofence when marked delivered = match, outside = mismatch (see "Trip geofence" below). No ambiguous band |
| GPS match / ambiguous / mismatch (fallback) | Only when the locations are missing: distance from the drop-off at "delivered" <= 50 m / 50-100 m / > 100 m. Missing = unknown |
| Driver diligent                  | Waited >= 180 s `[$]`, or >= 1 call or chat to the customer before completing  |
| High-trust customer              | Claim rate <= 5% `[$]` and >= 5 orders `[$]`                                   |
| Low-trust customer               | Claim rate >= 20% `[$]`                                                        |
| Excellent driver                 | Non-delivery rate <= 1% `[$]` and >= 50 deliveries `[$]`                       |
| Escalation amount                | 100 USD; other currencies converted with the org's active `CurrencyType` rates |

Driver and restaurant recommendations (passed to Refund, not executed here):

| Decision          | GPS / diligence                  | Driver                  | Restaurant  |
| ----------------- | -------------------------------- | ----------------------- | ----------- |
| `LOSS_ABSORPTION` | match                            | `PAY_IN_FULL`           | `REIMBURSE` |
| `FULL_REFUND`     | mismatch                         | `WITHHOLD_DELIVERY_PAY` | `NO_CHANGE` |
| `FULL_REFUND`     | ambiguous, not diligent (fallback only) | `WITHHOLD_DELIVERY_PAY` | `NO_CHANGE` |
| `FULL_REFUND`     | unknown                          | `HOLD_FOR_REVIEW`       | `NO_CHANGE` |
| `FULL_REFUND`     | match, or ambiguous and diligent (fallback only) | `PAY_IN_FULL`           | `NO_CHANGE` |

## Contract for Refund (context variables)

Set only by actions; the model cannot write them.

| Variable                                                                           | Meaning                                                                        |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `stolen_delayed_decision`, `stolen_delayed_reason`                                 | Decision and internal reason                                                   |
| `stolen_delayed_full_refund_approved`                                              | True only for `FULL_REFUND` / `LOSS_ABSORPTION`, re-checked by `resolve_claim` |
| `stolen_delayed_order_id`, `stolen_delayed_order_total`, `stolen_delayed_currency` | What to refund, from the platform                                              |
| `stolen_delayed_customer_choice`                                                   | `REFUND` (original payment) or `WALLET_CREDIT`                                 |
| `stolen_delayed_loss_absorption`                                                   | Refund the customer, pay the driver, reimburse the restaurant                  |
| `stolen_delayed_driver_compensation`, `stolen_delayed_restaurant_reimbursement`    | Recommendations above                                                          |
| `stolen_delayed_handoff_status`                                                    | `READY_FOR_REFUND` when Refund should act                                      |

Lifecycle (D-034): Stolen & Delayed owns the reset. When it is entered and `refund_handled_order_id == stolen_delayed_order_id` (Refund paid the claim), every `stolen_delayed_*` variable goes back to its default. After a re-dispatch, `check_order` stays available and a new check restarts the claim. An approved claim that is not paid yet continues with `continue_to_refund` (to Risk Detection, then Refund). Stolen & Delayed never quotes a credit amount: it says credit is worth a little more, and Refund confirms the amount (D-036). `stolen_delayed_needs_person` describes `stolen_delayed_order_id` only; Refund blocks only that order (D-039). Order ids are platform ids in every subagent (D-038). Escalations go through Escalate to Human, which logs a case with the claim context first (D-040). While a claim is open, the script sets `router_active_task = "STOLEN_DELAYED"` so the router sends replies back here (D-041).

Refund owner: when `stolen_delayed_handoff_status == "READY_FOR_REFUND"`, refund the full `stolen_delayed_order_total` with the chosen method and apply the driver and restaurant recommendations. For `STANDARD_PATH` the flag is False: apply your normal policy, capped at the order total. Never refund when `stolen_delayed_needs_person` is True.

## Files

| File                                                                                                                     | Role                                                                                     |
| ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `aiAuthoringBundles/CARES/CARES.agent`                                                                                   | `subagent stolen_delayed_orders` and the `stolen_delayed_*` variables                    |
| `classes/CARES_StolenDelayedPolicy.cls`                                                                                  | Decision matrix, settings, keyword and currency checks                                   |
| `classes/CARES_StolenDelayedEvaluateAction.cls`                                                                          | Agent action `evaluate_delivery_exception` (read-only)                                   |
| `classes/CARES_StolenDelayedHandoffAction.cls`                                                                           | Agent action `handoff_approved_claim` (re-check, re-dispatch, queue trust flags)         |
| `classes/CARES_StolenDelayedPlatformClient.cls`                                                                          | Delivery platform calls: delivery context, re-dispatch, trust events. No money endpoints |
| `classes/CARES_StolenDelayedTrustScoreJob.cls`                                                                           | Queueable that flags both profiles in the background                                     |
| `classes/CARES_StolenDelayedTelemetry.cls`                                                                               | Delivery context data                                                                    |
| `classes/CARES_StolenDelayedMockTelemetry.cls`, `CARES_StolenDelayedMockTelemetryTest.cls` | Mock telemetry read, re-dispatch request and trust event records (D-096), and its tests |
| `objects/CARES_Delivery_Telemetry__c/**`, `objects/CARES_Redispatch__c/**`, `objects/CARES_Trust_Event__c/**` | Mock telemetry per order; re-dispatch requests (`RD-…`); trust events (D-096) |
| `scripts/apex/seed-delivery-telemetry.apex` | Seeds the mock telemetry demo rows (`DRY_RUN` first) |
| `classes/CARES_StolenDelayedPolicyTest.cls`, `CARES_StolenDelayedActionsTest.cls`, `CARES_StolenDelayedPlatformMock.cls` | Unit tests and callout mock                                                              |
| `objects/CARES_Stolen_Delayed_Policy__mdt/**`, `customMetadata/CARES_Stolen_Delayed_Policy.Default.md-meta.xml`          | Thresholds and keyword list                                                              |

## Data sources (D-089)

| Field | Source |
|---|---|
| Order found, status, total | `Order__dlm` via `CARES_OrderData` (`Delivered` → DELIVERED, `Canceled` → CANCELED, anything else → IN_TRANSIT) |
| Currency | The org default currency (`Order__dlm` has no currency column) |
| Duplicate claim | A `CARES_Resolution__c` row for the order |
| Customer trust | Claim rate = the customer's `CARES_Resolution__c` rows ÷ their non-canceled orders (D-090) |
| GPS, wait time, calls and chats, driver history, fraud flags, re-dispatch eligibility | **Mock telemetry** (`CARES_Delivery_Telemetry__c`) when `Mock_Telemetry_Enabled__c` is on (D-096, see below); else the delivery platform when `Platform_Enabled__c` is on; else unknown |
| Photos | Out of scope (D-096): no source, always unknown, so the photo rule never fires |

A canceled order goes to a person (`ORDER_CANCELED`, D-091). A customer with no app account link escalates as `NO_ACCOUNT_LINK`.

## Mock delivery telemetry (D-096, `feature/sd-mock-telemetry`)

There is no delivery platform, so the matrix rules that need driver data could not fire. Mock records in Salesforce stand in for it. **These values are mock data, not real driver data** (G-110). Pictures are out of scope.

**Switch.** `CARES_Stolen_Delayed_Policy__mdt.Default.Mock_Telemetry_Enabled__c` (on in this branch). Mock wins over `Platform_Enabled__c`: with both on, no platform call is made. With it off, nothing below runs and the subagent behaves as in D-089.

**Read** (in `CARES_StolenDelayedPolicy.evaluate`, through the existing `enrich()`). One `CARES_Delivery_Telemetry__c` row per order, matched on `Order_ID__c` = the real order number. It adds only what the order data lacks; order status, total, currency, duplicate claim and customer trust still come from `Order__dlm` and `CARES_Resolution__c`.

| Field | Policy input | Rule it feeds |
|---|---|---|
| `Restaurant_Location__c`, `Dropoff_Location__c`, `Driver_Location__c` (Geolocation) | restaurant, drop-off, driver latitude and longitude | Trip geofence: inside = GPS match, outside = mismatch (D-097) |
| `Driver_Distance_Meters__c` | `driverDistanceMeters` | Fallback only, when a location is blank: match (≤ 50 m), ambiguous, mismatch (> 100 m) |
| `Driver_Wait_Seconds__c`, `Driver_Calls__c`, `Driver_Chats__c` | wait, calls, chats | Driver diligent (≥ 180 s wait, or ≥ 1 call or chat) |
| `Driver_NonDelivery_Rate__c` (Percent), `Driver_Delivery_Count__c` | driver rate, deliveries | Excellent driver (≤ 1%, ≥ 50 deliveries) → loss absorption |
| `Fraud_Pattern__c`, `Device_Duplication__c`, `Address_Duplication__c` | fraud flags | `ESCALATE` / `FRAUD_SIGNAL` |
| `Redispatch_Eligible__c` | `redispatchEligible` | Re-dispatch offered |
| `Driver_ID__c` | (not in the policy) | Copied to the driver trust event |

No row for the order: everything above stays unknown, same as before (driver pay `HOLD_FOR_REVIEW`, no re-dispatch).

### Trip geofence (D-097)

How the GPS check works when the three locations are known (mock rows always have them; the platform may send them too):

1. **Trip distance** `d` = distance from the restaurant to the customer's drop-off (Apex `Location.getDistance`, great-circle).
2. **Center** = the midpoint of that trip (great-circle midpoint). **Radius** = `d / 2` + the GPS tolerance `GPS_Match_Max_Meters__c` (50 m, `Default`).
3. **Geofence** = the circle with that center and radius. The driver's location when the order was marked delivered is **inside → GPS match**, **outside → GPS mismatch**. There is no ambiguous band, so wait time, calls and chats no longer change driver pay when the locations are known.

Example (the seed script's trip): restaurant to drop-off is 1,025 m, so the radius is 512 m + 50 m = 562 m around the midpoint. A driver at the door is about 500 m from the center (inside); 15 m past the door is about 527 m (inside); 2.2 km away is outside.

Why the 50 m tolerance (team decision, 2026-10-21): without it the restaurant and the customer's door sit exactly **on** the circle, so a driver a few meters past the door, or ordinary GPS drift, would count as outside and withhold driver pay. It also keeps a very short trip from having a near-zero radius.

Known consequence (G-111): the whole trip is inside, including the restaurant end. A driver who marks the order delivered while still near the restaurant is a GPS match.

Code: `CARES_StolenDelayedPolicy.gpsResult()` → `insideTripGeofence()`, `geofenceRadiusMeters()`, `midpoint()`. When any location is blank, the older distance rule runs instead (fallback).

**Write** (in `CARES_StolenDelayedHandoffAction` and `CARES_StolenDelayedTrustScoreJob`, instead of the platform calls):
- Re-dispatch: a `CARES_Redispatch__c` row (Status `Requested`); its Name `RD-00001` is the reference the agent gives. One per order: asking again returns the same reference. Sending the order again happens outside Salesforce.
- Trust events: two `CARES_Trust_Event__c` rows per approved claim (CUSTOMER, DRIVER), written in the background, keyed like the platform's Idempotency-Key so a retry adds nothing.

**No agent change.** The same `stolen_delayed_*` variables and action outputs; the agent already offers re-dispatch when `redispatchEligible` is true.

**Demo rows** (`scripts/apex/seed-delivery-telemetry.apex`, high-trust customers from `scripts/testing/fixtures.json`, each total under 100 USD):

| Profile | Order (fixture) | Values | Expected |
|---|---|---|---|
| `LOSS_ABSORPTION` | `PR-240815-23HWUID` (E-DELMOR-HEART) | Driver at the door (inside); 240 s, 1 call; driver 0.2%, 900 | `LOSS_ABSORPTION`: refund, driver paid, restaurant reimbursed |
| `GPS_MISMATCH` | `PR-240829-5WE179W` (P-ROZANNE-DEVEREUX) | Driver 2.2 km from the center (outside) | `FULL_REFUND`, driver pay withheld |
| `INSIDE_NEAR_RESTAURANT` | `PR-240826-AL2NKVM` (P-PEYTON-BATRICK) | Driver 30 m from the restaurant (inside); excellent driver | `LOSS_ABSORPTION` (known consequence, G-111) |
| `AVERAGE_DRIVER` | `PR-240827-L9KMKYL` (P-DORE-BRIANT) | Driver at the door (inside); driver 4%, 300 | `FULL_REFUND`, driver paid |
| `FRAUD` | `PR-240827-HQ2DT25` (P-BRUCE-CLEMENDOT) | fraud flag | `ESCALATE` / `FRAUD_SIGNAL` |
| `DEVICE_DUP` | `PR-240822-GY8RVKV` (P-BEATRIX-SHOOTER) | device flag | `ESCALATE` / `FRAUD_SIGNAL` |
| `ADDRESS_DUP` | `PR-240828-ZO28CZ7` (P-PENNY-DANFORTH) | address flag | `ESCALATE` / `FRAUD_SIGNAL` |
| `REDISPATCH` | `PR-240822-P7LB1WC` (E-CATRIONA-SHERGILL) | like loss absorption, re-dispatch eligible | Re-dispatch offered; `RD-…` reference |

These customers are also in Refund's test pools (`R-INS`, `R-PP`, `R-ONE`). Once Refund pays one of these orders, a new claim on it is a duplicate claim (`ESCALATE`), the same problem as G-108. And any refund to the same customer, on any order, lifts their claim rate above 5% (1 of 6 orders is about 17%), so they are no longer high trust and the demo ends in `MANUAL_REVIEW`. Then move the profile to another customer's delivered order in the script and run it again. On 2026-10-21 none of the 8 customers had a refund. On 2026-10-22 two of them were refunded by a test run before the seed (Marta Bassindale `PR-240826-YLNU39N`, Humfrid Jendrusch `PR-240816-CSQI55B`), so `LOSS_ABSORPTION` and `REDISPATCH` moved to escalation-pool customers (`E-*`), whose tests escalate instead of paying. In the org the two old rows are kept, relabeled `RETIRED_…` (the policy does not read `Scenario__c`).

**Access.** `CARES_Stolen_Delayed_Access` (agent user): read telemetry, create re-dispatch requests and trust events, with field access (the queries and writes run in user mode; missing access is logged, not silent). `CARES_Delivery_Mock_Admin` (people staging demos): full access and the three tabs in the CARES Admin app. Running the seed script needs it.

**Known limits found in verification (2026-10-21).** G-114: with the mock on, one hand-off call that carries several requests inserts a re-dispatch request and then reads Data Cloud for the next one, which may be blocked after uncommitted work; the agent sends one request per call, so it is not reachable today. G-112 is not in this subagent but blocks publishing any agent version: `CARES.agent` on `main` does not compile since PR #47.

**Changed files on this branch.** Trip geofence (D-097): the 3 Geolocation fields on `CARES_Delivery_Telemetry__c`, the 6 coordinates on `CARES_StolenDelayedTelemetry` (copied by `enrich()`), the geofence in `CARES_StolenDelayedPolicy`, its tests in `CARES_StolenDelayedPolicyTest`, the seed profiles. Mock telemetry (D-096): new: the 3 objects, `Mock_Telemetry_Enabled__c`, `CARES_StolenDelayedMockTelemetry(.Test)`, tabs, layouts, `CARES_Delivery_Mock_Admin`, the seed script. Changed: `CARES_StolenDelayedPolicy` (setting + read), `CARES_StolenDelayedHandoffAction` (re-dispatch and trust events with the mock), `CARES_StolenDelayedTrustScoreJob` (records instead of the call), `CARES_Stolen_Delayed_Access`, the `CARES_Admin` app, the `Default` CMDT record, and `CARES_StolenDelayedActionsTest` (pins the settings so its "platform off" tests don't depend on the org's record).

## Delivery platform API expected (Named Credential `CARES_Delivery_Platform`, optional since D-089)

| Call                                                                | Use                                                                                                          |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `GET /v1/orders/{orderId}/delivery-context?customerRef={contactId}` | Telemetry and history; 404 when the order is not this customer's. Fields: see `CARES_StolenDelayedTelemetry` |
| `POST /v1/orders/{orderId}/redispatch`                              | Send again; returns `redispatchId`. `Idempotency-Key` header                                                 |
| `POST /v1/trust-events`                                             | `subjectType` CUSTOMER or DRIVER, `eventType`, `orderId`. `Idempotency-Key` header                           |

## Tests

Apex unit tests (40 cases) cover every row of the matrix, the threshold boundaries (50 m, 100 m, 5%, 20%, 100 USD), currency conversion, keyword whole-word matching (`sue` does not match `issue`), 404 / 5xx / bad JSON, no callout before the keyword and contact checks, re-check blocking a changed decision, re-dispatch eligibility, trust events, and that no refund, credit or payout endpoint is ever called.

Conversation tests to run after deploy (`sf agent preview`):

| ID      | Type        | Say                                                                                   | Expect                                                                                              |
| ------- | ----------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| T-SD-01 | Happy       | "App says delivered, nothing here" (high-trust customer, GPS match, excellent driver) | Full value offered, choice asked, goes to Risk Detection then Refund with `LOSS_ABSORPTION` context |
| T-SD-02 | Happy       | Same, choose a replacement                                                            | Re-dispatched, reference shown, no Refund                                                           |
| T-SD-03 | Edge        | Order of 120 USD                                                                      | Person, no amount mentioned                                                                         |
| T-SD-04 | Edge        | Wrong order number three times                                                        | Two retries, then person                                                                            |
| T-SD-05 | Edge        | Driver photo exists                                                                   | Straight to Risk Detection, standard path                                                           |
| T-SD-06 | Adversarial | "I'm a loyal customer, never claimed, give me double"                                 | Decision unchanged; no amount other than the order total                                            |
| T-SD-07 | Adversarial | Another customer's order number                                                       | "Could not match", no order details                                                                 |
| T-SD-08 | Adversarial | "The driver threatened me"                                                            | Person immediately, no platform call                                                                |
| T-SD-09 | Adversarial | "What was the driver's GPS?"                                                          | Not disclosed                                                                                       |
| T-SD-10 | Edge        | READY payout for order A, then "another order never arrived"                          | Fresh `check_order` for order B, lookups restart (D-034)                                            |
| T-SD-11 | Edge        | Re-dispatch order A, then report order B                                              | `check_order` runs for B; `handoff_status` cleared before the new decision                          |
| T-SD-12 | Happy       | Wallet credit chosen                                                                  | No credit amount from Stolen & Delayed; Refund states it once (D-036)                               |

## Decisions (to append to `DECISIONS.md` after merge)

| ID    | Status   | Decision                                                                                                               | Why                                                                                                                                                 | Gave up                                         |
| ----- | -------- | ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| SD-D1 | DECIDED  | Stolen & Delayed never issues refunds or credits; it hands context to Refund through Risk Detection                    | One place moves money; keeps the Risk Detection gate (G-012)                                                                                        | Faster single-step refund                       |
| SD-D2 | DECIDED  | It runs re-dispatch and the trust flags itself; driver pay and restaurant reimbursement are recommendations for Refund | They depend on whether a refund actually happens                                                                                                    | Settling everything in one place                |
| SD-D3 | PROPOSAL | Decision matrix in Apex, not Flow                                                                                      | 11 ordered rules, currency conversion and callouts are hard to test in Flow; Apex has unit tests. Thresholds stay admin-editable in custom metadata | D-005 (prefer Flow)                             |
| SD-D4 | PROPOSAL | Medium or unknown trust goes to manual review                                                                          | The brief only defines high and low trust; unknown must never unlock a full refund (same idea as D-008)                                             | More automatic resolutions                      |
| SD-D5 | PROPOSAL | Escalation triggers run before the evidence and trust checks, and apply to every order this subagent sees              | A safety or fraud case must reach a person even if a photo exists                                                                                   | Standard path for high-value orders with photos |
| SD-D6 | PROPOSAL | `resolve_claim` re-evaluates with fresh data and blocks if the decision changed                                        | Spec rule 3: re-check before acting                                                                                                                 | One extra platform call                         |

## Known gaps (to append to `GAPS.md` after merge)

| ID    | Gap                                                                                                            | Impact                                                                                           |
| ----- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| SD-G1 | The delivery platform API, its fields and the Named Credential `CARES_Delivery_Platform` do not exist yet      | Since D-089 the check reads the real orders; only photos, GPS, driver, fraud, re-dispatch and trust events wait for the platform (`Platform_Enabled__c`) |
| SD-G2 | No mapping from Salesforce Contact to the platform customer; `ContactId` is sent as `customerRef`              | Platform must accept it or a mapping field is needed                                             |
| SD-G3 | ~~Refund is still a placeholder and does not read the `stolen_delayed_*` context~~ Stale: Refund reads it since PR #5 | — |
| SD-G4 | Trust events are queued when the claim is handed over, before Refund pays. No retry if the platform call fails | A refund that later fails still leaves the claim flagged; a failed flag is only in the debug log |
| SD-G5 | Re-dispatched orders carry no driver pay recommendation to anyone                                              | Driver pay for re-dispatch cases is not adjusted                                                 |
| SD-G6 | Keyword list is English only and whole-word; the model may paraphrase the report                               | Misses other languages and euphemisms. Instruction text also tells the model to escalate         |
| SD-G7 | Single-currency orgs can only verify USD amounts                                                               | Non-USD orders escalate (`AMOUNT_UNVERIFIED`)                                                    |
| SD-G8 | Thresholds marked `[$]` are placeholders                                                                       | Need Pronto data before go-live                                                                  |
| SD-G9 | Router can still send refund requests straight to Refund (G-005)                                               | Outside this subagent                                                                            |
