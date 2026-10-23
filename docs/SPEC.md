# CARES spec

Status date: 2026-10-19. Source: the `CARES` authoring bundle in this repo (identical to the version in the shared team org on this date).

> **Deploy status (2026-10-21):** `main` is deployed to the team org. Agent v4 (PR #15, #18, #19, #20) was published and activated on 2026-10-21. v5 adds real orders from Data Cloud (D-071) and the Order Status sub-agent (D-075). Deploy steps: [DEPLOY_CHECKLIST.md](DEPLOY_CHECKLIST.md).

## 1. Use case and business framing

Status: `PROPOSAL` (draft for the team to edit). Numbers marked `[$]` need Pronto data; do not invent them.

**Context.** Pronto is a food delivery marketplace. Switching to another app costs the customer nothing, so how we handle a bad order matters as much as price.

**Internal customer.** The Pronto customer support team. They receive the cases CARES cannot or should not close, and they pay the cost of every refund. Executive leadership judges success on retention.

**Customer challenge.** A customer whose order was stolen or late gets a slow, generic answer. A loyal customer with a clean history is treated like anyone else, or a fraud-prone claim is paid without a check. Either way Pronto loses money or the customer.

**Job Story (support POV).**

> When a customer contacts Pronto because an order was stolen or arrived late, I want the agent to check the order and the customer's recent history and then resolve it right away with a refund or credit that fits the policy and the customer's record, so that the customer feels looked after and keeps ordering with Pronto instead of switching apps, and my team only sees the cases that really need a person.

**KPIs.**

| KPI                                                                                   | Type       | How to measure                                           | Pilot target (D-104)                          |
| ------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------- | --------------------------------------------- |
| Customer retention after a complaint (for example orders in the 30 days after a case) | Headline   | Compare customers served by CARES with a baseline `[$]`  | 30-day reorder ≥ 74% (+2 pts vs control)      |
| Compensation cost per case vs policy                                                  | Guardrail  | Total credit and refunds / cases, against the policy cap | 100% inside policy, average ≤ a person's ($15) |
| Share of cases solved without a person                                                | Efficiency | Cases closed by CARES / all CARES cases                  | ≥ 70% (pause under 50%)                       |
| Customer rating after resolution                                                      | Quality    | Experience Rating score                                  | ≥ 60% thumbs up (baseline 40% `[$]`)          |

Baselines, pause lines, pilot design and the go/no-go rule: [PILOT_PLAN.md](PILOT_PLAN.md).

**Value -> system -> outcome -> dollar.**

| Step    | In CARES                                                                                                               | Example measure                                                                                                                                 |
| ------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Value   | A fast, fair, personal answer; better treatment for a clean record                                                     | Customer feels recognized                                                                                                                       |
| System  | Risk Detection (history), Stolen & Delayed (diagnosis), Refund (offer inside limits), Escalate (people for hard cases) | Actions run, offers made                                                                                                                        |
| Outcome | The customer orders again; fewer cases reach support                                                                   | Retention up, handled-by-person down                                                                                                            |
| Dollar  | Retained margin + saved support time - extra compensation - agent cost                                                 | `[$]` = (customers kept x orders per year x average order value x margin) + (cases not handled by a person x cost per case) - (cases CARES resolves x compensation above what a person would pay) - (conversations x agent cost). Base case ~US$1M a year for 1M orders a year |

Pronto has no real figures, so each input is a market benchmark or a team assumption `[$]`, with low, base and high values: see [MARKET_BENCHMARKS.md](MARKET_BENCHMARKS.md) and `metrics/data/value.json`. Compensation counts only what CARES pays above a person applying the same policy.

**Handoff to the internal customer.** When CARES escalates, the support team gets a case with a short summary, what was already offered, and the customer's priority. No customer has to repeat the story.

**Why a router with specialist subagents.** Each problem has different rules (diagnose vs pay vs hand off), so each gets a small subagent with its own limits. Money and identity rules stay in flows, not in the prompt.

## 2. Architecture

```
Customer -> Agent Router
              |-- Refund                   (built, not deployed)
              |-- Stolen & Delayed Orders  (built, not deployed) -> Refund
              |-- Risk Detection           (built, not deployed) -> Refund
              |-- Experience Rating        (built, not deployed)
              |-- Escalate to Human        (real: platform transfer)
              |-- Urgent Escalation        (branch: safety first -> Escalate, category URGENT)
              |-- Pronto Help              (branch: Pronto's customer rules from a Data Library)
              |-- Identify Customer        (real: email lookup when the chat has no contact, D-058)
              |-- Off Topic                (real: standard guardrails)
              |-- Ambiguous Question       (real: standard guardrails)
```

Design principle `DECIDED` (proposal from one member, adopted as the working rule): **the script decides whose data and whose money; the model writes the words.** Rules about money, identity and limits go into a Flow or Apex. Instruction text only shapes tone and wording, because instructions are not guarantees.

## 3. Subagents and status

| Subagent                       | Owner                | Status                                                                                                                          | Doc                                                                                                     |
| ------------------------------ | -------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Agent Router                   | `OPEN`               | Real, weak: no conditions, "best guess" when unclear                                                                            | n/a                                                                                                     |
| Refund                         | Refund owner         | Real tier and policy offer and audit row since PR #18; real orders and item values from Data Cloud since v5 (D-071, D-072). `apply_settlement` is still a stub. Tier and policy rows seeded (R-17 closed) | [node spec](subagents/refund.md)                                                                        |
| Stolen & Delayed Orders        | @rojasC10            | Built on branch (`feature/delivery-exceptions`), validated, not deployed                                                        | [design](subagents/stolen-delayed-orders.md)                                                            |
| Risk Detection                 | Risk Detection owner | Built on branch, validated, not deployed                                                                                        | [node spec](subagents/risk-detection-node-spec.md), [design](subagents/risk-detection.md)               |
| Experience Rating              | @ToroSF              | Built on branch (`feature/experience-rating-thumbs`), validated, not deployed. Thumbs up/down + model-generated summary (D-044) | [v1 baseline](subagents/experience-rating-v1.md), [changelog](subagents/experience-rating-changelog.md) |
| Escalate to Human | @Mateus-Goes | Built on `feature/escalation-handoff`, validated, not deployed: case number first, live transfer in real chats, fixed summary, bell and Slack alerts (D-083 to D-087) | [node spec](subagents/escalate-to-human.md), [demo](DEMO_ESCALATION.md) |
| Off Topic / Ambiguous Question | `OPEN`               | Real (template)                                                                                                                 | n/a                                                                                                     |
| Urgent Escalation              | Team (router)        | In `main` (PR #15), compiled and validated, not deployed. Sets category URGENT, goes to Escalate (D-061) | [POLICY_ALIGNMENT.md](POLICY_ALIGNMENT.md) POL-P13..P15                                                 |
| Pronto Help                    | @Mateus-Goes         | In `main` (PR #15), not deployed. Data Library READY in the team org (3 files indexed) and wired (D-067)                       | [node spec](subagents/pronto-help.md), [golden set](grounding/golden-set.md)                            |
| Identify Customer              | @lucasmpalomanes     | Merged (PR #16). Reached from Refund and Stolen & Delayed when `customer_id` is blank; unverified identity (G-065), not used by Risk Detection (G-076) | [DECISIONS.md](DECISIONS.md) D-058 |

Since PR #15, Escalate to Human passes a category (URGENT, PATTERN_REVIEW, CLAIM_REVIEW or general) to its Flow, which sets Type, Reason, Priority, Status and the `CARES_Escalations` queue and reuses an open case for the same order (D-063). Risk Detection sends a customer at or above the review threshold to a person before any offer (D-062). Official sources: [sources/](sources/) (D-059).

## 4. Variables today

| Variable                                     | Type    | Source                                                    |
| -------------------------------------------- | ------- | --------------------------------------------------------- |
| `EndUserId`, `RoutableId`, `EndUserLanguage` | linked  | Messaging session                                         |
| `ContactId`                                  | linked  | The contact of the messaging end user, set by the channel |
| `VerifiedCustomerId`                         | mutable | Nothing sets it yet                                       |

Rule `PROPOSAL`: the customer's identity comes only from `ContactId` (set by the channel) or a verification step, never from what the customer types. **Exception (D-058, demo):** when the channel gives no contact, the Identify Customer subagent looks the customer up by account email. That identity is unverified (G-065), so Risk Detection ignores it.

## 5. Data

The shared org has contacts and accounts, a few cases, no orders, no loyalty-tier field. Some reusable flows already exist (refund, remediation validation, verification code, case escalation). Read them before building new ones. See [GAPS.md](GAPS.md).

## 6. Cross-cutting rules `PROPOSAL`

1. Identity from the channel, not from chat.
2. Tier, order value and history come from records, not from what the customer says.
3. Amounts come from a calculate step; an apply step re-checks before writing.
4. Never tell the customer about internal assessments or limits.
5. If data is missing or an action fails: standard path or a person, never an invented answer.
6. Human help for: customer asks for a person, stuck after several turns, legal or fraud, safety.

## 7. Testing

Each subagent doc lists its tests: happy path, edge case, adversarial. Run them before the PR. After the merge, the whole agent is tested again before activation. `OPEN`: where the test suite lives.
