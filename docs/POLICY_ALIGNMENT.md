# Policy alignment: CARES vs the official Pronto documents

What each official rule says, what CARES does about it, and what we will do. Sources are in [sources/](sources/). Written 2026-10-20 by @Mateus-Goes (grounding), on `feature/grounding-policy-alignment`.

Two snapshots so the panel can see the iteration:
- **v0** = `main` at 854ea60 (the published v1 agent), before this branch.
- **v1** = this branch, merged with `main` after PR #18 (real Refund policy, audit row). Built, compiled locally, **not deployed and not tested live**.

Legend: ✅ aligned · 🟡 partial · 🔴 different (contradicts the rule) · ⬜ missing (the rule asks for it, nothing exists) · ❓ to decide (Pronto or an owner) · ∅ no source (our own number) · 🚫 out of scope (on purpose)

## The matrix

| ID | Official rule (paraphrase) | v0 (main) | v0 | v1 (this branch) | v1 | Owner | Next step |
|---|---|---|---|---|---|---|---|
| POL-P01 | Be calm and clear: acknowledge, then the next step | Tone only in Refund and Stolen & Delayed | 🟡 | Same line in the global system instructions | 🟡 | Team | Templates (P) still unused: proposal W3 |
| POL-P02 | Do not promise what you can't confirm; no amount without confirmed eligibility | Refund: "never say approved unless issued"; amounts only from actions. Stub `calculate_refund_offer` always says eligible | ✅ text / 🟡 code | Also in the global never-list. Since PR #18, `calculate_refund_offer` decides eligibility from the tier and policy rows (D-046, D-047); since v5 the order and item values come from the real Data Cloud orders (D-071, D-072) | ✅ text / 🟡 code | @lucasmpalomanes | Tier and policy rows in the org before the publish (R-17) |
| POL-P03 | Least disruptive resolution, chosen by category | Same fixed offer for every category | 🔴 | Since PR #18 the ceiling and credit bonus come from one policy row per tier and outcome (D-046). The offer type is still refund or credit for every category | 🟡 | @lucasmpalomanes | Proposal: category → offer type rule (no amounts) |
| POL-P04 / F05 | Options: replacement, credit, refund | Refund offers refund or credit only; replacement only as a Stolen & Delayed re-dispatch | 🔴 | No change | 🔴 | @lucasmpalomanes | ❓ Is replacement an operation the agent may start? (question to Pronto) |
| POL-P05 | 1–2 items missing → partial credit/refund | Stub values every item issue at 12.00 | 🔴 ∅ | Since PR #18 the refund is the value of the affected items, capped by the policy row (D-046). Item prices are still the stub's (G-023, G-004) | 🟡 ∅ | @lucasmpalomanes | Real prices need order data (G-004) |
| POL-P06 | Most of the order wrong → replacement or full credit/refund | Not built | ⬜ | No change | ⬜ | @lucasmpalomanes | Gap G-071 |
| POL-P07 / P08 | Minor delay → goodwill; severe delay + poor quality → credit/refund | No delay measure, no ETA | ⬜ | D-100 (`feature/sd-delivery-timing`, not deployed): lateness from the order's own times against the 40-minute promise; minor (≤ 15 min) → 15% of the order, severe → 50%, capped by the tier's Delayed row `[$]`. Poor quality still goes through Refund's item path | 🟡 built | @lucasmpalomanes / @rojasC10 | Pronto to confirm the percentages (G-071) |
| POL-P09 | Never arrived: verify address and proof → full refund or replacement, customer's choice | Stolen & Delayed checks photo/GPS and offers refund, wallet credit or re-dispatch; does not verify the address | 🟡 | Also an order still on its way far past its time is treated as never arrived (D-100: `LIKELY_LOST`, full refund for high trust). Address still not verified | 🟡 | @rojasC10 | Test B-PO-11 |
| POL-P10 | Create a case when the customer asks for refund, credit or replacement | `issue_resolution` stub writes nothing | ⬜ | Since PR #18 `issue_resolution` writes a `CARES_Resolution__c` audit row and blocks a second payout on the same order (D-048). It is not a Case | 🟡 | @lucasmpalomanes | ❓ Is the audit row enough, or does Pronto want a Case? |
| POL-P11 | Check for an open case for the same order/issue; update it, don't duplicate | Flow always creates; no lookup; no order field on Case | ⬜ | Flow looks for an open case (same contact, order, category) and adds a private comment instead (D-063) | ✅ built | Team (Escalate) | Test B-PO-14 (live) |
| POL-P12 | Case for a dispute or when the customer asks for escalation | Escalate logs a case, then `@utils.escalate` | ✅ | Same, plus category | ✅ | Team | — |
| POL-P13 / M02 | **Escalate immediately:** food safety or contamination | No rule; no food keywords; router sends "money" to Refund | ⬜ critical | Router safety-first rule → `urgent_escalation` → case URGENT, High priority, no offer (D-061) | 🟡 built | Team (router) | Instruction-based detection: test B-PO-01..03, R-12 |
| POL-P14 | Escalate immediately: harassment or unsafe delivery | Only Stolen & Delayed instruction line | 🟡 | Same safety-first rule, any subagent | 🟡 built | Team | B-PO-04 |
| POL-P15 | Escalate immediately: fraud or account takeover | Platform flags only inside Stolen & Delayed | 🟡 | Same safety-first rule | 🟡 built | Team | B-PO-05 |
| POL-P16 | Escalate: repeated failures in a short period | Risk Detection only lowers the offer (D-025) | 🔴 | At `risk_issue_count >= risk_review_threshold` (3 `[$]`), Risk Detection sends to a person with category PATTERN_REVIEW (D-062) | ✅ built | @Mateus-Goes | B-PO-06; threshold is ours, not Pronto's |
| POL-P17 | No refund for clearly abusive patterns without supervisor review | Stolen & Delayed: MANUAL_REVIEW. Refund ignores `riskStatus` | 🟡 / 🔴 | Above threshold: no automatic offer (D-062). Below: since PR #18 only CLEAN unlocks the higher ceiling (D-046); NOT_CLEAN and UNKNOWN get the standard one, still automatic | 🟡 | @Mateus-Goes / @lucasmpalomanes | Below the threshold an abusive pattern still gets an automatic (smaller) offer |
| POL-P18 | Verify the customer before sensitive actions (email flow or Member Number) | Channel `ContactId` only; `VerifiedCustomerId` never set; no Member Number in the org. Since PR #16: an unverified email lookup when the chat has no contact (D-058, G-065) | 🟡 ❓ | No change | 🟡 ❓ | Team | ❓ Is a channel contact "verified"? (question to Pronto) |
| POL-P19 | Never request or share full card numbers | No card field anywhere; no instruction | 🟡 | Global never-list: never ask, never repeat, ask the customer not to share | 🟡 built | Team | B-PO-08; instruction only (R-14) |
| POL-P20 | "Where is my order?": status + ETA; no movement → case | Not built | ⬜ | Pronto Help explains status words and that ETA is an estimate; "has not moved" → Stolen & Delayed. v5: the Order Status sub-agent gives the customer's real status and ETA from Data Cloud (D-075) | ✅ built in v5 | @Mateus-Goes | "No movement → case" goes through Stolen & Delayed; D-100 tells "not late yet" from late and lost |
| POL-P21 | "I want a refund": confirm category, follow rules, case | Category yes, case no | 🟡 | No change | 🟡 | @lucasmpalomanes | Linked to P10 |
| POL-P22 | Route to the right escalation queue | No Case queue; no Type/Priority | ⬜ | Queue `CARES_Escalations`; Type, Reason, Priority, Status from the category | ✅ built | Team | Queue has no members yet (G-068) |
| POL-F01 | Status words: Submitted / Accepted / Picked Up / Delivered / Canceled | Stolen & Delayed platform uses DELIVERED / IN_TRANSIT / CANCELLED | 🔴 words | Pronto Help answers with the FAQ words. v5: `get_order_status` maps the order data to them (Preparing → Accepted, PickedUp / Out for Delivery → Picked Up, D-075) | 🟡 | @rojasC10 | Stolen & Delayed's platform codes are still not mapped (G-081) |
| POL-F02 | ETA is an estimate | Not built | ⬜ | Pronto Help (retrieved) | ✅ built | @Mateus-Goes | Golden set Q-02 |
| POL-F03 | Change address → contact support as soon as possible | Not built | ⬜ | Pronto Help says so and hands to a person | ✅ built | @Mateus-Goes | Category for it (Reason "Can't update delivery address") not built: G-072 |
| POL-F04 | "Delivered but not here": check address, doors, who accepted it | Stolen & Delayed goes straight to the evidence check | 🔴 / ❓ | No change | 🔴 / ❓ | @rojasC10 | ❓ One self-check turn before the check? |
| POL-F06 | Cold food: delivery time, photos, packaging | Refund asks only for the items | ⬜ small | No change | ⬜ | @lucasmpalomanes | Proposal: three questions in the Quality_Issue step |
| POL-T01 | Promo codes: once per order, may not combine, expired can't be reactivated | Not built | ⬜ | Pronto Help (retrieved) | ✅ built | @Mateus-Goes | Golden set Q-05..Q-07 |
| POL-T02 | Member Number for benefits and identification | Not in the org | ❓ | No change | ❓ | Team | Question to Pronto |
| POL-T03 | Gift certificates can be a recovery credit; may expire; may be restricted | Refund says "store credit in the app wallet", no expiry | ❓ | Pronto Help explains the terms; Refund unchanged | ❓ | @lucasmpalomanes | ❓ Is our store credit a gift certificate? |
| POL-T04 | Promo/gift not applying → support needs code, storefront, total | Not built | ⬜ | Pronto Help (retrieved) tells the customer what to share | ✅ built | @Mateus-Goes | Golden set Q-09 |
| POL-M01 | No guarantee of allergen-free preparation | Not built; the model could reassure | ⬜ critical | Hard rule in the global never-list **and** in Pronto Help, even if retrieval says otherwise | ✅ built | Team | B-PO-07 |
| POL-M03 | Availability, storefront standards, reviews | Not built | ⬜ | Pronto Help (retrieved). Merchant operations stay out of scope | 🟡 / 🚫 | @Mateus-Goes | Golden set Q-12..Q-14 |
| POL-N01 | (No source) amounts, %, windows, tiers | 15.00 / 18.00, +20%, 30 days, Gold, 100 USD, trust limits | ∅ | Refund ceilings and the credit bonus come from `CARES_Refund_Policy__c` rows that CRM users set (D-046). Seeded in the team org on 2026-10-21 by `scripts/apex/seed-refund-tiers.apex` (D-073, R-17 closed): Explorer / Insider / Pronto Plus, standard max 25 / 40 / 60, clean-history max 35 / 55 / 80, bonus 10 / 15 / 20%. Validation rules keep each row consistent: clean max at least the standard max, no negative limits, bonus 0-100% (D-077). The approved-claim path uses the same row's bonus, no default (D-077). Still ours: 30 days, 100 USD, trust limits, the review threshold 3, and no refund timing promise (D-077) | ∅ | Everyone | All labeled `[$]` (D-065) |

