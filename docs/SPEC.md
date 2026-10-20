# CARES spec

Status date: 2026-10-19. Source: the `CARES` authoring bundle in this repo (identical to the version in the shared team org on this date).

## 1. Use case and business framing

Status: `PROPOSAL` (draft for the team to edit). Numbers marked `[$]` need Pronto data; do not invent them.

**Context.** Pronto is a food delivery marketplace. Switching to another app costs the customer nothing, so how we handle a bad order matters as much as price.

**Internal customer.** The Pronto customer support team. They receive the cases CARES cannot or should not close, and they pay the cost of every refund. Executive leadership judges success on retention.

**Customer challenge.** A customer whose order was stolen or late gets a slow, generic answer. A loyal customer with a clean history is treated like anyone else, or a fraud-prone claim is paid without a check. Either way Pronto loses money or the customer.

**Job Story (support POV).**

> When a customer contacts Pronto because an order was stolen or arrived late, I want the agent to check the order and the customer's recent history and then resolve it right away with a refund or credit that fits the policy and the customer's record, so that the customer feels looked after and keeps ordering with Pronto instead of switching apps, and my team only sees the cases that really need a person.

**KPIs.**

| KPI                                                                                   | Type       | How to measure                                           |
| ------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------- |
| Customer retention after a complaint (for example orders in the 30 days after a case) | Headline   | Compare customers served by CARES with a baseline `[$]`  |
| Compensation cost per case vs policy                                                  | Guardrail  | Total credit and refunds / cases, against the policy cap |
| Share of cases solved without a person                                                | Efficiency | Cases closed by CARES / all CARES cases                  |
| Customer rating after resolution                                                      | Quality    | Experience Rating score                                  |

**Value -> system -> outcome -> dollar.**

| Step    | In CARES                                                                                                               | Example measure                                                                                                                                 |
| ------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Value   | A fast, fair, personal answer; better treatment for a clean record                                                     | Customer feels recognized                                                                                                                       |
| System  | Risk Detection (history), Stolen & Delayed (diagnosis), Refund (offer inside limits), Escalate (people for hard cases) | Actions run, offers made                                                                                                                        |
| Outcome | The customer orders again; fewer cases reach support                                                                   | Retention up, handled-by-person down                                                                                                            |
| Dollar  | Retained margin + saved support time - compensation cost                                                               | `[$]` = (customers kept x orders per year x average order value x margin) + (cases not handled by a person x cost per case) - compensation paid |

Inputs we still need from Pronto `[$]`: average order value, orders per customer per year, margin, the share of customers who leave after a bad order, cost per support case.

**Handoff to the internal customer.** When CARES escalates, the support team gets a case with a short summary, what was already offered, and the customer's priority. No customer has to repeat the story.

**Why a router with specialist subagents.** Each problem has different rules (diagnose vs pay vs hand off), so each gets a small subagent with its own limits. Money and identity rules stay in flows, not in the prompt.

## 2. Architecture

```
Customer -> Agent Router
              |-- Refund                   (placeholder)
              |-- Stolen & Delayed Orders  (placeholder) -> Refund
              |-- Risk Detection           (placeholder) -> Refund
              |-- Experience Rating        (placeholder)
              |-- Escalate to Human        (real: platform transfer)
              |-- Urgent Escalation        (branch: safety first -> Escalate, category URGENT)
              |-- Pronto Help              (branch: Pronto's customer rules from a Data Library)
              |-- Off Topic                (real: standard guardrails)
              |-- Ambiguous Question       (real: standard guardrails)
```

Design principle `DECIDED` (proposal from one member, adopted as the working rule): **the script decides whose data and whose money; the model writes the words.** Rules about money, identity and limits go into a Flow or Apex. Instruction text only shapes tone and wording, because instructions are not guarantees.

## 3. Subagents and status

| Subagent                       | Owner                | Status                                                                                                                          | Doc                                                                                                     |
| ------------------------------ | -------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Agent Router                   | `OPEN`               | Real, weak: no conditions, "best guess" when unclear                                                                            | n/a                                                                                                     |
| Refund                         | Refund owner         | Built with stub actions on branch, validated, not deployed                                                                      | [node spec](subagents/refund.md)                                                                        |
| Stolen & Delayed Orders        | `OPEN`               | Placeholder                                                                                                                     | to add                                                                                                  |
| Risk Detection                 | Risk Detection owner | Built on branch, validated, not deployed                                                                                        | [node spec](subagents/risk-detection-node-spec.md), [design](subagents/risk-detection.md)               |
| Experience Rating              | @ToroSF              | Built on branch (`feature/experience-rating-thumbs`), validated, not deployed. Thumbs up/down + model-generated summary (D-044) | [v1 baseline](subagents/experience-rating-v1.md), [changelog](subagents/experience-rating-changelog.md) |
| Escalate to Human              | `OPEN`               | Real (needs Omni-Channel check)                                                                                                 | to add                                                                                                  |
| Off Topic / Ambiguous Question | `OPEN`               | Real (template)                                                                                                                 | n/a                                                                                                     |
| Urgent Escalation              | Team (router)        | Built on `feature/grounding-policy-alignment`, compiled locally, not deployed. Sets category URGENT, goes to Escalate (D-047)   | [POLICY_ALIGNMENT.md](POLICY_ALIGNMENT.md) POL-P13..P15                                                 |
| Pronto Help                    | @Mateus-Goes         | Built on the same branch, not deployed. Data Library created in the team org and wired (D-053); indexing check in G-056       | [node spec](subagents/pronto-help.md), [golden set](grounding/golden-set.md)                            |

On the same branch, Escalate to Human passes a category (URGENT, PATTERN_REVIEW, CLAIM_REVIEW or general) to its Flow, which sets Type, Reason, Priority, Status and the `CARES_Escalations` queue and reuses an open case for the same order (D-049). Risk Detection sends a customer at or above the review threshold to a person before any offer (D-048). Official sources: [sources/](sources/) (D-045).

## 4. Variables today

| Variable                                     | Type    | Source                                                    |
| -------------------------------------------- | ------- | --------------------------------------------------------- |
| `EndUserId`, `RoutableId`, `EndUserLanguage` | linked  | Messaging session                                         |
| `ContactId`                                  | linked  | The contact of the messaging end user, set by the channel |
| `VerifiedCustomerId`                         | mutable | Nothing sets it yet                                       |

Rule `PROPOSAL`: the customer's identity comes only from `ContactId` (set by the channel) or a verification step, never from what the customer types.

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
