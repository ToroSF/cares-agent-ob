# Subagent: Refund — handoff brief for the owner

Branch: none yet (still the placeholder from the original skeleton, on `main`). Owner: **@lucasmpalomanes** — *inferred, not confirmed*: the only repo collaborator with no subagent PR open or merged as of 2026-10-19. Team: please confirm or correct this in `DECISIONS.md`.

This doc exists because Risk Detection (#1), Experience Rating (#2) and Stolen & Delayed Orders (#3) are all merged, and all three already produce context meant for Refund to consume. None of it has a consumer yet. This is the contract Refund needs to honor, written from the perspective of what already exists in the repo today, so the owner doesn't have to reverse-engineer it from three other people's PRs.

## In one paragraph

Refund is the one subagent in CARES that is allowed to actually offer money or credit. Every other subagent that touches an order (Stolen & Delayed Orders) or a customer's history (Risk Detection) is explicitly forbidden from issuing a refund itself — they compute context and hand it to Refund. Refund's job is: read that context, apply tier/limit policy (not yet defined — see Gaps below), and make one offer within the rules. It is currently a placeholder that does neither.

## Where it sits today

```
Agent Router -> Risk Detection (silent, runs once) -> Refund
                                                          ^
Agent Router -> Stolen & Delayed Orders -- STANDARD_PATH -----^ (via Risk Detection)
                                         -- FULL_REFUND/LOSS_ABSORPTION, customer picks REFUND/WALLET_CREDIT -> resolve_claim -> Risk Detection -> Refund
```

Two things already enforce that Refund cannot be reached without Risk Detection running first (D-006, D-011, D-015):
1. The router's `go_to_refund` action is gated: `available when @variables.risk_checked == True`.
2. Refund itself has a `before_reasoning` guard: `if @variables.risk_checked == False: transition to @subagent.risk_detection`. This is the one place in `CARES.agent` outside your own block that's already been edited on your behalf (by the Risk Detection owner, with the gate placed at your subagent per D-015) — see Gaps below for why that matters.

## What Refund currently is (verbatim, as of this doc's date)

```agentscript
subagent refund:
    label: "Refund"
    description: "PLACEHOLDER — issues a refund or store credit based on customer tier and order outcome, within defined limits. Detailed tier/limit/credit-percentage logic to be added in a future pass."

    before_reasoning:
        if @variables.risk_checked == False:
            transition to @subagent.risk_detection

    reasoning:
        instructions: ->
            | This sub-agent is a structural placeholder. Acknowledge the customer's refund request and let them know a refund or credit will be issued once this sub-agent's detailed logic is implemented. Do not invent specific amounts, tiers, or percentages.
```

No actions, no variables of its own, no Apex. This is the entire block.

## The context already waiting for you

Two upstream subagents already compute data meant for you. All of it is **set only by actions, never by the model** — read-only facts from your side, not conversational state.

### From Risk Detection (merged, PR #1)

| Variable | Type | Meaning |
|---|---|---|
| `risk_checked` | boolean | Always `True` by the time you run (your own guard enforces this) |
| `risk_status` | string | `CLEAN`, `NOT_CLEAN`, or `UNKNOWN`. **`UNKNOWN` must be treated as not-clean** — it's the fail-closed default on any lookup problem (no contact, bad window, query error), not a real signal (D-008) |
| `risk_issue_count` | number | Number of issue cases found in the lookback window |
| `risk_lookback_days` | number | The window used, default 30 (placeholder, pending Pronto confirmation) |

This is G-013 in `GAPS.md`: *"The Refund placeholder does not read `risk_status` yet — the result is computed but has no effect on the offer."* Closing G-013 is your first job.

### From Stolen & Delayed Orders (merged, PR #3)

Only populated when the customer came through that subagent (not every Refund case will have these set — a plain refund request that skipped Stolen & Delayed won't have them).

| Variable | Type | Meaning |
|---|---|---|
| `stolen_delayed_decision` | string | `STANDARD_PATH`, `FULL_REFUND`, `LOSS_ABSORPTION`, `MANUAL_REVIEW`, `ESCALATE`, or `ORDER_NOT_FOUND` |
| `stolen_delayed_reason` | string | Internal reason code — **never show this to the customer** |
| `stolen_delayed_full_refund_approved` | boolean | `True` only for `FULL_REFUND` / `LOSS_ABSORPTION`, re-verified with fresh data by `resolve_claim` right before you see it |
| `stolen_delayed_order_id`, `stolen_delayed_order_total`, `stolen_delayed_currency` | string / number / string | What to refund and in what currency, read from the delivery platform |
| `stolen_delayed_customer_choice` | string | `REFUND` (original payment method) or `WALLET_CREDIT` (app wallet) — the customer already chose this before reaching you |
| `stolen_delayed_loss_absorption` | boolean | `True` means: refund the customer, pay the driver in full, reimburse the restaurant — all three, not just the customer refund |
| `stolen_delayed_driver_compensation` | string | `PAY_IN_FULL`, `WITHHOLD_DELIVERY_PAY`, or `HOLD_FOR_REVIEW` — a recommendation for you to apply, not something Stolen & Delayed executes itself |
| `stolen_delayed_restaurant_reimbursement` | string | `REIMBURSE` or `NO_CHANGE` |
| `stolen_delayed_handoff_status` | string | `READY_FOR_REFUND` is your actual "go" signal for this path |
| `stolen_delayed_needs_person` | boolean | If `True`, the case has already been escalated — **never refund when this is `True`** |

The Stolen & Delayed owner's doc (`docs/subagents/stolen-delayed-orders.md`, section "Contract for Refund") already states the rule you need to implement:

> *"Refund owner: when `stolen_delayed_handoff_status == "READY_FOR_REFUND"`, refund the full `stolen_delayed_order_total` with the chosen method and apply the driver and restaurant recommendations. For `STANDARD_PATH` the flag is False: apply your normal policy, capped at the order total. Never refund when `stolen_delayed_needs_person` is True."*

### From Experience Rating (merged, PR #2)

No direct contract — Experience Rating runs *after* you, once the case is resolved. Nothing to read, but worth knowing it exists downstream so you don't accidentally route somewhere that skips it.

## What's genuinely missing (not just "not wired yet")

These are real open questions, not implementation details:

- **No loyalty tier field exists in the org** (G-003). "Based on customer tier" in your own description is currently undefined — there's no data source for it yet.
- **No refund/credit percentage or limit policy has been decided anywhere** (`[$]` markers throughout `docs/SPEC.md`). Pronto hasn't given real numbers for average order value, margin, or compensation caps.
- **No Apex or Flow for actually issuing a refund exists in this repo.** Stolen & Delayed's Apex explicitly never calls a refund/payout endpoint (it has a test asserting exactly that — see `CARES_StolenDelayedPolicyTest.cls`). The actual money-moving call is entirely your scope to design.
- **Nothing is saved anywhere** (G-008) — no case record, no refund record. If you build this, decide what record proves a refund happened and who reads it later.

## Suggested first steps

1. Read `docs/SPEC.md` section 2 (architecture) and `docs/DECISIONS.md` D-004 ("the script decides data and money; the model writes words") — the same rule the other two subagents followed applies to you: tier/limit/percentage logic belongs in Apex or Flow, not in `reasoning.instructions` text.
2. Close **G-013**: add a `before_reasoning` or `reasoning.instructions` branch that actually reads `risk_status` and changes behavior (e.g. a better offer on `CLEAN`, standard policy otherwise — never a better offer on `UNKNOWN`, consistent with D-008's fail-closed rule).
3. Implement the `READY_FOR_REFUND` contract from Stolen & Delayed Orders above — that path already has real computed values waiting (order total, currency, driver/restaurant recommendations), unlike the tier-based path which has no backing data yet.
4. Follow `docs/CONTRIBUTING.md`: branch as `feature/refund-subagent`, edit only your own `subagent refund:` block (the `before_reasoning` guard already there from D-015 is **not yours to remove** — it's a cross-subagent dependency; if you need to change it, ask the Risk Detection owner first per the repo's ownership rule), append new variables at the end of `variables:` prefixed `refund_`, and log your own decisions/gaps in `DECISIONS.md`/`GAPS.md` rather than editing someone else's row.
5. When you're ready to validate: local compiler (`node <skill-dir>/scripts/index-agent.mjs CARES.agent`) then `sf agent validate authoring-bundle --json --api-name CARES`. No deploy from your branch — that's a single end-of-week step per `CONTRIBUTING.md`.

## Related reading

- `docs/GAPS.md` — G-013 (this doc's main trigger), G-003, G-008, G-012, G-020, G-021
- `docs/DECISIONS.md` — D-004, D-006, D-008, D-011, D-015, D-018
- `docs/subagents/risk-detection.md` — the producer of `risk_status`
- `docs/subagents/stolen-delayed-orders.md` — the producer of the `stolen_delayed_*` context, with its own "Contract for Refund" section
- `docs/OPEN_ITEMS.md` — the merge-time checklist this doc was written to close one line of
