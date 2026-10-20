# Spec: fixing the contracts between subagents

Status date: 2026-10-20. Status: `DECIDED` (all recommended paths approved 2026-10-20). Built on `fix/inter-subagent-contracts` except C-10 (see 0.1). Nothing is deployed. Source: `CARES.agent` and the Apex on `main` at `a605c79`.

A "contract" here is anything one subagent writes that another one reads: shared variables, transitions, enum values, ids, and the input/output types between an action in the agent and the Apex or Flow behind it. Every problem below was found by reading the code. None was found in a live run, because nothing is deployed yet (G-015). Each item says where the problem is, a concrete case that breaks, the fix, who owns it, and how to test it.

Tags follow `OPEN_ITEMS.md`: @lucasmpalomanes (Refund, D-027), @rojasC10 (Stolen & Delayed), @Mateus-Goes (Risk Detection), Experience Rating owner, Router owner (unassigned), Team.

## 0. Summary

| ID | Problem | Severity | Owner | Touches another owner's block? |
|---|---|---|---|---|
| C-01 | `save_csat_rating.ratingId` is typed `string` in the agent but Apex returns `Id` | Blocks validation | Experience Rating owner | No |
| C-02 | Refund ignores a Stolen & Delayed handoff when it already found an order (Refund → S&D → Refund) | High: dead end, and a promised refund is never paid | @lucasmpalomanes | No |
| C-03 | `stolen_delayed_*` state is never reset, so a second Stolen & Delayed claim in the same conversation cannot start | High: dead end | @rojasC10 | No |
| C-04 | Stale `stolen_delayed_customer_choice` hides `confirm_refund` on later direct refunds | High: refund can't be confirmed | @lucasmpalomanes | No |
| C-05 | Stale `stolen_delayed_needs_person` blocks every later refund in the conversation | Medium | @lucasmpalomanes, @rojasC10 | No |
| C-06 | No one owns the escalation once a case is handed to Refund with `needs_person` True. Refund says "a person will take it" and does not escalate | Medium | @lucasmpalomanes | No |
| C-07 | Order ids from `find_order` and from the delivery platform may be different id spaces | Medium: possible double payout once real data exists | @lucasmpalomanes, @rojasC10 | No (decision) |
| C-08 | S&D and Refund use different words and amounts for the same thing (`WALLET_CREDIT` vs `Store_Credit`; "full order value" vs total + bonus; currency vs `$`) | Medium: customer told two different amounts | @lucasmpalomanes, @rojasC10 | No |
| C-09 | "Missing contact" means `""` in some subagents and `""` or null in others | Medium | Each owner, Team for the rule | No |
| C-10 | `risk_checked` becomes True even when the risk action did not run | Medium (already G-020, G-022, D-018) | @Mateus-Goes | No |
| C-11 | Escalations carry no context to the person | Medium | Team, Router owner | Yes (Escalate to Human) |
| C-12 | Router can take a mid-flow reply away from Refund or S&D | Medium (already G-025) | Router owner | Yes (router) |
| C-13 | `csat_attempted` is per conversation, but its description says per case | Low | Experience Rating owner | No |

Suggested order: C-01 (unblocks validation), then C-02 to C-06 (dead ends in the shipped script), then C-08 and C-09, then the team items (C-07, C-11, C-12). C-10 waits for a live run.

### 0.1 Implementation status (`fix/inter-subagent-contracts`)
Checked with the local AgentScript compiler (`@sf-agentscript/agentforce` 2.9.27): 0 errors, same 4 unused-variable notes as `main`. Not yet checked with `sf agent validate authoring-bundle` or a dry-run deploy (they need an org). Nothing was run live.

