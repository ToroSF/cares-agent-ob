# How we work on CARES

Goal: each person builds one subagent on their own branch. At the end one person merges everything, deploys and activates. Every decision, reason and known gap is written down so teammates (and their AI assistants) can follow what happened.

## This repository is public
Never commit: org URLs, org ids, usernames, emails, access tokens, real customer data, screenshots of the org. Use masked examples (`003…ABC`). If something leaks, tell the team right away and rotate it.

## Branches
- `main` is always in a state we could deploy. No direct commits to `main`.
- One branch per subagent: `feature/<subagent>-subagent` (for example `feature/risk-detection-subagent`, `feature/refund-subagent`).
- Keep branches short-lived. Rebase or merge `main` into your branch before opening the PR.

## Who edits what (to avoid merge conflicts)
The agent lives in one file (`CARES.agent`), so conflicts are likely if we edit each other's blocks.
- Edit **only your own** `subagent <name>:` block, plus any variables you add (add them at the end of the `variables:` list and prefix them with your subagent name, for example `risk_clean_30_day`).
- Put your Flows, Apex and test files in files named after your subagent. Do not change a teammate's files.
- Changes to the router, `system:` block or shared variables: open an issue or ask in the team channel first. One person owns these.
- Your docs: `docs/subagents/<subagent>.md` only. Shared docs (`SPEC.md`, `DECISIONS.md`, `GAPS.md`) are edited through a PR that touches only your own section or appends a row.

## Commits
- Small commits, present tense, say what and why: `Add Risk Detection flow that counts cases in the last 30 days`.
- No generated or unrelated files in a commit.

## Pull requests
Use the PR template. A PR must have:
1. What changed and why (link to the decision in `DECISIONS.md` if there is one).
2. How it was tested (happy, edge, adversarial) with results.
3. Known gaps, written in `GAPS.md`.
4. Confirmation that no identifiers or customer data are in the diff.
At least one teammate reviews. The reviewer checks the subagent doc matches the code.

## Deploying (read this before touching the org)
- Nobody deploys, publishes or activates in the shared org from a feature branch.
- Order at the end: merge all PRs into `main` -> validate the bundle -> one person deploys -> run the tests -> that person publishes and activates.
- Working in the org during the week is for reading and testing only, and only after telling the team.
- Before any CLI command, confirm which org the command targets.

## Writing rules for docs
- Plain English, short sentences, direct.
- Every choice has a reason ("Why") and what we gave up.
- Mark status clearly: `DECIDED`, `PROPOSAL`, `OPEN`.
- Dates in `YYYY-MM-DD`.