**Count (33 rules):** v0 had 2 ✅, 8 🟡, 6 🔴, 14 ⬜ (2 critical), 2 ❓, 1 ∅. v1 has 10 ✅ (built, not tested), 15 🟡, 2 🔴, 3 ⬜, 2 ❓, 1 ∅, and no critical ⬜ left. Three of the 🟡 (P03, P05, P10) come from PR #18's Refund code, which is not deployed or tested yet either. "Built" is not "tested": every v1 status needs the live run in [TEST_PLAN.md](TEST_PLAN.md) before the panel calls it done.

## Our own rules with no official source
Valid, but they are team decisions, not Pronto policy. Say so if asked.
- Refunds only to the original payment method (Refund, D-026).
- At most 3 order lookups (Stolen & Delayed).
- "Never mention risk checks, GPS, scores" (several subagents). Close to POL-P02 in spirit, not in the text.
- All Stolen & Delayed trust and GPS limits (`CARES_Stolen_Delayed_Policy__mdt`).
- Risk Detection window (30 days) and review threshold (3).
- The refund ceilings and credit bonus, once someone fills the `CARES_Refund_Policy__c` rows (D-046).

## Questions for Pronto (open)
1. Which numbers are policy (amounts, %, windows, tiers), and who owns them?
2. Is a channel contact enough to count as verified, or do we need the email flow or the Member Number? (POL-P18, T02)
3. Is a replacement an operation the agent may start, and through which system? (POL-P04)
4. Is store credit the same as a gift certificate? Does it expire? (POL-T03)
5. Is the urgent queue (food safety, harassment, fraud) different from the general one? (POL-P22)
6. Who does supervisor review, and how does the agent ask for it? (POL-P17)
7. What counts as "repeated failures within a short period"? (POL-P16: our 3 in 30 days is a guess)
