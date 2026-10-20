# Architecture notes: splitting subagents, and the AgentScript patterns behind each suggestion

Status date: 2026-10-20. All five subagent PRs (#1 Risk Detection, #2 Experience Rating, #3 Stolen & Delayed Orders, #4 docs, #5 Refund) are merged into `main`. Every subagent now does *something* — even if stubbed — and that's exactly when the cracks start to show: each box is quietly doing more than one job, and a few gaps already trace back to that.

This file is not a gap list (see `GAPS.md`) and not a decision log (see `DECISIONS.md`). It's a set of concrete architecture suggestions, each one tied to a real symptom already in this repo and to a documented AgentScript pattern, not a "clean code" opinion. Each section is tagged with the GitHub username whose subagent it touches, same convention as `OPEN_ITEMS.md`.

If you only read one thing from this file: **a subagent boundary should track a change in objective, instructions, actions, authority, or escalation behavior — not "this is logically one topic."** Refund today is one topic (money) but at least two different authorities (deciding an offer vs. actually issuing it). That mismatch is where most of the suggestions below come from.

## 1. Refund: split "decide" from "pay" — @lucasmpalomanes

**Symptom already in the repo:** D-021 and D-022 exist because the team already hit this problem once. The offer calculation, the confirmation, and the actual payout all live in one subagent block, and you had to hand-build workarounds to keep them from colliding — two separate `confirm_refund`/`confirm_store_credit` actions instead of one (D-022, because the model free-typed an amount when given the chance), and a same-turn transition bug into Experience Rating that swallowed the confirmation message (D-023).

**The pattern this maps to:** Agent Script's "Post-Action Re-resolution" pattern — persist a trusted result (`refund_offer_amount`, `refund_offer_eligible`) and gate the next step on it, so "decide" and "act" are provably sequenced instead of hoping the prompt enforces order. You're already doing a version of this with `refund_offer_calculated`; the suggestion is to make the subagent boundary match it, not just the variable.

**Concretely:** consider `refund_offer` (reads `risk_status` + Stolen & Delayed context, computes eligibility, never touches money) transitioning only after explicit confirmation to `refund_issue` (its only job is `issue_resolution` + `apply_settlement`). This is exactly the "smallest architecture first, split only when authority changes" rule — issuing money needs `require_user_confirmation`-grade care; calculating an offer doesn't. Keeping them in one block means every future change to the confirmation flow risks breaking the calculation, and vice versa.

**Why now and not before:** this wasn't worth proposing while Refund was a placeholder. Now that D-019 through D-032 exist — four order outcomes, two entry paths (direct vs. Stolen & Delayed handoff), a settlement step — the single block is already at the complexity where this split pays for itself. G-023/G-024/G-031 (stub amounts, no policy objects, no settlement retry) are exactly the kind of thing that gets easier to scope and test once "decide" and "pay" are separately named.

## 2. Risk Detection: separate "count" from "classify" — @Mateus-Goes

**Symptom already in the repo:** D-013 (the account-only counting fix) and D-014 (should a brand-new contact be `CLEAN`? — still `OPEN`, still a business decision Pronto hasn't made) are both changes to *what counts as clean*, and both required touching the same Flow that also does the SOQL counting. The real bug already found in review — the account-only branch (`Has_Account`/`Only_Contact`/etc.) being wired into the Flow but structurally unreachable — happened in a Flow that was asked to do two jobs at once: gather the raw numbers, and decide what they mean.

**The pattern this maps to:** Agent Script's "Deterministic vs. Subjective Flow Control" guidance — the classification rule (CLEAN/NOT_CLEAN/UNKNOWN, the 30-day window, whether a new contact counts as clean) is a policy decision that changes with business input (D-014 is explicitly waiting on Pronto). The counting itself is a stable, mechanical query. Mixing a policy that's still being negotiated into the same artifact as the query that's already correct makes every future policy tweak a risk to the thing that already works.

**Concretely:** today `CARES_Get_Risk_Result` Flow does both in one shot. Separating "count issue cases in a window" (a small, stable, well-tested piece) from "what status does that count produce" (a thin policy layer — could stay in the Flow as a clearly separate branch, or move to Custom Metadata thresholds like Stolen & Delayed already does with `CARES_Stolen_Delayed_Policy__mdt`) means D-014 can be resolved by changing one threshold, not by re-touching the counting logic that already has the account-only wiring bug fresh in memory.

**Also worth reading:** Stolen & Delayed Orders (PR #3) already put its thresholds in `CARES_Stolen_Delayed_Policy__mdt` instead of hardcoding them — that's the model to copy here once D-014 has an answer.

## 3. Stolen & Delayed Orders: name the two phases you already have — @rojasC10

**Symptom:** this one's less broken than the others — the policy matrix in `CARES_StolenDelayedPolicy` already *conceptually* separates "what happened" (rules 1-7: fraud, duplicate, value, delivery evidence) from "what to recommend" (rules 8-11: trust-based remedy, plus driver/restaurant compensation). But it's one 11-rule ordered list in one class, and the two `reasoning.actions` (`evaluate_delivery_exception`, `handoff_approved_claim`) already sit at roughly that boundary.

**The pattern this maps to:** Agent Script's "Smallest Architecture First" rule — this is deliberately *not* a call to add more subagents. The two actions you already built are the right granularity; the suggestion is narrower: as the compensation side grows (it's the part most likely to change — G-031 already flags that `apply_settlement` can't surface a failed settlement yet), keep the fraud/evidence detection rules and the compensation-recommendation rules in visibly separate methods or even separate classes inside `CARES_StolenDelayedPolicy`, so a change to "what counts as high trust" can't accidentally shift what counts as fraud.

**Why this one's lower priority than #1 and #2:** your test suite (40 cases, boundary coverage on GPS/claim-rate/value) is the best in the repo right now — that's exactly what makes a future split safe later. No urgency; just worth keeping in mind as `CARES_StolenDelayedPolicy` grows past 11 rules.

## 4. A shared identity/verification step, instead of five different guesses — Team

**Symptom:** `VerifiedCustomerId` has existed since the original skeleton and nothing has ever set it (G-006). Instead, every subagent independently decided what to do about an unverified or missing `ContactId`:
- Risk Detection: missing `ContactId` → `risk_status = UNKNOWN` (fail-closed, inside the Flow)
- Experience Rating: missing `ContactId` → skip the CSAT question entirely (`experience_rating_skipped`)
- Stolen & Delayed Orders: missing `ContactId` → `ESCALATE` with reason `NO_VERIFIED_CONTACT`
- Refund: missing/null `ContactId` → hand off to a person (D-026), and the team explicitly *dropped* building verification inside Refund itself with the stated reason "identity belongs to the team"

Four reasonable answers, four different places, and D-026's own "gave up" column says it out loud: a Refund-owned verification step was built on an earlier branch and deliberately dropped. That's not a coincidence — it's the project telling you where the real boundary is.

**The pattern this maps to:** Agent Script's "Verification Gate" pattern — a dedicated subagent that runs once, sets one trusted variable (`is_verified` or reuse `VerifiedCustomerId` for real), and every downstream subagent reads that one flag instead of re-deciding what "no identity" means for itself. This is the same shape Risk Detection already uses for itself (a silent `before_reasoning` step, not a chatty subagent) — just applied one level earlier, before any domain subagent runs.

**Concretely:** this doesn't have to be a conversational subagent (same argument Risk Detection already made for itself in D-007 — "a lookup, not a conversation"). It could be a silent `before_reasoning` step the router runs once per conversation, same mechanical shape as Risk Detection's own gate. The payoff: G-006 gets closed once, centrally, instead of once per subagent; and the next subagent anyone builds doesn't have to invent its own fifth answer to "what if there's no contact."

**Who should own this:** no current subagent owner is a clean fit (it's infrastructure, not a domain), so this is explicitly a Team decision, same category as "Router accepts the gate on `go_to_refund`" already is in `GAPS.md`'s "items the team will close together."

## 5. The router needs to know when *not* to reclassify — Router owner (unassigned)

**Symptom:** G-025, already filed: every turn starts at the router, so a one-word reply to a Refund question ("yes," an order number, "the fries") can get reclassified instead of continuing the task the customer was already in. Seen in preview on an earlier branch.

**The pattern this maps to:** Agent Script's router-first guidance lists *"Routing everything back to router by default, even when a direct subagent-to-subagent transition better matches the workflow"* as a named common migration mistake, not a one-off bug. The fix isn't a new subagent — it's an instruction change already proposed in G-025 ("if the customer is answering a question from an ongoing refund, choose Refund") plus, if that proves unreliable in practice, a small piece of state (e.g. `active_task` written only by the subagent that's mid-flow, read only by the router) rather than relying on the model inferring continuation from conversation history alone.

**Why this is listed here and not just in GAPS.md:** this is the one item that could make splitting Refund (#1 above) actively worse if done first — more sub-steps inside Refund means more chances for the router to misclassify a continuation reply mid-flow. Suggest fixing router continuation *before* or *alongside* splitting Refund's offer/issue steps, not after.

## General pattern for this team, going forward

Three things worth internalizing for whoever builds the next subagent (Pronto numbers, the identity gate, anything else):

1. **A new authority = a new subagent boundary; a new conversation topic doesn't automatically = one.** Stolen & Delayed Orders already does this well — "diagnose" and "recommend compensation" are different authorities living in the same policy file on purpose, at a granularity that's working. Refund currently has "decide" and "pay" at different authority levels but the same subagent boundary — that's the one place in this repo where the two are out of sync.
2. **Put volatile policy in data, not in control flow.** `CARES_Stolen_Delayed_Policy__mdt` (PR #3) is the pattern every future threshold-with-a-`[$]`-marker should copy, instead of hardcoding like today's Refund stubs do (D-020, explicitly temporary) or burying a business rule inside a Flow's branching logic like Risk Detection's open D-014 question currently risks doing.
3. **When two subagents independently invent an answer to the same missing-data question, that's a signal the question belongs to a shared step, not to either of them.** `ContactId` being missing/null is the clearest example already in this codebase (section 4 above). The next time this happens, that's the cue to pull the shared concern out rather than let a third subagent invent a fifth behavior.
