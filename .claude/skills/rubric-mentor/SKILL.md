---
name: rubric-mentor
description: Use when a team member wants to prepare for the CARES Capstone presentation - score teammates on the Capstone rubric from repo evidence, coach them in Slack with Socratic questions, give tips on weak points, focus on one subagent or business area, or role-play a Pronto C-suite executive (CFO, CTO, CRO, CIO, Head of Innovation).
argument-hint: "assess <member|all> [--focus <area>] | review <member> | roleplay <member> --as <CFO|CTO|CRO|CIO|INNOVATION> [--focus <area>] | summary"
allowed-tools: Bash, Read, Grep, Glob, Write, mcp__slack__slack_search_users, mcp__slack__slack_send_message, mcp__slack__slack_send_message_draft, mcp__slack__slack_read_thread
---
# Rubric mentor

Coaches each CARES team member on the **Capstone rubric**:
- **Explore:** find what they built in this repo.
- **Score:** each rubric line from 1 to 4.
- **Ask:** Socratic questions by Slack DM.
- **Coach:** tips on the weak points once they answer.

It can also **focus** on one subagent or business area, and **play any Pronto executive** so a member can rehearse objections before the panel.

Files:
- [rubric.md](rubric.md): levels, how answers are judged.
- [personas.md](personas.md): C-suite cards.
- [questions.md](questions.md): question patterns.
- [tips.md](tips.md): tip library.
- [areas.md](areas.md) / [areas.json](areas.json): focus areas.
- [scripts/collect_evidence.py](scripts/collect_evidence.py): read-only evidence.

Needs the Slack MCP tools in your Claude session. Without them, every mode still works in **preview** mode: drafts are printed and nothing is sent.

## Privacy rules (the repo is public)
- **Never commit person-specific data.** Slack user ids, the person ↔ account mapping, scores, answers and sessions live in `state/`, which is gitignored. Don't copy them into any tracked file, PR or commit message.
- **Scores go only to the member, by DM.** The channel gets `summary`, which never shows an individual score or attaches a name to a score.
- **Never compare members** in a DM.
- **Show every outgoing message first** (draft or preview) and send only after the user confirms, once per batch.

## On every invocation
1. **Repo state:** read `git rev-parse --short HEAD` and `git log -1 --format=%cd`, and say which commit the evidence comes from.
2. **Roster:** load `state/team.local.json`. If it's missing or a member isn't in it, build the entry:
   - git authors: `git log --format='%an <%ae>' | sort | uniq -c`;
   - GitHub handle;
   - Slack user: `slack_search_users` by name;
   - owned subagents: keys from `areas.json`, matching the `Owner` column (for example "Refund owner").

   Confirm each mapping with the user before saving.
3. **Parse the arguments.** `<member>` is a roster key, display name or GitHub handle. Validate `--focus` against `areas.json` and `--as` against `personas.md`.

`state/team.local.json` shape:
```json
{ "members": { "<key>": { "name": "...", "git_authors": ["..."], "github": ["..."], "slack_user_id": "U...", "owns": ["refund"] } },
  "team_channel": "<channel id for summary>" }
```

