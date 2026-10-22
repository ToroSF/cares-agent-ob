# Market benchmarks for the CARES business case

Real market numbers to size the value of CARES. **Pronto is fictional and has no financials**, so the dollar figure on the metrics dashboard uses these benchmarks plus team assumptions marked `[$]` (D-065). None of it is a Pronto number.

- The inputs are in [metrics/data/value.json](metrics/data/value.json), with a low, base and high value each. The dashboard computes all three.
- The research was done on 2026-10-22, in two rounds (section 5). Every number used in the math was checked against its primary source.

## 1. Benchmarks

**Strength** of each source:
- **High:** primary source (filing, official page, peer-reviewed paper, press release).
- **Medium:** a paid report, a vendor-published primary, or a secondary that quotes a primary.
- **Low:** a blog or a vendor compilation.

**Checked:** the number was read on the source page on 2026-10-22. **Not checked:** the link was given but could not be opened, or no link was given.

### Market size (context only)

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| M1 | Online food delivery market, 2026 | **US$1.51T**, 6.24% CAGR to 2031, *including grocery* | [Statista Market Forecast](https://www.statista.com/outlook/emo/online-food-delivery/worldwide/) | High | Context only. Say: "a few hundred billion dollars, growing about 10% a year, depending on the definition" |
| M2 | Grocery vs. meals | ~US$1.04T is grocery; restaurant meals pass US$500B by 2030 | [Gourmetpix, quoting Statista](https://gourmetpix.com/blog/food-delivery-statistics) | Medium (aggregator) | Explains why the market estimates differ |
| M3 | Platform services only, 2026 | US$199B | [The Business Research Company](https://www.thebusinessresearchcompany.com/report/online-food-delivery-services-global-market-report) | Medium (paid report) | Same |
| M4 | Platform services only, 2026 | US$285B, 10.44% CAGR | [Precedence Research](https://www.precedenceresearch.com/online-food-delivery-market) | Medium (paid report) | Same. Do not quote US$326B as *the* number |

### Unit economics (filings)

DoorDash numbers come from **one quarter, Q4 2025**, because it is the only recent release that gives orders, GOV and MAUs for the same period. Q2 2026 is used only as a range check.

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| U1 | Orders per active user | 903M orders in Q4 2025 ÷ "over 56 million monthly active users" at year end = **~16 a quarter, ~5.4 a month, ~64 a year** (derived). **Checked** | [DoorDash Q4 and FY2025 results, 18 Feb 2026](https://ir.doordash.com/news/news-details/2026/DoorDash-Releases-Fourth-Quarter-and-Full-Year-2025-Financial-Results/default.aspx) | High (derived) | `ordersPerCustomerYear`. An upper bound: global, all categories (grocery, Wolt, Deliveroo), and MAU counts only active users |
| U2 | Average order value | Marketplace GOV US$29,683M ÷ 903M orders = **US$32.87** (Q4 2025, derived). Q2 2026: US$33,078M ÷ 970M = US$34.10. **Checked** | Q4 2025 release above; [DoorDash Q2 2026 release (SEC Ex. 99.1), 5 Aug 2026](https://www.sec.gov/Archives/edgar/data/1792789/000179278926000048/proddashex991-pressrelease.htm) | High (derived) | `avgOrderValue`. Global, all categories, not US restaurants only |
| U3 | Contribution profit, % of GOV | **4.7%** in Q4 2025 (5.1% in Q3 2025, 5.0% in Q2 2026). **Checked** | Same two releases (tables) | High | `margin` base. The whole contribution of an order is about 5% of its value |
| U4 | Adjusted EBITDA, % of GOV | 2.6% in Q4 2025, 2.8% in Q2 2026. **Checked** | Same | High | Context: profit after fixed costs is under 3% |
| U5 | Uber Delivery segment income, % of bookings | Delivery Gross Bookings US$27,463M, Delivery Segment Operating Income US$1,055M = **~3.8%** (Q2 2026, derived). Uber total Adjusted EBITDA: 4.9% of Gross Bookings. **Checked** | [Uber Q2 2026 results, 5 Aug 2026](https://investor.uber.com/news-events/news/press-release-details/2026/Uber-Announces-Results-for-Second-Quarter-2026/default.aspx) | High (derived) | `margin` low. A second company gives the same picture: 4–5% |
| U6 | Gross profit, % of GOV | 6.4% in Q4 2025 (GAAP). **Checked** | DoorDash Q4 2025 release (table) | High | Context only. It is **not** a refund rate: refunds are not shown separately |
| U7 | Marketing spend, % of GOV | GAAP sales and marketing: 2.4% of GOV in Q4 2025, 2.5% in Q2 2026 (US$821M in the quarter). **Checked** | Same two releases | High | The only CAC proxy in the filings. It mixes acquisition, retention and brand |

### Customer acquisition cost

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| A1 | CAC, food and beverage e-commerce | **US$30–80** per new customer. **Checked** | [DoorDash Merchants blog, 29 Sep 2026](https://merchants.doordash.com/en-us/blog/restaurant-customer-acquisition-cost), quoting Yotpo | Medium (secondary; restaurant CAC, not platform CAC) | Comparison 1: "refund vs. replacing the customer" |
| A2 | Paid ads, food and beverage | US$12.91 cost per action (Facebook, 2022) and US$26.58 cost per **lead** (Google, restaurants, 2022). **Checked** | Same blog, quoting WordStream | Low (old; the blog mixes CPA, CPL and CAC) | Do not use as CAC |

Platform CAC is **not disclosed** by DoorDash or Uber.

### Loyalty and reorder

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| L1 | Orders from repeat customers | **79%** of delivery orders come from customers who already ordered from that restaurant. **Checked** | [DoorDash, 2026 Restaurant Industry Trends Report](https://merchants.doordash.com/en-us/blog/restaurant-loyalty-programs) (DoorDash data from 50M+ monthly users and a survey of 3,001 US consumers) | High, but vendor-published | Most revenue is repeat business, so losing a regular costs more than one order |
| L2 | A credit brings customers back | **87%** say a credit, discount or perk influenced them to order again from the same restaurant in the past 6 months. **Checked** | Same report | High, but vendor-published | Proof that a credit works as a retention tool. **Not** a service-recovery rate (any perk, restaurant level), so it is not `retainedByCares` |
| L3 | App loyalty | **73%** stay with the same delivery app | [DoorDash Merchants, quoting a 2026 report](https://merchants.doordash.com/en-us/blog/online-food-delivery-services-market-growth) | Medium (secondary) | Switching is easy, but most people settle on one app |
| L4 | App loyalty, split | 31% loyal to one app, 50% usually the same app, 19% switch | [Intouch Insight via Restaurant Business](https://www.restaurantbusinessonline.com/technology/which-restaurant-delivery-app-best-consumers-weigh) (page returned 403 on 2026-10-22) | High | Different survey from L3: quote one or the other, do not combine them |

### Failure rate, churn and service recovery

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| F1 | Orders with a problem | **24.4%** on average (missing or wrong items, temperature, very late) | [Zion & Zion study (PDF)](https://www.zionandzion.com/download/research/RestaurantsOrDeliveryAppCompanies.pdf); [Restaurant Business coverage](https://www.restaurantbusinessonline.com/topics/nearly-25-third-party-deliveries-disappoint-study-finds) | Medium (older, no clear date) | Sizes complaint volume: about 1 order in 4. A problem rate, not a support-contact rate |
| F2 | Late against the estimate (mystery shopper, 600 orders) | Uber Eats 48%, DoorDash 42%, Grubhub 35%. Satisfaction 87% (2022) → 91% (2024). **Not checked** (403) | [Intouch Insight via Restaurant Business](https://www.restaurantbusinessonline.com/technology/which-restaurant-delivery-app-best-consumers-weigh) | High if confirmed | Newer replacement for F1, for the *Delayed* outcome. Confirm on the page before quoting |
| F3 | Temperature and satisfaction | 49% more satisfied when the food arrives at the right temperature | Same | High | Matches CARES's `Quality_Issue` outcome. Optional |
| F4 | Switch after **one** bad experience | **63%**, up 9% year on year. **Checked** | [Zendesk CX Trends 2025](https://www.zendesk.com/newsroom/articles/2025-cx-trends-report/) (Nov 2024, ~10,500 respondents, 22 countries) | High (cite Zendesk) | Stated intention, not measured churn: the **upper bound** for `churnAfterBadOrder` |
| F5 | Switch after **several** bad experiences | 73% | [Zendesk customer service statistics](https://www.zendesk.com/blog/customer-service-statistics/) (undated) | Medium | Explains the misquoted "73% after one bad experience" if asked |
| R1 | **Measured** loss after a bad experience ⭐ | Without an apology, a rider whose trip was late "spends 5-10% less on the platform relative to a counterfactual rider". Field experiment, **1.5 million** US Uber riders; "late" meant about the 5% latest trips. **Checked** (paper p. 3) | [Halperin, Ho, List & Muir, NBER w25676 (2019)](https://www.nber.org/papers/w25676); [*The Economic Journal* 132(641), 2022](https://academic.oup.com/ej/article-abstract/132/641/273/6325164) | High (peer reviewed) | `churnAfterBadOrder` base, as a spend-equivalent loss. Ridesharing, not food delivery, but the same company and the same failure type (late) |
| R2 | A coupon recovers part of it ⭐ | A US$5 coupon right after the late trip "increases future demand". The first apology with the coupon gave "a 2% increase in net spending", and the benefit is measured **net of the coupon cost**. Words alone "had little effect or was even sometimes counterproductive". **Checked** (pp. 3–4, 25) | Same paper | High | `retainedByCares`: a 2-point gain against a 5–10-point loss means **~20–40% of the loss recovered** |
| R3 | Timing matters ⭐ | The same US$5 coupon sent at a random time had "a significantly negative effect of -8.3%" on net spending at 7 days; sent right after the bad trip it worked. **Checked** (p. 28) | Same paper | High | Supports resolving **inside the conversation**, not later by email |
| R4 | Repeat apologies backfire ⭐ | "apologizing repeatedly to the same person who had multiple bad experiences in a three-month period actually reduced future spending". The third apology with a coupon had "a significantly negative effect". **Checked** (pp. 25, 30) | Same paper | High | Supports Risk Detection's history check and limits on repeat compensation |
| R5 | Coupons work less for experienced users | The coupon effect was "highest for the newest quartile of users (those with 0 to 10 lifetime trips) and lowest for the most experienced users (those with greater than 157 trips)", but "the confidence intervals are wide". **Checked** (p. 24) | Same paper | High (weak result) | **The strongest counter-argument to our tiers.** See section 4 |
| R6 | Replicated at Via | A US$5 promo after a bad ride increased net spending; a random US$5 promo and a cheap apology had no significant effect. **Checked** (as reported in the Uber paper, p. 29) | Cohen et al. (2018), cited in the paper above | Medium (not opened) | A second company with the same result |

### Agent cost (consumption objection)

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| P1 | Flex Credits | "$ 500 USD/Per 100k Credits"; "Agentforce actions are 20 Flex Credits, while Agentforce Voice actions are 30 Flex Credits" = **US$0.10 per action**. Unused credits do not roll over. **Checked** | [Salesforce Agentforce pricing](https://www.salesforce.com/agentforce/pricing/) | High (official) | Base cost per CARES conversation: ~5 actions = **~US$0.50** (estimate; check the org's consumption) |
| P2 | Conversations | "$ 2 USD/Per conversation", "optimized for external facing customer agents". "Flex Credits and Conversations will not be supported in the same org". **Checked** | Same page | High (official) | High case for the agent cost |
| P3 | Help Agent resolutions | Listed at "$ 2" per resolution; the page gives no more detail. **Checked** | Same page | High (official, unclear scope) | Do not use unless asked |

### Support costs and AI return

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| S1 | Cost per contact | Median **US$1.84** self-service vs. **US$13.50** assisted | [Gartner, 2024 document](https://www.gartner.com/en/documents/5164231) (paywalled) | High | High end of `costPerHumanCase` |
| S2 | Cost per assisted contact | **US$7.80** in 2026, up from US$6.70 in 2024. **Checked** | [Deloitte Digital, 2026 Global Contact Center Survey (PDF)](https://www.deloittedigital.com/content/dam/digital/global/documents/insights-20260603-global-contact-center-survey.pdf) (June 2026, 720 B2C service leaders, p. 8) | High | Base for `costPerHumanCase` |
| S3 | Gen AI cost per resolution | Will exceed **US$3** by 2030, "higher than many B2C offshore human agents". Leaders will look past cost cutting toward "customer lifetime value, repurchase rate and brand loyalty". **Checked** | [Gartner press release, 26 Jan 2026](https://www.gartner.com/en/newsroom/press-releases/2026-01-26-gartner-predicts-genai-cost-per-resolution-for-customer-service-will-exceed-offshore-human-agent-costs-by-2030) | High (primary) | CARES is justified by protecting revenue, not by cutting support cost |
| S4 | Few teams show AI ROI | Only **24%** of service leaders showed positive financial returns from AI, after investing a median 12% of the 2025 budget. **Checked** | [Gartner press release, 8 Jul 2026](https://www.gartner.com/en/newsroom/press-releases/2026-07-08-gartner-survey-finds-customers-are-three-times-more-likely-to-use-third-party-genai-than-company-provided-chatbots-for-customer-service) (1,303 senior leaders, Jan–Apr 2026) | High (primary) | We anticipate the ROI objection by saying how we would measure the return |

### Competitive positioning

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| C1 | DoorDash: gen AI voice support for Dashers | "hundreds of thousands" of support calls a day, response latency "2.5 seconds or less", built on Claude 3 Haiku in Amazon Bedrock; "DoorDash does not provide any personally identifiable information to be accessed via these generative AI solutions". The earlier IVR (Amazon Lex, **not** gen AI) "reduced DoorDash's agent transfers by 49 percent", with "a 12 percent increase in first contact resolution" and "$3M in YoY operational cost savings". **Checked** | [AWS case study](https://aws.amazon.com/solutions/case-studies/doordash-bedrock-case-study/) (undated; testing in early 2024) | High (vendor case study) | Market leaders automate support at scale, and keep PII away from the model. Do not credit the 49% / US$3M to gen AI |
| C2 | Uber: rules execute the procedure | Policy Engine "allows for automated execution of SOPs across all channels", and "every action against a policy will have to be logged". **Checked** (the post does not say "deterministic") | [Uber engineering blog, 14 Jul 2021](https://www.uber.com/us/en/blog/customer-automation-platform/) | High (primary, older) | **Same pattern as CARES:** policy runs in code and is logged; the model handles the language |
| C3 | Uber: gen AI on top | Gen AI summarises conversations, automates investigations, suggests empathetic replies. **Not checked** | [OpenAI customer story](https://openai.com/index/uber-enables-outstanding-experiences/) | Medium (vendor story) | Optional, after C2 |
| C4 | DoorDash Quality Guarantee | DoorDash can deny a refund or credit if it suspects fraud or abuse. **Not checked** | [DoorDash Help: Quality Guarantee terms](https://help.doordash.com/en-us/consumers/article/terms-of-the-quality-guarantee) | High (official) if confirmed | Market practice for Risk Detection: abuse checks before paying |

Instacart: no primary source was found, so do not cite it.

### Mexico (optional, context only)

| # | Benchmark | Value | Source | Strength | How we use it |
|---|---|---|---|---|---|
| X1 | Share in Mexico, by active users, 2024 | DiDi Food 38%, Rappi 36% | [Sensor Tower](https://sensortower.com/blog/fragmented-lat-am-food-delivery-market-evolves-amidst-ubers-exit) | High | Only if the panel asks about LATAM |
| X2 | Share in Mexico, by orders, 2026 | Uber Eats 42%, Rappi 31%, DiDi 18% | [Consultancy blog citing AMVO and Statista](https://restaurantecercademi.co/EN/selling-on-uber-eats-rappi-didi-2026-data-margins.html) | Low | Avoid, or say "sources disagree" |
| X3 | Restaurant commission in Mexico | 27% to 35% of the subtotal | Same blog | Low | Avoid. It is a take rate, not a margin |

### Gaps (no public primary source)

- **Share of problem orders that contact support.** Not disclosed. It stays a labelled assumption.
- **Refunds and credits as % of GOV.** Not disclosed: refunds sit inside revenue and cost of revenue.
- **Platform CAC.** Not disclosed. U7 and A1 are proxies.
- **Store credit redemption rate.** No source, not even a secondary one.
- **Refund abuse in food delivery.** No checked source. See section 5 for what was dropped.

## 2. The `value.json` inputs

Units follow `value.json`: percentages are fractions. **B** = benchmark, **A** = team assumption `[$]`.

| Input | Low | Base | High | Basis |
|---|---|---|---|---|
| Pronto orders per year | 1,000,000 | 1,000,000 | 1,000,000 | **A**: a mid-size regional marketplace; it only scales the result |
| × problem rate | 0.244 | 0.244 | 0.244 | **B** F1 |
| × share that contacts support | 0.25 | 0.50 | 0.75 | **A** (gap) |
| = `complaintsPerYear` | **61,000** | **122,000** | **183,000** | Derived |
| `churnAfterBadOrder` | 0.05 | **0.10** | 0.30 | **B** R1 (5–10% spend loss) for low and base; high is between R1 and the 63% stated intention (F4) |
| `retainedByCares` | 0.20 | **0.30** | 0.40 | **B** R2: 2 points recovered of a 5–10-point loss |
| `ordersPerCustomerYear` | 32 | **64** | 64 | **B** U1 for base; low is half (**A**), because U1 is global and all categories |
| `avgOrderValue` | 30.00 | **32.87** | 34.10 | **B** U2 (Q4 2025 base, Q2 2026 high); low is **A** |
| `margin` | 0.038 | **0.047** | 0.050 | **B** U5, U3, U3 (Q2 2026) |
| `costPerHumanCase` | 6.70 | **7.80** | 13.50 | **B** S2 (2024), S2 (2026), S1 |
| `resolvedWithoutPerson` | 0.50 | **0.70** | 0.90 | **A**. High is our test traffic (90.6% on v5), which is not real customers |
| `extraCompensationPerCase` | 0 | **0** | 0 | **A**: same caps as a person. Risk Detection should make it negative once measured |
| Average refund or credit (3.1 and 3.4 only) | 35.00 | **20.00** | 11.68 | **A**. High is our measured test average; low is the Explorer clean cap |
| `agentCostPerConversation` | 2.00 | **0.50** | 0.40 | **B** P2, and P1 at ~5 or ~4 actions |

Margin kept per retained customer per year = orders × AOV × margin = **US$98.87** (base).

## 3. The dollar math, worked out

### 3.1 Why the first formula was replaced

The first dashboard formula was `retained margin + support saved − all compensation paid`, and its base case is negative. That formula charged CARES for every refund, as if Pronto paid nothing without the agent. It does not hold up: a human agent applies the same policy and pays the same refunds. In a 4–5% margin business, a full refund never pays back from one year of margin.

| Term (US$ per year) | Low | Base | High |
|---|---|---|---|
| Customers kept | 610 | 3,660 | 21,960 |
| Retained margin | 22K | 362K | 2,396K |
| Support saved | 204K | 666K | 2,223K |
| − Compensation paid | −1,068K | −1,708K | −1,924K |
| **Total** | **−841K** | **−680K** | **+2,696K** |

### 3.2 The formula the dashboard uses

`retained margin + support saved − incremental compensation − agent cost`

- **Incremental compensation** = what CARES pays − what the human process would pay. With the same caps it is about **0**. Risk Detection makes it negative: abuse-pattern claims are not paid at the full cap, so CARES pays less. It stays 0 here until we measure it.
- **Agent cost** = complaints × cost per conversation. Every complaint goes through CARES, including the ones it escalates.

| Term (US$ per year) | Low | Base | High |
|---|---|---|---|
| Retained margin | 22K | 362K | 2,396K |
| Support saved | 204K | 666K | 2,223K |
| − Incremental compensation | 0 | 0 | 0 |
| − Agent cost | −122K | −61K | −73K |
| **Total** | **+105K** | **+967K** | **+4,547K** |

**Base: ~US$1M a year** for a marketplace with 1M orders a year. About two thirds is support time saved and one third is margin kept.

### 3.3 Sensitivity (base case)

- **Linear in volume:** `complaintsPerYear` (orders, problem rate, contact share) scales every term.
- **Retention term:** linear in churn, kept share, frequency, AOV and margin. Raising churn from 0.10 to 0.30 alone adds ~US$724K.
- **Support term:** most exposed to the share resolved without a person. At 0.50 it falls from US$666K to ~US$476K.
- **Agent cost:** small either way. Even at US$2 a conversation it is US$244K, a quarter of the base total.

### 3.4 Break-even for a refund (comparison 1)

How many complainers a refund has to keep, if it were paid *only* to keep them:

| Refund | Customers kept per 100 complaints, 1-year margin | 3-year margin |
|---|---|---|
| US$5 (Uber coupon) | 5.1 | 1.7 |
| US$11.68 (our test average) | 11.8 | 3.9 |
| US$20 | 20.2 | 6.7 |
| US$35 (Explorer clean cap) | 35.4 | 11.8 |

**Takeaway:** on margin alone, large refunds do not pay for themselves. That is why the refund is owed for the failed order (the policy), CARES keeps it inside the cap, and the business case rests on speed, the right amount for the right customer, and support time. Replacing a lost customer costs US$30–80 (A1), several times the average refund.

## 4. Counter-arguments to raise ourselves (rubric L4)

1. **"Refunds just give money away."**
   - The refund is owed for a failed order; any support process pays it.
   - What CARES changes is three things:
     - **Speed:** R3, timing matters.
     - **Fit to the policy and the customer's record:** caps in Apex.
     - **Not paying abuse patterns:** Risk Detection, R4, C4.
   - Margin is 4–5% of an order (U3, U5). So the cap lives in code, not in the prompt.
2. **The tiers may be backwards.** In the Uber experiment, the coupon worked best for new users and least for the most experienced (R5, wide confidence intervals). CARES gives Pronto Plus the highest caps.
   - **Answer:** the tier cap is a *ceiling*, not the amount paid.
   - For loyal customers, the speed and the recognition of their record matter as much as the money.
   - This is a test we would run in production: compensation vs. reorder, by tier.
3. **"Your 90% is test traffic."** True. The base case uses 70%, and the low case 50%.
4. **Consumption.** About US$0.50 a conversation with Flex Credits (P1), or US$2 with Conversations (P2). That is under a tenth of a human contact (S2).
   - Gartner expects gen AI cost per resolution to pass US$3 (S3). So the expensive decisions do not depend on the model: risk, caps and the amount run in Flows and Apex.
5. **ROI.** Only 24% of service leaders show AI ROI (S4).
   - We show the formula, the benchmark behind each input, and what we would measure: reorder within 30 days, CARES vs. a control group.

## 5. Research log (2026-10-22)

Two research rounds (one with Gemini, one with Claude) were consolidated. Where both covered the same item, one was chosen:

| Item | Gemini | Claude | Chosen, and why |
|---|---|---|---|
| Orders per user | Q4 2025: 903M ÷ 56M MAU ≈ 16.1 a quarter | Q2 2026: 970M ÷ 56M MAU ≈ 5.8 a month (max) | **Gemini.** The MAU count is from the end of 2025, so Q4 2025 orders match it; Q2 2026 mixes periods |
| AOV | Q4 2025 US$32.87, Q3 2025 US$32.23 | Q2 2026 ~US$34 | **Gemini (Q4 2025)** to stay on the same quarter as U1; Q2 2026 kept as the high value |
| Margin | Contribution 4.7% (Q4 2025); Uber take rate 19.6% | Contribution 5.0% (Q2 2026); Uber Delivery ~4% | **4.7% base** (same quarter), Claude's Uber number for low. The 19.6% take rate was dropped: it is revenue, not margin |
| Contact rate and churn | Zion & Zion 24.4%; "WISMO" with no source | Gap declared; Uber field experiment | **Claude** for churn and recovery (R1–R6). Zion & Zion kept for the problem rate |
| Service recovery | "Yale School of Management, July 2026, citing Bain" with no link | Uber and Via experiments | **Claude.** The Gemini claim has no link and could not be found |
| CAC | DoorDash blog, US$30–80 | Same blog plus S&M 2.4% of GOV | **Both**: same source; Claude's proxy added as U7 |
| Refunds % of GOV | Gross profit 6.4% of GOV | Not disclosed; Quality Guarantee policy | **Claude:** declared a gap. 6.4% kept as context (U6), not as a refund rate |
| Agentforce pricing | US$2 per conversation and US$0.10 per action | Same, plus rules and the Help Agent resolution price | **Claude** (more complete), checked on the official page |
| Competitive positioning | Uber sentiment "early warning"; DoorDash summaries; MindBlaze | DoorDash AWS case, Uber Policy Engine | **Claude:** primary sources. The Gemini items had no links |
| Problem rate, newer | none | Mystery shopper: late 48/42/35% | Kept as F2, **not checked** (page 403) |
| Refund fraud | Cyjax "Refund Fraud as a Service"; Chargeflow 34.7% "Item Not Received" chargebacks | 52% UK / 45% US self-reported abuse; US$28B, 7% of returns cost | **None used.** No links, e-commerce rather than delivery, and "released today" claims could not be verified. Find primary sources before quoting |

Corrections made while checking:
- **Contribution 5.0% (Q2 2026)** came from a call transcript in the Claude answer. It is also in the release table, so it is confirmed.
- **The DoorDash 49% / 12% / US$3M** results belong to the earlier Amazon Lex IVR, not to gen AI.
- **The Uber blog** never uses the word "deterministic". It says "automated execution of SOPs", and that every policy action is logged.
- **The Claude answer said "Gold" customers.** CARES tiers are Explorer, Insider and Pronto Plus.
- **The Google Ads US$26.58** is a cost per lead, not a CAC.

## 6. The 30-second narrative

> "In food delivery, most orders come from repeat customers, and the whole margin of an order is about 5% of its value. About one order in four has a problem. When Uber measured it on 1.5 million riders, a late trip cut future spending by 5 to 10 percent, and a small credit sent right away won part of it back, even after paying for the credit. Words alone did not. So CARES resolves inside the conversation, keeps the amount inside a cap written in code, and checks the customer's history so we do not keep paying the same pattern. For a marketplace with a million orders a year, that is about one million dollars a year, mostly support time saved and customers kept, at about fifty cents a conversation."

What not to say:
- **"We only use the model on the high-value path" was removed.** In CARES every conversation goes through the LLM. The true claim is that the model never decides the money or the identity.
- **The 87% is said as "a credit or perk brought them back",** not "a credit recovers a complaint". R2 is now the recovery evidence.
- **"US$1M" is an assumption-based estimate,** not a Pronto number. Say "for a marketplace with a million orders a year".

## 7. Next steps

1. **Confirm F2 and C4 on the page** before citing them.
2. **Replace assumptions with measurements in production:**
   - the share of problem orders that contact support;
   - the share resolved without a person, on real traffic;
   - incremental compensation: CARES vs. a control group handled by people;
   - reorder within 30 days after a case, CARES vs. a baseline (the headline KPI).
3. **Measure the agent cost** per conversation from the org's consumption, in place of the ~5-action estimate.