| ID | Status | Decision |
|---|---|---|
| C-01 | Built | |
| C-02 | Built (fix 2 only; see C-02) | D-033 |
| C-03 | Built | D-034 |
| C-04 | Built, via the C-08 mapping | D-035 |
| C-05 | Built: the block applies only to the Stolen & Delayed order | D-039 |
| C-06 | Built | D-037 |
| C-07 | Decided: platform order id everywhere. Contract text updated; the real `find_order` must return it | D-038 |
| C-08 | Built. Direct path still shows USD from the stub | D-035, D-036 |
| C-09 | Built (Experience Rating only; the Flow and the Apex already treat null as blank) | |
| C-10 | Decided to wait for a live run (T-14); D-018 stays open | D-042 |
| C-11 | Built: `CARES_Create_Escalation_Case` Flow + `CARES_Escalation_Access`, run once before the transfer. Stolen & Delayed escalates through Escalate to Human | D-040 |
| C-12 | Built: `router_active_task` + router instructions | D-041 |
| C-13 | Built: description changed, behavior kept | D-042 |

## 1. Rules for every contract (proposed)

These rules come from what went wrong below. Each fix in section 2 applies one or more of them.

| Rule | Text | Why |
|---|---|---|
| R1 | **The producer owns the reset.** A subagent that writes shared variables also clears them when its job ends. The consumer never writes them (keeps D-032) | Today nobody clears `stolen_delayed_*` (C-03, C-04, C-05) |
| R2 | **Read the producer's state only through a "ready" check.** A consumer gates on the producer's done flag (`stolen_delayed_handoff_status == "READY_FOR_REFUND"`) and on the order it is about, never on one leftover field (`stolen_delayed_customer_choice`) | C-04 |
| R3 | **A handoff wins over a half-finished local step.** If a producer hands over a new order, the consumer drops its own unfinished state for a different order | C-02 |
| R4 | **One word per value.** Each enum has one owner and one list of values. Any mapping between two vocabularies is written in the script, not left to the model | C-08 |
| R5 | **One test for "no value".** Missing means `is None or == ""`, everywhere | C-09, G-029 |
| R6 | **Agent types match the target exactly.** Apex `Id` outputs are `object` + `lightning__recordIdType`, or the Apex field is `String`. Checked by `sf agent validate authoring-bundle` before each PR | C-01 |
| R7 | **The step that says "a person will help" makes the handoff.** Saying it without calling an escalate action is not allowed | C-06 |

## 2. Problems and fixes

### C-01. `ratingId` type mismatch (Experience Rating)
**Where:** `CARES.agent`, `save_csat_rating` outputs, `ratingId: string`. `CsatRatingSaver.cls`, `Result.ratingId` is `Id`.
**Breaks:** the simulator rejects the action: "invalid data type for the output parameter 'ratingId'". The whole agent fails validation, not only this subagent.
**Fix (recommended):** change the agent declaration:
```
ratingId: object
    complex_data_type_name: "lightning__recordIdType"
    filter_from_agent: True
```
Agent-only change, no Apex redeploy. Nothing reads `ratingId`. Alternative: make the Apex field `String`. Use that if a Flow will reuse the action later.
**Also:** every other action's types were checked against its Apex or Flow and match (`String`↔`string`, `Decimal`↔`number`, `Boolean`↔`boolean`). This is the only `Id` field.
**Test:** `sf agent validate authoring-bundle` passes. Reset the simulator; a rating of 2 with a comment saves, and `csat_saved` is True.

### C-02. Refund → Stolen & Delayed → Refund ignores the handoff (Refund)
**Where:** top of the Refund `instructions`: both handoff branches need `@variables.refund_order_id == ""`.
**Breaks:** a direct-path customer: "my order", `find_order` sets `refund_order_id`. Customer then says "actually it never arrived". Refund offers `go_to_stolen_delayed`. Stolen & Delayed checks the order:
- `STANDARD_PATH` → Risk Detection → Refund. `refund_order_id` is not empty, so `refund_sd_path` stays blank. Refund asks "what went wrong" again, `log_order_issue` rejects `Stolen` (direct path), the model is told to use `go_to_stolen_delayed` again. Stolen & Delayed now has `stolen_delayed_evaluated == True`, so `check_order` is hidden. Dead end.
- `READY_FOR_REFUND`: the customer was told they get the full order value, and Refund ignores it. A promise is never paid.

