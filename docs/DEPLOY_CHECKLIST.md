# Deploy checklist: `feature/grounding-policy-alignment`

What the person who deploys must do after this branch is merged into `main`. Follows the order in [CONTRIBUTING.md](CONTRIBUTING.md): merge → validate → one person deploys → tests → that person publishes and activates. Written 2026-10-20 by @Mateus-Goes. Nothing here has been deployed yet.

## What this branch adds to the org
| Component | Type | New or changed | Notes |
|---|---|---|---|
| `Case.CARES_Order_Ref__c` | Custom field (Text 80) | New | Used by the escalation Flow to find an open case for the same order (D-049) |
| `CARES_Escalations` | Queue (Case) | New | Owner of escalation cases. **Has no members yet** (G-055) |
| `CARES_Escalation_Access` | Permission set | Changed | Read/edit on the new field, create on CaseComment |
| `CARES_Create_Escalation_Case` | Flow | Changed | New input `escalationCategory`; Type, Reason, Priority, Status, queue, reuses an open case |
| `CARES_Get_Risk_Result` | Flow | Changed | G-053 fix (unknown contact → `UNKNOWN`, account-only branch reachable) |
| `CARES` | Authoring bundle | Changed | Urgent Escalation, Pronto Help, never-list, review threshold, `knowledge:` block |
| `CARES_Customer_Policy` | Data Library | **Already in the org** (D-053) | Created 2026-10-20 in Setup; READY, 3 files indexed. Not used by any agent until the bundle above is deployed |

## Before the deploy
1. `sf agent adl get -i <libraryId> --target-org <team org> --json` still shows a `retrieverId`, and `sf agent adl file list` shows the 3 files `INDEXED` (both true on 2026-10-20). If not, Pronto Help declines every question (safe, but useless) and the golden set cannot run (G-056).
2. Check the agent user can read the library: Data Cloud permission set and the Data Space scope (Setup UI only). Without them, search results are empty and **nothing shows an error** (G-056).
3. `sf agent validate authoring-bundle --api-name CARES --target-org <team org> --json` on merged `main`.
4. Check-only deploy of the metadata (`--dry-run`) on merged `main`.

## Deploy order
Field → queue → permission set → both Flows → authoring bundle. The Flows read the field and the queue, and the agent calls the Flows, so each step needs the one before it.

## ⚠️ Flow versions: decide before the deploy (G-062)
Both Flow files have `<status>Draft</status>`, the same as on `main`. In the org, version 1 of each Flow is **Active**. Deploying a Draft Flow adds a new **inactive** version, and the agent keeps calling the old active one. Result if nobody acts:
- the escalation case gets no Type, Reason, Priority or queue, and is never reused (D-049 does not take effect);
- the G-053 fix does not take effect (an unknown contact still comes back `CLEAN`).

The new versions are backward compatible: a blank category becomes `GENERAL`, so activating them does not break the v1 agent.

Two options, **the team decides** (owner: whoever deploys):
- **A.** After the deploy, activate the new version of both Flows (Setup → Flows → version → Activate), then check that the active version is the new one.
- **B.** Before the deploy, change both files to `<status>Active</status>` in a commit on `main`, so the deploy activates them.

Not done on this branch on purpose: activating a Flow changes what the live agent runs, so it is a team decision, not a grounding one.

## After the deploy
1. Add members to the `CARES_Escalations` queue (G-055). Without members, escalation cases sit in a queue nobody watches.
2. Live preview: new session, ask Q-01 from the golden set. In the trace, `search_pronto_policy` is called and returns a chunk with a citation. Empty results → go back to "Before the deploy" step 2.
3. Run the golden set ([grounding/golden-set.md](grounding/golden-set.md)). Targets: ≥ 13/15, 5/5, 5/5, **0 amounts, 0 allergen guarantees**.
4. Run P12 Pronto policy (B-PO-01 to B-PO-16) Tier S, then the P0 scenarios ([BASELINE_BATCH_TEST.md](BASELINE_BATCH_TEST.md)).
5. Escalation Flow: one escalation creates a case with Type, Priority and the queue; a second one for the same order reuses it (B-PO-14).
6. Write each result in [TEST_PLAN.md](TEST_PLAN.md).
7. Publish and activate: only the designated person, only after steps 2 to 5 pass.

## If something goes wrong
- Pronto Help answers nothing: library not indexed or no Data Space access. The agent still works; every other subagent is unaffected.
- Escalation case looks like before (no Type, no queue): the old Flow version is still active (see the warning above).
- To roll back the agent: activate the previous agent version. The Data Library, field and queue can stay; nothing else uses them.