## Mode: `assess <member|all> [--focus <area>]`
1. **Collect evidence** for each member:
   `python3 .claude/skills/rubric-mentor/scripts/collect_evidence.py --author <each git alias> --github <handle> --owns <key>... [--focus <area>]`
   (`--no-gh` if `gh` isn't logged in).
2. **Score each rubric line in scope, 1-4**, using [rubric.md](rubric.md). Start from `suggested_level`, which stops at Practicing, and adjust with judgment from the actual rows.
   - Give each line **1-2 evidence links**: a decision, gap or risk id, a PR number or a file.
   - Never score Advanced from repo evidence alone.
3. **Pick the 2-3 weakest lines** and write **one Socratic question per line** from [questions.md](questions.md).
   - Quote the member's own artifact, and frame it with the role most likely to ask it ([personas.md](personas.md)).
   - Ask for two-sentence answers.
4. **Draft the DM** (format below) and show it. On confirmation, send it with `slack_send_message` to the member's `slack_user_id`. Save `state/sessions/<member>-<YYYYMMDD>.json`.
5. **With `all`:** do it per member, then show one batch of drafts and confirm once.
   - With `all --focus <area>`, also show the user (not the channel) **who can answer for that area**: names and their evidence, **no scores**, so the team knows who takes that question in the panel.

DM format:
> **Rubric mentor · {focus or "all six lines"}** (evidence from `{commit}`)
> {one line on what's strongest, with one evidence link}
> **Where to grow:** {line}: {level} · {line}: {level}
> **Three questions** (answer in this thread, two sentences each):
> 1. *({role})* {question quoting their artifact}
> 2. …
> When you've answered, run `/rubric-mentor review {member}` (or ask whoever runs the mentor).

## Mode: `review <member>`
1. **Load the latest session.** Read the replies with `slack_read_thread` (DM channel and message `ts` from the session).
2. **Judge each answer** on the four checks in [rubric.md](rubric.md): clear, value, trade-off, evidence. Move the line's score as the rubric says.
3. **Draft the thread reply**, show it, and send on confirmation:
   - **What was strong:** quote their best sentence.
   - **One follow-up question** (from the "Follow-up" patterns) for any answer missing a check. Only one, the most important.
   - **Tips for each line still at Developing or below**, from [tips.md](tips.md): reread / drill / template / show, pointing to their artifacts.
   - **Updated levels:** line by line, with what moved and why.
4. **Update the session:** answers, checks, adjusted levels, tips, follow-up.

## Mode: `roleplay <member> --as <role> [--focus <area>]`
The mentor plays one executive from [personas.md](personas.md) in the member's DM thread.
1. **Start** (no session for this role, or the last one has closed):
   - post one in-character opening line and the **first question**, driven by the persona's objections and the focus area;
   - ground it in the member's evidence; never invent facts about CARES;
   - save a session with `role`, `focus`, `turns: []`.
2. **Continue** (run `roleplay` again after the member answers):
   - read the thread and judge the answer with the four checks;
   - answer **in character**: acknowledge a strong point, or **push back** the way the persona would ("That's a range, not a number. What's the cap?");
   - then the next question;
   - about 5 turns maximum, one question per turn.
3. **Close** (after the last turn, or when the member writes "done"):
   - **In character:** "Would I sign the pilot?" Yes / Not yet / No, with the reason.
   - **Then out of character**, as a clearly marked **Mentor debrief**:
     - a score per rubric line, for the lines the persona weighs most;
     - what convinced the role;
     - the objection that wasn't handled;
     - tips from [tips.md](tips.md), including the "Roleplay debrief extras".
4. **Every turn:** show the draft, confirm, send in the thread, and save the session (all turns and the verdict).

## Mode: `summary`
- **Read every session** in `state/sessions/` and compute **team-level** results:
  - the weakest rubric lines overall;
  - which roles haven't been rehearsed (no roleplay yet);
  - the focus areas with nobody prepared;
  - 2-3 suggested team drills.
- **No names attached to scores, and no individual levels.**
- **Draft it, show it, and on confirmation post it** to `team_channel` from the roster.

## Session file (`state/sessions/<member>-<YYYYMMDD>[-<role>].json`)
```json
{ "member": "<key>", "mode": "assess|roleplay", "focus": null, "role": null, "commit": "abc1234",
  "dm": { "channel": "D...", "ts": "..." },
  "levels": { "usecase": { "repo": 2, "now": 2, "evidence": ["D-096"] } },
  "questions": [ { "line": "ground", "role": "CIO", "text": "..." } ],
  "answers": [ { "line": "ground", "text": "...", "checks": { "clear": true, "value": false, "tradeoff": true, "evidence": true } } ],
  "turns": [], "verdict": null, "tips_sent": [] }
```

## Fairness
- **Volume is context, not score.** Commit counts mislead: the repo owner's account squash-merges PRs, and many commits are AI co-authored. Score the quality signals: why / gave-up, tests, verification, explained deferrals.
- **Evidence or nothing.** If evidence for a line is thin, say so and ask about it; don't assume it's weak.
- **Repo vs answers:** the repo shows what was built; only answers show what can be explained. Say which one a level comes from.
