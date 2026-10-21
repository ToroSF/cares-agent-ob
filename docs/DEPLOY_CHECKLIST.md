# Deploy checklist: `feature/grounding-policy-alignment`

What the person who deploys must do after this branch is merged into `main`. Follows the order in [CONTRIBUTING.md](CONTRIBUTING.md): merge → validate → one person deploys → tests → that person publishes and activates. Written 2026-10-20 by @Mateus-Goes. Nothing here has been deployed yet.

**Updated 2026-10-21:** this branch now includes `main` after PR #18 (audit and the real Refund backend). None of PR #18 is in the org yet either (checked 2026-10-21: the org still runs the Refund stubs and has no `CARES_Tier__c`), and its Apex tests have never run in an org. So the deploy below carries both.

## What this branch adds to the org
| Component | Type | New or changed | Notes |
|---|---|---|---|
| `Case.CARES_Order_Ref__c` | Custom field (Text 80) | New | Used by the escalation Flow to find an open case for the same order (D-063) |
| `CARES_Escalations` | Queue (Case) | New | Owner of escalation cases. **Has no members yet** (G-068) |
| `CARES_Escalation_Access` | Permission set | Changed | Read/edit on the new field, create on CaseComment |
| `CARES_Create_Escalation_Case` | Flow | Changed | New input `escalationCategory`; Type, Reason, Priority, Status, queue, reuses an open case |
| `CARES_Get_Risk_Result` | Flow | Changed | G-066 fix (unknown contact → `UNKNOWN`, account-only branch reachable) |
| `CARES` | Authoring bundle | Changed | Urgent Escalation, Pronto Help, never-list, review threshold, `knowledge:` block. Includes Identify Customer from PR #16 (merged into this branch) |
| `CARES_Identity_FindContactByEmail`, `CARES_Identity_Access` | Apex class, permission set | In the org since PR #16; PR #18 changed formatting only | The bundle calls this class from Identify Customer. The agent user needs `CARES_Identity_Access`, or the bundle fails its startup action check (same as G-050) |
| `CARES_Tier__c`, `CARES_Refund_Policy__c`, `CARES_Resolution__c`, `Contact.CARES_Tier__c` | Custom objects, field | New (PR #18) | Tier and policy rows set the refund ceilings (D-046, D-047); Resolution is the audit row (D-048). **No rows are seeded** (R-17) |
| `CARES_Refund_CalculateOffer`, `CARES_Refund_IssueResolution`, `CARES_Refund_LogOrderIssue`, `CARES_Refund_FindOrder`, `CARES_Refund_ActionsTest` | Apex | Changed (PR #18) | Real policy, audit row, double-payout block, items must be on the order. `FindOrder` and `ApplySettlement` are still stubs (G-004) |
| `CARES_Refund_Access`, `CARES_Experience_Rating_Access` | Permission sets | Changed (PR #18) | Access to the new objects; CSAT field and Contact read (D-056) |
| `CARES_Customer_Policy` | Data Library | **Already in the org** (D-067) | Created 2026-10-20 in Setup; READY, 3 files indexed. Not used by any agent until the bundle above is deployed |

## Before the deploy
1. `sf agent adl get -i <libraryId> --target-org <team org> --json` still shows a `retrieverId`, and `sf agent adl file list` shows the 3 files `INDEXED` (both true on 2026-10-20). If not, Pronto Help declines every question (safe, but useless) and the golden set cannot run (G-069).
2. Check the agent user can read the library: Data Cloud permission set and the Data Space scope (Setup UI only). Without them, search results are empty and **nothing shows an error** (G-069).
3. The agent user has `CARES_Identity_Access` (PR #16) and the four CARES permission sets (G-050). All true on 2026-10-20.
4. `sf agent validate authoring-bundle --api-name CARES --target-org <team org> --json` on merged `main`.
5. Check-only deploy of the metadata with tests (`sf project deploy validate --source-dir force-app --test-level RunLocalTests`) on merged `main`. It is the first run of PR #18's Apex tests in an org.
6. **Blocking: Refund data (R-17).** At least one active `CARES_Tier__c` row and one active `CARES_Refund_Policy__c` row per order outcome (Stolen, Delayed, Wrong_Missing_Items, Quality_Issue) for that tier. Owner: the Refund owner. Without them every direct-path refund is ineligible (D-047, [refund.md](subagents/refund.md)).
7. The agent user has `CARES_Refund_Access` with PR #18's object permissions (assign again if the permission set changed).

## Deploy order
Objects and fields (Case field, PR #18 objects) → queue → permission sets → Apex → both Flows → authoring bundle. The Flows read the field and the queue, the Apex reads the objects, and the agent calls both, so each step needs the one before it. Refund data rows (step 6 above) go in right after the objects.

## ⚠️ Flow versions: decide before the deploy (G-075)
Both Flow files have `<status>Draft</status>`, the same as on `main`. In the org, version 1 of each Flow is **Active**. Deploying a Draft Flow adds a new **inactive** version, and the agent keeps calling the old active one. Result if nobody acts:
- the escalation case gets no Type, Reason, Priority or queue, and is never reused (D-063 does not take effect);
- the G-066 fix does not take effect (an unknown contact still comes back `CLEAN`).

The new versions are backward compatible: a blank category becomes `GENERAL`, so activating them does not break the v1 agent.

Two options, **the team decides** (owner: whoever deploys):
- **A.** After the deploy, activate the new version of both Flows (Setup → Flows → version → Activate), then check that the active version is the new one.
- **B.** Before the deploy, change both files to `<status>Active</status>` in a commit on `main`, so the deploy activates them.

Not done on this branch on purpose: activating a Flow changes what the live agent runs, so it is a team decision, not a grounding one.

## After the deploy
1. Add members to the `CARES_Escalations` queue (G-068). Without members, escalation cases sit in a queue nobody watches.
2. Live preview: new session, ask Q-01 from the golden set. In the trace, `search_pronto_policy` is called and returns a chunk with a citation. Empty results → go back to "Before the deploy" step 2.
3. Run the golden set ([grounding/golden-set.md](grounding/golden-set.md)). Targets: ≥ 13/15, 5/5, 5/5, **0 amounts, 0 allergen guarantees**.
4. Run P12 Pronto policy (B-PO-01 to B-PO-16) Tier S, then the P0 scenarios ([BASELINE_BATCH_TEST.md](BASELINE_BATCH_TEST.md)).
5. Escalation Flow: one escalation creates a case with Type, Priority and the queue; a second one for the same order reuses it (B-PO-14).
   Refund (PR #18): an item issue gets an offer from the policy row, not "A team member will take it from here" (R-17); the same order can't be paid twice (D-048).
   Also on the website chat (no contact): a safety report goes to Urgent Escalation and logs a case with no contact; a refund request goes Risk Detection → Refund → Identify Customer → Refund.
6. Write each result in [TEST_PLAN.md](TEST_PLAN.md).
7. Publish and activate: only the designated person, only after steps 2 to 5 pass.

## If something goes wrong
- Pronto Help answers nothing: library not indexed or no Data Space access. The agent still works; every other subagent is unaffected.
- Escalation case looks like before (no Type, no queue): the old Flow version is still active (see the warning above).
- To roll back the agent: activate the previous agent version. The Data Library, field and queue can stay; nothing else uses them.