**Fix (built):** in the handoff branches, replace `refund_order_id == ""` with "not already on a Stolen & Delayed path, nothing confirmed or attempted": `@variables.refund_sd_path == "" and @variables.refund_confirmed == False and @variables.refund_issue_attempted == False`. On a match, reset the `refund_` offer variables, then set the path (applies R3).
Not built: clearing state inside `go_to_stolen_delayed`. A `@utils.transition` action can't run `set`, and the branch above covers every route into Refund, including the router.
Both are inside the Refund block.
**Test:** new R-18: direct path, find order, then "it never arrived". Expect S&D check → Risk Detection → Refund on the STANDARD path, asking "stolen or late?". R-19: same, with a high-trust mock → READY path, only the chosen method offered.

### C-03. Stolen & Delayed state is never reset (Stolen & Delayed)
**Where:** `stolen_delayed_*` variables. Nothing sets them back. Refund does not write them by design (D-032).
**Breaks:** a customer gets a READY refund for order A, then reports order B as stolen. `stolen_delayed_evaluated` is still True and `check_order` is hidden. `handoff_status` is `READY_FOR_REFUND`, which has no branch in the S&D instructions, so the model gets no step to follow. The same applies after `REDISPATCHED`.
**Fix (built, applies R1):** Stolen & Delayed resets itself.
- New `before_reasoning`: if `stolen_delayed_order_id != ""` and it equals `refund_handled_order_id` (Refund paid this claim), every `stolen_delayed_*` variable goes back to its default.
- After a re-dispatch, `check_order` stays available. Its post-action restarts the claim: lookups back to 1, and `handoff_status`, `customer_choice`, `loss_absorption` and `redispatch_reference` cleared. A re-dispatch is not reset on entry, so a follow-up question about it still sees the reference.
- `READY_FOR_REFUND` that is not paid yet now has a branch and a `continue_to_refund` action (transition to Risk Detection, which hands on to Refund).

Never resets while a person is needed (see C-05).
Reading `refund_handled_order_id` is a read, not a write, so D-032 still holds. It becomes part of the Refund contract: "Refund sets `refund_handled_order_id` to the S&D order id after a successful payout and never clears it". Add that line to `docs/subagents/refund.md`.
**Test:** new T-SD-10: READY payout for order A, then "another order never arrived". Expect a fresh `check_order` for order B, `stolen_delayed_lookups` back to 0.

### C-04. Stale `stolen_delayed_customer_choice` hides `confirm_refund` (Refund)
**Where:** `confirm_refund` has `available when ... and @variables.stolen_delayed_customer_choice != "WALLET_CREDIT"`. That condition applies on every path.
**Breaks:** READY claim paid as wallet credit. Later, in the same conversation, a direct-path refund for a wrong item. The customer picks "refund to card", but `confirm_refund` is still hidden because the old choice is `WALLET_CREDIT`. They can only confirm store credit.
**Fix (applies R2):** scope the condition to the READY path: `... and (@variables.refund_sd_path != "READY" or @variables.stolen_delayed_customer_choice != "WALLET_CREDIT")`. This mirrors `confirm_store_credit`, which is already scoped correctly. C-03 also removes the stale value, but Refund should not depend on that.
**Test:** new R-20: R-03 followed by R-01 with a refund chosen. Expect `confirm_refund` available.

### C-05. Stale `stolen_delayed_needs_person` blocks later refunds (Refund, Stolen & Delayed)
**Where:** Refund's first branch, and the `issue_resolution` gate, read `stolen_delayed_needs_person` with no check on which order it is about.
**Breaks:** S&D escalates order A (`MANUAL_REVIEW`). The escalation fails or the customer comes back to the bot (S&D instructions say "if the handoff fails, say the team will follow up"). They then ask about a wrong item on order B. Refund says "a person will take it from here" and never offers anything.
**Fix:**
- Refund (R2): only honor the flag for the S&D order: `@variables.stolen_delayed_needs_person == True and (@variables.refund_sd_path != "" or @variables.refund_order_id == "" or @variables.refund_order_id == @variables.stolen_delayed_order_id)`. Keep the `issue_resolution` gate strict when `refund_sd_path != ""`.
- Stolen & Delayed (R1): do not clear `needs_person` itself (a person still owns order A). Document that it describes `stolen_delayed_order_id` only.

