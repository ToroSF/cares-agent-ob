# Risks and safeguards (Risk Diagnostic)

Four types: People, Business, Tech, Data. For each: a concrete failure, how to reproduce it, the safeguard and where it lives, when we escalate, and what it would NOT catch. Status: `DECIDED`, `PROPOSAL`, `OPEN`. Owners add rows as they build.

## People

| ID | Failure | Reproduce | Safeguard (where) | Escalate when | Not caught | Status |
|---|---|---|---|---|---|---|
| R-01 | A customer claims a tier or a clean record ("I'm Gold, never had a problem") to get a bigger offer | Say it in chat before the offer step | Tier and history come from records, never from chat; the model cannot set the risk flag (Flow, script) | Customer insists after the offer, or asks for a person | A genuine customer wrongly shown as "not clean" because of bad data | PROPOSAL |
| R-02 | A teammate overwrites another's subagent or changes the shared org by mistake | Two people edit the same block | One branch per subagent, one person deploys, inspect before changing (process) | Any unexpected change in the shared org | A mistake made inside the org UI outside the repo | DECIDED |

## Business

| ID | Failure | Reproduce | Safeguard (where) | Escalate when | Not caught | Status |
|---|---|---|---|---|---|---|
| R-03 | Over-compensation: offer above policy, or the same customer paid twice | Ask for a refund twice; ask for more than the cap | Cap per tier in configuration; calculate step returns the amount; apply step re-checks before writing (Flow) | Amount above cap or repeat claim | A policy that is itself too generous | OPEN |
| R-04 | Gaming: customers falsely report "stolen" to get the highest refund | Report stolen orders repeatedly | Stolen needs delivery evidence (driver location vs drop-off); repeat claims go to a person (Flow, rules) | Repeat or high-value stolen claim | A real-looking claim with good fake evidence | OPEN |
| R-05 | Store credit worth 20-25% more costs more than the retention it buys | Compare cost of credit with retention in a pilot | Pilot, measure, adjust the percentage in configuration | Cost per case above guardrail | Long-term effects beyond the pilot window | OPEN |

## Tech

| ID | Failure | Reproduce | Safeguard (where) | Escalate when | Not caught | Status |
|---|---|---|---|---|---|---|
| R-06 | Router sends a money case straight to Refund, skipping Risk Detection or diagnosis | Say "refund me" with no context | Router conditions on variables only actions can set (script); test suite before activation | Refund reachable without the required steps | A new route added later without a test | PROPOSAL |
| R-07 | An action fails or times out and the agent invents an answer | Break the flow in a test org | Fail to `UNKNOWN`: standard offer or a person; never an invented value (Flow + script) | Any action error on a money step | An error that returns plausible but wrong data | PROPOSAL |
| R-08 | A deploy or activation breaks routing for everyone | Deploy a changed router | One person merges and activates after the full test suite; keep the previous version to roll back | Any failed regression test | Model variation between runs (same test can pass and fail) | PROPOSAL |

## Data

| ID | Failure | Reproduce | Safeguard (where) | Escalate when | Not caught | Status |
|---|---|---|---|---|---|---|
| R-09 | Missing or wrong history/tier makes the agent treat a customer wrongly | Test with a contact that has no cases or no tier | Unknown means standard treatment, never the generous one; audit data before building on it (Flow, process) | Data missing for a money decision | Data that is present but wrong | OPEN |
| R-10 | Sensitive data (for example card numbers) inside text the agent can read or index | Search case text for digit patterns | Redact at the source; never discuss card details; keep indexed text clean (process + instruction) | Any sensitive data found | Data entered after the audit | OPEN |
| R-11 | Duplicate or unmerged customer records give a partial history | Two contacts for one person | Use the verified channel contact; schedule identity resolution if Data 360 is used | Different counts for the same person | Duplicates that are not detected | OPEN |

## How we debug a failure (the routine)
1. Reproduce with the exact message and the same test customer.
2. Read the trace: which subagent, which action, what each returned.
3. Find the layer: routing, action, data, or wording.
4. Fix in the lowest layer that can fix it (data -> flow -> script -> instruction).
5. Add the case to [TEST_PLAN.md](TEST_PLAN.md) and re-run the suite.
6. Escalate to the owner of that part, or to a person for customers, if it is not fixed in a short time box.

## Gap our safeguards will not catch (be honest)
- Instructions are not guarantees. If a rule exists only in prompt text, the model can break it. Money and identity rules must live in flows.
- A flow that returns correct-looking but wrong data (R-07, R-09) is not detected by the agent itself; only audits and tests catch it.
- Cost versus coverage: a re-check on every apply adds a little time and one more place to maintain, in exchange for stopping double payments. We accept it.
