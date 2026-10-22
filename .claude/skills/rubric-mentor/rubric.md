# The Capstone rubric, as the mentor scores it

Six lines, four levels: **1 Beginning · 2 Developing · 3 Practicing · 4 Advanced**.

Two sources, two jobs:
- **Repo evidence** (`scripts/collect_evidence.py`) shows what the member *built and wrote down*. It can reach **Practicing** at most.
- **Answers** (in `review` or `roleplay`) show whether the member can *explain it to an executive*. Only answers can lift a line to **Advanced**, and a weak answer can lower a line below its repo level: the rubric scores the presentation, not the commit history.

Score on quality, not volume. Squash merges by the repo owner and AI co-authored commits make commit counts misleading. Use them as context only.

## The six lines

### 1. Use Case & Business Framing
*Was a real business challenge identified and connected to KPIs stakeholders care about?*
- **Beginning:** describes the feature, not the problem.
- **Developing:** names the problem (late or stolen orders cost customers), but no KPI.
- **Practicing:** ties the work to a KPI (retention, cost per case, resolved without a person, CSAT) with the team's value model (`MARKET_BENCHMARKS.md`).
- **Advanced:** says which executive cares about which KPI, and how a pilot would measure it, in two sentences.
- **Repo signals:** `SPEC.md` §1, `MARKET_BENCHMARKS.md`, `metrics/data/value.json`, `PANEL_QA.md` Q1/Q9, decisions that mention KPI, cost or retention.

### 2. Configure
*Is the agent functional, and can you explain the design choices behind how you structured it?*
- **Beginning:** "it works", no structure explained.
- **Developing:** explains what the subagent does.
- **Practicing:** explains why it is built that way (script decides, model writes: D-004), with tests behind it.
- **Advanced:** names the alternative they rejected and what it would have cost.
- **Repo signals:** their `CARES.agent` block, Apex/Flows, structural decisions with "why" and "what we gave up", unit tests.

### 3. Ground
*Is the agent pulling from the right data sources, and can you explain how you verified it?*
- **Beginning:** "it uses Salesforce data".
- **Developing:** names the source (Data Cloud `Order__dlm`, the policy PDFs).
- **Practicing:** shows how it was checked (row audits in `GROUNDING.md`, the golden set, a test).
- **Advanced:** gives one concrete verification and one data limit honestly (for example the 908/908 on-time match, or that only open orders have an estimate).
- **Repo signals:** `GROUNDING.md`, data-access code, data gaps they own, passing test runs.

### 4. Risks & Safeguards
*Do your guardrails cover specific risks, and can you explain what each one is designed to prevent?*
- **Beginning:** generic ("we have guardrails").
- **Developing:** lists safeguards.
- **Practicing:** maps each safeguard to the failure it prevents.
- **Advanced:** also says what each safeguard does *not* catch (the "Not caught" column of `RISKS.md`).
- **Repo signals:** gaps with impact and status, risks with "not caught" filled, guardrail code.

### 5. Recommended Approach
*Were solutions to failures validated? Were deferred failures diagnosed and explained?*
- **Beginning:** no test evidence.
- **Developing:** tests exist.
- **Practicing:** failures found, fixed, and re-tested (closed gaps with a run row).
- **Advanced:** explains why a failure was deferred and what it costs to leave it, with the next step.
- **Repo signals:** `TEST_PLAN.md` run rows, closed gaps, open gaps with a reason.

### 6. Justification & Strategic Communication
*Were design and decisions explained clearly and tied back to business value?*
- **Beginning:** decisions not written down.
- **Developing:** decisions written, without the reason.
- **Practicing:** decision rows with "why" and "what we gave up"; PRs that explain why and how it was tested.
- **Advanced:** explains a decision to a non-technical executive in two sentences, tied to value.
- **Repo signals:** `DECISIONS.md` rows they own, PR descriptions, `PANEL_QA.md` answers.

## How an answer is judged (`review`, `roleplay`)
Four checks per answer, each yes/no:
1. **Clear:** two or three sentences, no jargon the role wouldn't use.
2. **Value:** ties back to a KPI or a cost.
3. **Trade-off:** names what was given up or what isn't covered.
4. **Evidence:** points to something checkable (a number, a test, a decision id).

How the four checks move the score:
- **4 of 4** moves the line up one level, and is the only way to reach Advanced.
- **2 or 3 of 4** keeps the repo level.
- **0 or 1 of 4** moves it down one level, but never below Developing if the repo shows the work.
