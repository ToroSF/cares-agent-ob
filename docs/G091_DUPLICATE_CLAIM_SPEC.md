# Spec: refuse a second claim before the offer (G-091)

Status date: 2026-10-21. Status: `PROPOSAL`. Branch: `fix/g091-duplicate-claim-before-offer`. Owner: @lucasmpalomanes (Refund, D-027). Nothing in this file is built yet. Source: `main` at `fe62128`.

## 1. Problem
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

## 2. Change

### 2.1 Where the check lives: `calculate_refund_offer`
The check goes **at the top of `CARES_Refund_CalculateOffer.calculateOne`, before the READY / direct split**. It's the one deterministic step that every path runs before any amount reaches the customer: the script `run`s it as soon as the outcome is known (D-021). It needs no new action and no new agent branch.

- **Query:** one bulk query in `execute()`, next to the existing tier, contact and policy queries:
  ```apex
  SELECT Order_Id__c FROM CARES_Resolution__c WHERE Order_Id__c IN :orderIds WITH USER_MODE
  ```
  It uses `req.orderId`, which is required today but unused.
- **No `Status__c` filter**, the same as `issue_resolution`: any row for the order blocks. Today only `Issued` rows are written. A `Failed` row, if one is ever written, blocks too, so a person reviews it instead of a second automatic payout.
- **Access:** `CARES_Refund_Access` already grants read on `CARES_Resolution__c`, and `Order_Id__c` is a required field, so it's always readable. No permission set change.
- **Backstop:** `issue_resolution` keeps its own check, plus the unique `Order_Id__c` (D-024, D-048), for races.

### 2.2 Apex contract
| | Change |
|---|---|
| Result | New field `alreadyResolved` (Boolean). False in every other case |
| When a resolution exists | `eligible = false`, `refundAmount = 0`, `creditAmount = 0`, `alreadyResolved = true`, `ineligibleReason` = "This order already has a refund or credit on file, so I can't offer another one. A team member can check it if something looks wrong." |
| Order of checks | Resolution first, then tier, then policy, then amounts. A resolved order never shows a tier or policy message |
| Batch | Results stay in request order (existing pattern) |

### 2.3 Agent (`subagent refund`, `CARES.agent`)
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

### 2.4 What does not change
- **D-032 stays:** `refund_handled_order_id` still stops a same-session double payout before any query.
- **D-048 stays:** `issue_resolution` keeps its check as the backstop.
- **No new subagent**, and no change to the router or to Stolen & Delayed.

### 2.5 Out of scope (follow-ups)
- **Telling the customer earlier:** on the direct path the customer still describes the problem before hearing "already on file". No amount is shown, so this is acceptable. Checking in `find_order` would be earlier, but it would miss the READY path and duplicate the rule.
- **Writing `Status__c = Failed` rows:** never written today (see the readiness findings).

## 3. Tests

### 3.1 Apex (`CARES_Refund_ActionsTest`)
Reuse `refundUser()`, `makeTier`, `makePolicy`, `makeContact`, `offer(...)` and `issue(...)`. Add an `offer(...)` overload that takes an order id. The insert of a resolution row uses `issue(...)` as `refundUser()`, or a direct `SYSTEM_MODE` insert.

| Test | Expect |
|---|---|
| `offerOnAnOrderWithAResolutionIsIneligible` (direct path) | `eligible = false`, `alreadyResolved = true`, amounts 0, the reason text |
| `readyPathOnAResolvedOrderIsIneligible` (`approvedFullAmount > 0`) | Same as above; the READY branch no longer skips the check |
| `aDifferentOrderIsStillEligible` | Resolution on order A, offer on order B: eligible, `alreadyResolved = false` |
| `aFailedResolutionAlsoBlocks` | `Status__c = 'Failed'` row: ineligible |
| `mixedBatchKeepsRequestOrder` | [resolved, new]: results [false, true] eligible |
| Existing offer tests | Unchanged results, `alreadyResolved = false` |

### 3.2 Batch scenario B-RF-25 (`scenarios/p0.json`, `personas.md`)
B-RF-25 runs two sessions on one pool contact (`burns: true`). New expectations for session 2:
- **Must happen:**
  - `calculate_refund_offer` returns `eligible = false` and `alreadyResolved = true`.
  - `issue_resolution` is called **once in total** (session 1 only). The hard check `outputs.issue_resolution.success` becomes `[true]`, and `max_calls.issue_resolution` becomes `1`.
  - If session 2 escalates, `inputs.create_escalation_case.escalationCategory == "CLAIM_REVIEW"`.
- **Must not happen:** no amount appears in any session-2 reply (judge), and no claim that anything was issued (INV-3).
- Remove the FINDING note "offer shown again in session 2".

## 4. Docs to update on this branch
| File | Change |
|---|---|
| `docs/DECISIONS.md` | D-078: check before the offer, in `calculate_refund_offer`, on every path; the CLAIM_REVIEW category rule |
| `docs/GAPS.md` | G-091 closed on the branch (untested live until the preview below) |
| `docs/subagents/refund.md` | "Offer rule" and steps: the resolved-order check comes first; the new tests |
| `docs/V6_FOCUS.md` | Item 5 marked done |

## 5. Verification (before the PR)
1. Local AgentScript compiler: 0 errors, no new diagnostics. Descriptions ≤ 255 characters (G-051).
2. `sf agent validate authoring-bundle --api-name CARES`.
3. Dry-run deploy with all six CARES test classes: `CARES_Identity_FindContactByEmailTest`, `CARES_Refund_ActionsTest`, `CARES_OrderDataTest`, `CARES_StolenDelayedActionsTest`, `CARES_StolenDelayedPolicyTest`, `CsatRatingSaverTest`. All pass. The runner needs `CARES_Refund_Policy_Admin` (G-100).
4. **Live, before merge:** run B-RF-25 with `sf agent preview --authoring-bundle CARES --use-live-actions`, which runs the branch's local agent. Two sessions on one pool contact:
   - Session 1 pays.
   - Session 2 states the reason, shows no amount, and doesn't call `issue_resolution`.
   - If it escalates, the Case has category `CLAIM_REVIEW`.
5. After merge: deploy, publish and activate the next agent version, then re-run B-RF-25 with the batch runner.
