# Pilot plan: KPI targets, Pronto baseline and go/no-go

How we would prove CARES with Pronto before a full rollout: the starting point (baseline), the target for each KPI, when to pause, and how to decide at the end. Decided in D-104.

**Pronto is fictional and has no data** (see [MARKET_BENCHMARKS.md](MARKET_BENCHMARKS.md)). So the baseline below is a **mock profile**, marked `[$]`. Each number comes from a public benchmark or from the business case inputs in [metrics/data/value.json](metrics/data/value.json), so the slides, the dashboard and this plan stay consistent. In a real engagement, the first pilot week replaces every `[$]` with Pronto's own numbers. The targets stay the same.

## 1. Pronto mock profile (before CARES)

| Input | Mock value `[$]` | Where it comes from |
|---|---|---|
| Orders a year | 1,000,000 | Business case base (`value.json`) |
| Orders with a problem | 24.4% (244,000) | Zion & Zion delivery study |
| Complaints that reach support | 50% of those: **122,000 a year, ~2,350 a week** | `complaintsPerYear` base |
| Cost of a case handled by a person | $7.80 | Deloitte Digital 2026 Contact Center Survey |
| Resolved without a person today | **0%** | Every complaint becomes a ticket after a generic auto-reply (the problem slide) |
| Time to an answer today | 3–5 business days | The generic reply in the brief's scenario |
| Average payout by a person | **$15.00** | Team assumption: same policy table as CARES, people round up and add goodwill |
| Reorder within 30 days, no complaint | **80%** | Team assumption for a regular (~64 orders a year, ~5 a month, DoorDash Q4 2025) |
| Reorder within 30 days, after a complaint | **72%** | 80% × (1 − 10% spend lost after a bad order, Uber field experiment, NBER w25676) |
| Thumbs up after a complaint today | **40%** | Team assumption for a slow ticket answer |

## 2. KPI targets

The four KPIs are the ones in [SPEC.md](SPEC.md). "Pause" means CARES traffic goes back to people the same day, we fix the problem, then resume.

| KPI | Type | Baseline `[$]` | Pilot target | Pause line | Why this target |
|---|---|---|---|---|---|
| Reorder within 30 days after a complaint | Headline | 72% | **≥ 74%** (+2 pts vs the control group) | CARES group below control | A complaint costs 8 points (80% → 72%). In the Uber experiment, a credit sent right away won back about 2 points of a 5–10 point loss. +2 points is that same 30% share (`retainedByCares` base) and is what the $362K "customers kept" line assumes |
| Payouts inside policy | Guardrail | Not measured today | **100%** of amounts from the policy table in code, human review above $100 on Stolen & Delayed, average **≤ $15** | Any single breach | The amount is computed in code (D-004), so the right number is 100%, not "most". Average at or under a person's keeps "extra compensation" at $0, as the business case assumes. With a ~5% margin, one wrong $90 refund erases ~58 orders of profit |
| Resolved without a person | Efficiency | 0% | **≥ 70%** | Under 50% for a full week | 70% is the business case base, 50% its cautious case. Under 50% the support saving falls below the low case |
| Thumbs up after resolution | Quality | 40% | **≥ 60%** | Under 40% two weeks in a row | +20 points: an instant fair answer should beat a 3–5 day ticket clearly. Under 40% CARES is worse than today, so we stop |

Two health checks support the KPIs. They are not KPIs.

| Check | Target | Pause line | Why |
|---|---|---|---|
| Escalated cases with summary, offer made and priority | 100% | Over 5% missing in a week | The support team is the internal customer. No customer should have to repeat the story |
| Conversations that hit a platform error | Under 1% | Over 2% in a day | We have seen an org-level throttle under load (G-090). The customer must never be left with "something went wrong" |

## 3. Pilot design

