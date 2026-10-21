# Deploy checklist: `feature/grounding-policy-alignment` (PR #15) and PR #18

What the person who deploys must do after this branch is merged into `main`. Follows the order in [CONTRIBUTING.md](CONTRIBUTING.md): merge → validate → one person deploys → tests → that person publishes and activates. Written 2026-10-20 by @Mateus-Goes. Deployed to the team org on 2026-10-21 (agent v4): seed run (3 tiers, 12 policies, 187 contacts) and option A below done (both Flows on their new version, v2).

**Updated 2026-10-21:** this branch now includes `main` after PR #18 (audit and the real Refund backend). None of PR #18 is in the org yet either (checked 2026-10-21: the org still runs the Refund stubs and has no `CARES_Tier__c`). Its Apex tests first ran in a check-only deploy on 2026-10-21, and two deploy blockers were fixed on this branch (G-078). So the deploy below carries both.

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
| `CARES_Tier__c`, `CARES_Refund_Policy__c`, `CARES_Resolution__c`, `Contact.CARES_Tier__c` | Custom objects, field | New (PR #18) | Tier and policy rows set the refund ceilings (D-046, D-047); Resolution is the audit row (D-048). **No rows are seeded** by the deploy: run the seed script (R-17, D-073, step 6) |
| `CARES_Refund_Policy_Admin` | Permission set | New (D-073) | For CRM users who maintain tiers and policy rows, and for whoever runs the seed script. Not for the agent user |
| `CARES_Refund_CalculateOffer`, `CARES_Refund_IssueResolution`, `CARES_Refund_LogOrderIssue`, `CARES_Refund_FindOrder`, `CARES_Refund_ActionsTest` | Apex | Changed (PR #18) | Real policy, audit row, double-payout block, items must be on the order. `FindOrder` and `ApplySettlement` are still stubs (G-004) |
| `CARES_Refund_Access`, `CARES_Experience_Rating_Access` | Permission sets | Changed (PR #18) | Access to the new objects; CSAT field and Contact read (D-056). Field access to required fields removed on this branch, or the deploy fails (G-078) |
| `CARES_Customer_Policy` | Data Library | **Already in the org** (D-067) | Created 2026-10-20 in Setup; READY, 3 files indexed. Not used by any agent until the bundle above is deployed |

## Before the deploy
1. `sf agent adl get -i <libraryId> --target-org <team org> --json` still shows a `retrieverId`, and `sf agent adl file list` shows the 3 files `INDEXED` (both true on 2026-10-20). If not, Pronto Help declines every question (safe, but useless) and the golden set cannot run (G-069).
2. Check the agent user can read the library: Data Cloud permission set and the Data Space scope (Setup UI only). Without them, search results are empty and **nothing shows an error** (G-069).
3. The agent user has `CARES_Identity_Access` (PR #16) and the four CARES permission sets (G-050). All true on 2026-10-20.
4. `sf agent validate authoring-bundle --api-name CARES --target-org <team org> --json` on merged `main`.
5. Check-only deploy with tests on merged `main`. Use `RunSpecifiedTests`, not `RunLocalTests`: old `Agent*` classes in the org do not compile (G-079).
   `sf project deploy validate --source-dir force-app --test-level RunSpecifiedTests --tests CARES_Identity_FindContactByEmailTest --tests CARES_Refund_ActionsTest --tests CARES_StolenDelayedActionsTest --tests CARES_StolenDelayedPolicyTest --tests CsatRatingSaverTest --target-org <team org> --json`
   Passed on this branch on 2026-10-21: 69 components, 81/81 tests. With `CARES_Refund_Policy_Admin` (D-073): 70 components, 81/81. Use the same test list for the real deploy.
6. **Blocking: Refund data (R-17).** At least one active `CARES_Tier__c` row and one active `CARES_Refund_Policy__c` row per order outcome (Stolen, Delayed, Wrong_Missing_Items, Quality_Issue) for that tier. Owner: the Refund owner. Without them every direct-path refund is ineligible (D-047, [refund.md](subagents/refund.md)).
   The seed script does it (D-073). Run it right after the objects and permission sets are deployed:
   1. Assign `CARES_Refund_Policy_Admin` to the person who runs the script (not to the agent user): `sf org assign permset --name CARES_Refund_Policy_Admin --target-org <team org> --json`.
   2. Dry run first: set `DRY_RUN = true` in the script, then `sf apex run --file scripts/apex/seed-refund-tiers.apex --target-org <team org> --json`. The `SEED` lines show the tier counts.
   3. Set `DRY_RUN = false` (don't commit the change) and run it again.
   4. Expected: 3 active tiers, 12 active policy rows, 187 contacts with a tier (Explorer 26, Insider 130, Pronto Plus 31, on the data of 2026-10-21). Check with `SELECT COUNT() FROM CARES_Refund_Policy__c WHERE Active__c = true` and `SELECT CARES_Tier__r.Name, COUNT(Id) FROM Contact WHERE CARES_Tier__c != null GROUP BY CARES_Tier__r.Name`.
   The amounts are `[$]` (D-065): the Refund owner reviews them before the publish. Running it again is safe.
7. The agent user has `CARES_Refund_Access` with PR #18's object permissions (assign again if the permission set changed).

## Deploy order
Objects and fields (Case field, PR #18 objects) → queue → permission sets → Apex → both Flows → authoring bundle. The Flows read the field and the queue, the Apex reads the objects, and the agent calls both, so each step needs the one before it. Refund data rows (step 6 above) go in right after the objects and permission sets: the script needs both.

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

## v5: real orders from Data Cloud (`feature/real-order-data`)

Adds `CARES_OrderData`, `CARES_Order_GetStatus` and `CARES_OrderDataTest`, changes `CARES_Refund_FindOrder`, `CARES_Refund_LogOrderIssue`, `CARES_Refund_ActionsTest`, `CARES_Refund_Access` and `CARES.agent` (Order Status sub-agent). Decisions D-071, D-072, D-074, D-075.

1. Needs in the org (already there in the team org): the Data Cloud stream `Order` (`Order__dlm`), the field `Contact.Pronto_App_Account_Id__c` filled for the customers, and `AgentforceServiceAgentUserPsg` on the agent user (it gives read on `Order__dlm`).
2. Check-only with the new test class (2026-10-21: 99/99, coverage `CARES_OrderData` 90.5%, the others 97 to 100%):
   `sf project deploy validate --source-dir force-app --test-level RunSpecifiedTests --tests CARES_Identity_FindContactByEmailTest --tests CARES_Refund_ActionsTest --tests CARES_StolenDelayedActionsTest --tests CARES_StolenDelayedPolicyTest --tests CsatRatingSaverTest --tests CARES_OrderDataTest --target-org <team org> --json`
3. Deploy the Apex, the permission set and the bundle together. The new `find_order` and `log_order_issue` also change what the active v4 does: v4 does not send `contactId` to `log_order_issue`, so item refunds on v4 stop being accepted until v5 is active. Publish v5 soon after the deploy, or roll back.
4. Preview from the authoring bundle with live actions and `'$Context.ContactId=<id>'` (demo customers in `.claude/skills/cares-testing/personas.md`): (a) a missing item on the latest order gets a real `PR-...` order and an offer within the order total; (b) "where is my order?" gives the real status and ETA; (c) another customer's order number is not found.
5. Publish and activate v5. Rollback: activate v4 and deploy the Apex from tag `pre-v5`.

**Done 2026-10-21 (agent v5 Active, v4 Inactive):**
- Deploy: 8 components, 99/99 tests (the test list in step 2).
- Preview, customer Alex Morgan:
  - (a) "my last order was missing the lemonade": `PR-250812-0LNZ2JM`, Lemonade $9.14, cap $27.40. Offer: refund $9.14 or credit $10.97 (Pronto Plus).
  - (b) "where is my order?": `PR-250814-C3V2D3K`, Picked Up, ETA Aug 14, 2025 4:37 PM UTC (the D-074 ETA fix).
  - (c) Garrik Forman's `PR-240830-FWZ0TPF`: not found, both for status and for a refund.
- The preview found one problem: the not-found prompt used a real order number of another customer as the format example. Fixed in PR #22 before the publish.
- Smoke test on the published v5 (`--api-name`, no ContactId, identified by email): status and missing-item refund both worked.

## If something goes wrong
- Pronto Help answers nothing: library not indexed or no Data Space access. The agent still works; every other subagent is unaffected.
- Escalation case looks like before (no Type, no queue): the old Flow version is still active (see the warning above).
- To roll back the agent: activate the previous agent version. The Data Library, field and queue can stay; nothing else uses them.