The order-id comparison depends on C-07.
**Test:** new R-21: S&D `MANUAL_REVIEW` on order A, escalation fails, then a wrong item on order B. Expect a normal offer for B. Nothing for A.

### C-06. Refund says "a person will take it" without escalating (Refund)
**Where:** Refund branch `stolen_delayed_needs_person == True` only gives text. Refund also has an "offer to connect them with a human agent" text for ineligible offers, but leaves the decision to the model.
**Breaks:** the router sends a needs-person customer to Refund (`go_to_refund` only checks `risk_checked`). The customer is told a person is coming, and nobody comes.
**Fix (applies R7):** in that branch, tell the model to call `{!@actions.go_to_escalate_human}` in the same reply. Stolen & Delayed already does this for its own cases.
**Test:** R-16 extended: expect a transition to Escalate to Human, not just text.

### C-07. Two order id spaces (decision, Refund and Stolen & Delayed)
**Where:** `find_order.orderId` is an "internal order identifier" (stub: `STUB-ORDER-1042`). `evaluate_delivery_exception.orderId` is the delivery platform's id, from the customer's order number. Refund uses both as `refund_order_id`, passes them to `issue_resolution`, and compares them with `refund_handled_order_id`. The planned `CARES_Resolution__c.Order_Id__c` (unique, D-024) would also hold both.
**Breaks (once real data exists):** the same order paid once through the direct path (internal id) and again through S&D (platform id). The unique field does not catch it because the two ids differ. C-05's comparison would also fail.
**Fix:** `OPEN`, needs a team decision. Options: (a) both actions return the same canonical id, the platform id, and `find_order` maps it; (b) both return both ids and the contract uses one. Recommendation: (a), because the platform is the source of truth for orders. Until decided, document that ids are only comparable within one path.
**Test:** when real data exists: the same order through both paths in one conversation → second attempt not eligible.

### C-08. Two vocabularies and two amounts for the same remedy (Refund, Stolen & Delayed)
**Where:**
- S&D choice: `REFUND` / `WALLET_CREDIT` / `REDISPATCH`. Refund: `Refund` / `Store_Credit`. The mapping lives only in Refund's instruction text.
- S&D tells the customer: "they will get the full order value back: {total} {currency}" and "do not change or mention any other amount". Refund then offers `total + bonus` as credit (D-029) and shows `$` (G-033).
- `calculate_refund_offer` returns `currencyCode`, but nothing stores it.

**Breaks:** a customer is told "25.00 EUR, refund or wallet credit?", picks wallet credit, and Refund says "store credit of $30.00". The amount and currency both changed between two messages.
**Fix (applies R4):**
1. Write the mapping in the script: Refund sets `refund_chosen_resolution` from `stolen_delayed_customer_choice` on the READY path (`REFUND` → `Refund`, `WALLET_CREDIT` → `Store_Credit`) at handoff time. Keep the confirm actions for the explicit yes (D-028).
2. S&D stops quoting the credit amount: "the full order value back as a refund, or as app credit (credit is worth a bit more)". Pick one wording, and say in `stolen-delayed-orders.md` that S&D never quotes a credit amount. Alternative: S&D quotes both from an action. Not recommended, because amounts belong to Refund.
3. Pass currency (built): `calculate_refund_offer` gets a new `orderCurrency` input (`stolen_delayed_currency` on the S&D paths, blank otherwise). Its `currencyCode` output goes to a new `refund_currency`, which every amount shows instead of `$`. The stub echoes `orderCurrency`, or USD when it's blank. This closes G-033 for the S&D paths.