- **Scope:** web chat, late, stolen and missing order claims (what CARES handles today), all tiers.
- **Split by customer, not by conversation:** a hash of the Contact Id puts each customer in CARES or in control (today's process) for the whole pilot. A customer who complains twice stays in the same group, so the 30-day reorder comparison is clean.
- **Ramp:**
  - **Weeks 1–2 at 10% of customers.** Safety: guardrail and handoff checks every day. Pronto's real numbers replace the `[$]` baseline here.
  - **Weeks 3–8 at 50%.**
  - **Weeks 9–12:** no new customers in the pilot, only the 30-day follow-up for the headline KPI.
- **Size:** ~7,500 CARES complaints and ~11,250 control (2,350 a week). At a 72% reorder rate, the error on the difference is ~0.7 points, so a +2 point lift is ~3 standard errors: about an 85% chance of detecting it (5% significance, two-sided). A shorter or smaller pilot could not tell a real +2 from noise.
- **Read the guardrail, efficiency and quality KPIs every week.** Read retention from week 5, when the first customers have their full 30 days.

## 4. Decision at week 12

| Result | Decision |
|---|---|
| All four KPIs at target, no open pause | **Go:** scale to 100% in steps, keep a 10% control group to keep measuring retention |
| Guardrail, efficiency and quality at target; retention not below control but not +2 yet | **Go on the cost case:** scale, keep the 10% control. The support saving alone pays for CARES (section 5) |
| Efficiency 50–70% or thumbs up 40–60% | **Extend 4 weeks** at 50% with the fixes |
| A guardrail breach we could not fix, retention clearly below control, or efficiency under 50% after fixes | **Stop** and go back to design |

## 5. Financial metrics

| Metric | Value | How |
|---|---|---|
| Cost per conversation | **$0.50** vs **$7.80** for a person | Agentforce $0.10 per action × ~5 actions; Deloitte |
| Break-even share resolved without a person | **6.4%** | $0.50 ÷ $7.80. Above it, CARES pays for itself on support cost alone, even if retention does not move |
| Value per complaint | **~$7.90** | $967K ÷ 122,000 complaints (business case base) |
| Pilot agent cost | **~$3.8K** (up to ~$15K at $2 a conversation) | ~7,500 conversations × $0.50 |
| Pilot support saving | **~$41K** | 7,500 × 70% × $7.80 |
| Annual net value | **~$967K** (range $105K–$4.5M) | Business case, [SPEC.md](SPEC.md) |

## 6. If the panel asks

- **"These numbers aren't Pronto's."** Right. Pronto is fictional, so the baseline is a mock built from public benchmarks and labelled `[$]`. The plan doesn't depend on those numbers: the first two weeks measure Pronto's real ones, and the targets are relative (+2 points, ≥ 70%, ≤ a person's payout).
- **"Why +2 points and not +10?"** Because that is what a peer-reviewed field experiment on 1.5M Uber riders found for an immediate credit. Promising more would be a guess. The business case uses the same number.
- **"Why 8 weeks? Can't we go faster?"** Retention needs 30 days to show. With ~2,350 complaints a week, 8 weeks at 50% is the smallest pilot that can tell +2 points from noise. Guardrail and efficiency show in the first week, so that is where we can stop early.
- **"What if retention doesn't move?"** The support saving still pays: CARES breaks even at 6.4% resolved without a person, and the target is 70%. Retention is the upside, not the condition.
- **"Why 100% on payouts and not 99%?"** Because the model never sets the amount: policy in code does (D-004). Any breach is a bug, not a statistic, so a single one pauses the pilot.
- **"Why a control group? Just compare before and after."** Delivery has strong seasons and promotions. A control group measured over the same weeks removes them. Splitting by customer keeps people who complain twice in one group.
- **"What does the support team get?"** Every escalation arrives with a summary, the offer already made and the priority. That is a health check with its own pause line.

## 7. What is measured vs mocked

- **Measured in testing** (test traffic, not customers; see the dashboard, snapshot 2026-10-23 00:50 UTC): 65 of 65 payouts under $100 (57 refunds, 8 store credits), average $12.84, max $92.20; 87% resolved without a person (390 of 447 conversations); thumbs up 16 of 28; Testing Center v13 37 of 39; live run on v13 156 PASS of 170 scenarios. The Refund path has no $100 review line yet (G-135).
- **Public benchmark:** problem rate, cost per human case, margin, orders per customer, spend lost after a bad order.
- **Mock `[$]`:** order volume, the 50% that contact support, 80%/72% reorder, 40% thumbs up, $15 average human payout, 0% resolved without a person today.
