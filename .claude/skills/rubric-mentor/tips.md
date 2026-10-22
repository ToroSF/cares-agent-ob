# Tips for weak points

Give each tip as: **reread** (the artifact), **drill** (5-minute practice), **template** (sentence frame), **show** (evidence for the demo). Point to the member's own artifacts first. Keep each tip to a few lines.

## Use Case & Business Framing
- **Reread:** `SPEC.md` §1 (job story, KPIs), `MARKET_BENCHMARKS.md` (the value chain), `PANEL_QA.md` Q9.
- **Drill:** name one KPI for each executive (CFO cost per case, CRO retention, CIO admin effort…) and how your piece moves it.
- **Template:** "This matters because {problem} costs {KPI}; {artifact} changes it by {mechanism}, and the pilot measures it with {metric}."
- **Show:** the dashboard's value formula and its range, not just the headline figure.

## Configure
- **Reread:** your block in `CARES.agent`, `ARCHITECTURE_NOTES.md`, and your decisions with "what we gave up".
- **Drill:** draw your subagent in 4 boxes (in → checks → decision → out) and mark which boxes are code.
- **Template:** "We built {X} because {reason}; we did not use {Y} because {cost}. The script decides {money/identity}; the model writes the words."
- **Show:** one decision made in Apex with a unit test (for example `CARES_StolenDelayedTimingTest` boundaries).

## Ground
- **Reread:** `GROUNDING.md` (sources, audits, failure behavior), your data gaps.
- **Drill:** for each fact your subagent uses, say source → how checked → what happens if it's wrong.
- **Template:** "{Fact} comes from {source}; we checked it by {audit/test}; when it's missing we {fail-safe}."
- **Show:** one verification number (for example "on-time = 40 min explains 908 of 908 delivered orders").

## Risks & Safeguards
- **Reread:** `RISKS.md` ("Safeguard" and "Not caught" columns), your open gaps.
- **Drill:** pick your top 3 risks and finish "this prevents … but it does not catch …".
- **Template:** "{Safeguard} stops {failure}; it won't catch {limit}, so we {mitigation / person}."
- **Show:** a live case where the agent hands off to a person with a case number.

## Recommended Approach
- **Reread:** `TEST_PLAN.md` run log, your closed and open gaps.
- **Drill:** tell one failure story: found → cause → fix → re-test → result.
- **Template:** "We found {failure} in {test}; the cause was {root cause}; we fixed it with {change} and re-ran {test}: {result}. {Gap} is deferred because {reason}; it costs {impact}."
- **Show:** a gap row with a root cause, and the run row that proved the fix.

## Justification & Strategic Communication
- **Reread:** your rows in `DECISIONS.md`, your PR descriptions.
- **Drill:** explain one decision aloud to a non-technical friend in 30 seconds.
- **Template:** "We decided {X}. Why: {value}. We gave up {Y}, which is fine because {reason}."
- **Show:** the decision id on a slide, so the panel sees it's documented.

## Roleplay debrief extras
- **Lost the CFO:** lead with the number and the cap, then the range.
- **Lost the CTO:** lead with what fails safely and how you know.
- **Lost the CRO:** lead with the customer's experience, then the metric.
- **Lost the CIO:** lead with access, ownership and who maintains it.
- **Lost Innovation:** lead with the lesson and what you'd rebuild.
