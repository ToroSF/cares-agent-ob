# CARES agent: notes for AI assistants

Read `docs/README.md` first, then `docs/SPEC.md`, then the doc of the subagent you are working on.

Rules:
- This repo is public. Never write org URLs, ids, usernames, emails, tokens or real customer data into any file.
- Work only on your own subagent block in `force-app/main/default/aiAuthoringBundles/CARES/CARES.agent` and your own files. Do not edit the router or other subagents without the team's agreement.
- Do not deploy, publish or activate anything. A person merges and deploys at the end (see `docs/CONTRIBUTING.md`).
- Before any CLI command, confirm which org it targets.
- When you decide something, add it to `docs/DECISIONS.md` with the reason. When you find a limit, add it to `docs/GAPS.md`.
- Money and customer data decisions belong in a Flow or Apex (the script), not in instruction text. The model writes the words.