**Test:** R-03 with a EUR mock order: S&D and Refund show the same currency, and the credit amount is shown once, by Refund.

### C-09. "Missing contact" has two meanings (each owner, rule by Team)
**Where:** Refund checks `ContactId is None or == ""`. Experience Rating checks only `== ""`. Risk Detection passes the value to the Flow unchecked. S&D sends it to Apex unchecked. G-029: in preview `ContactId` is null, not blank.
**Breaks:** with a null `ContactId`, Experience Rating does not skip. It asks for a rating, `save_csat_rating` fails, and the customer hears "thanks, but it wasn't recorded".
**Fix (applies R5):** every subagent uses `is None or == ""`. Experience Rating: change its `before_reasoning` condition. Risk Detection: check the Flow handles a null input (expected `UNKNOWN`). S&D: Apex already returns `NO_VERIFIED_CONTACT` for blank; check null too. Longer term: the shared verification step in `ARCHITECTURE_NOTES.md` section 4.
**Test:** preview without a channel (null `ContactId`): Experience Rating goes to `experience_rating_skipped`; Risk Detection gives `UNKNOWN`; S&D escalates.

### C-10. `risk_checked` is set even when the action did not run (Risk Detection)
Already tracked: G-020, G-022, option D-018. Restated here because it is a contract problem: Refund trusts `risk_checked` as "a result exists", and today it only means "the script tried". `risk_status` defaulting to `UNKNOWN` keeps it safe for money. No change proposed until a live run (T-14) shows what the platform does on action failure.

### C-11. Escalations carry no context (Team, Escalate to Human)
**Where:** S&D calls `@utils.escalate` directly. Refund transitions to `escalate_to_human`, which reads no variables. The escalate fallback says "log a support case", but there is no action for it.
**Breaks:** SPEC section 1: "No customer has to repeat the story". Today the person receives the transcript only: no decision, no reason code, no amount offered.
**Fix:** `PROPOSAL` for the team. Add a script-run "create escalation case" action (Flow, D-005) that writes the summary fields (`stolen_delayed_decision`, `stolen_delayed_reason`, `refund_offer_amount`, `refund_chosen_resolution`, `risk_status`; all internal, never shown to the customer) before any escalate, and route both S&D and Refund through `escalate_to_human`. Needs the Escalate owner and G-007 (Omni-Channel).

### C-12. Router can take mid-flow replies away (Router owner)
Already tracked: G-025, `ARCHITECTURE_NOTES.md` section 5. It now applies to S&D too: "wallet credit" in reply to S&D's question can be routed to Refund, which has no READY handoff yet. Fix as proposed there: an `active_task` variable written by the subagent mid-flow and read by the router. Should be done before splitting Refund.

### C-13. CSAT is once per conversation (Experience Rating owner)
`csat_attempted` is never reset, but its description says "once per case". With two cases in one conversation, the second is not rated. Fix: either change the description to "per conversation" (simplest, recommended), or reset it when Refund or S&D finishes a new case. Low priority.

## 3. What does not change
- D-032: Refund never writes `stolen_delayed_*`. C-03 has S&D reset its own state instead.
- D-015: the gate at the top of Refund stays.
- D-023: Refund does not transition after issuing.
- SD-D1: S&D never moves money.

## 4. Docs to update when each fix lands
| Fix | Docs |
|---|---|
| C-01, C-09, C-13 | `subagents/experience-rating-changelog.md` |
| C-02, C-04, C-05, C-06, C-08 | `subagents/refund.md` (tests R-18 to R-21, "Reads, not owned"), `DECISIONS.md` |
| C-03, C-05, C-08 | `subagents/stolen-delayed-orders.md` (contract table, T-SD-10), `DECISIONS.md` |
| C-07, C-11 | `DECISIONS.md` (team decision) |
| All | Close or link the matching rows in `GAPS.md` (G-034 to G-044) |
