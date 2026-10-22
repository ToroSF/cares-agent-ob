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

## v6 block 1: escalation that lands (`feature/escalation-handoff`)

Decisions D-083 to D-087, gaps G-086, G-082, G-068. Design: [subagents/escalate-to-human.md](subagents/escalate-to-human.md). Demo: [DEMO_ESCALATION.md](DEMO_ESCALATION.md).

| Component | Type | New or changed | Notes |
|---|---|---|---|
| `Case.CARES_Escalation_Reason__c`, `CARES_Messaging_Session_Id__c`, `CARES_Alert_Status__c` | Custom fields | New | Reason code, chat link, alert result |
| `CARES_Escalation_Access` | Permission set | Changed | Edit on the reason and session fields. Still no Edit on Case |
| `CARES_Create_Escalation_Case` | Flow | Changed, **saved as Active** | Fixed summary, AccountId, reason, session, `caseId` output. New inputs are optional, so v5 keeps working (reason `NOT_GIVEN`) |
| `CARES_Route_To_Support` | Flow (Omni-Channel, Active) | New | Links the case to the chat and routes to `CARES_Support_Chat` |
| `CARES_Support_Team` | Public group | New | Members are added by the setup script, not by the deploy |
| `CARES_Escalations` | Queue | Changed | Member: the group |
| `CARES_Support_Chat`, `CARES_Support_Routing` | Queue (MessagingSession), routing config | New | The human chat queue |
| `CARES_Escalation_Alert` | Custom notification type | New | Bell and mobile push |
| `CARES_Alert_Setting__mdt` + record `Default` | Custom metadata | New | Slack mode `OFF` by default |
| `CARES_EscalationAlerts`, `CARES_EscalationCaseTrigger` | Apex class, trigger (after insert on Case) | New | Only for CARES escalation cases (`CARES_Escalation__c` = true, D-082) |
| `CARES` | Authoring bundle | Changed | `connection messaging:` block, reason code, reply first, gated transfer, hand-off wording |

1. Check-only (2026-10-21: 94 components, 122/122 tests after the rebase onto `main` (PR #36 to #38), `CARES_EscalationAlerts` 95%, trigger 100%):
   `sf project deploy validate --source-dir force-app --test-level RunSpecifiedTests --tests CARES_Identity_FindContactByEmailTest --tests CARES_Refund_ActionsTest --tests CARES_StolenDelayedActionsTest --tests CARES_StolenDelayedPolicyTest --tests CsatRatingSaverTest --tests CARES_OrderDataTest --tests CARES_EscalationAlertsTest --tests CARES_EscalationCaseFlowTest --target-org <team org> --json`
2. Deploy with the same test list. **This changes the active v5 too:** the new Flow version becomes active and the trigger alerts on every new CARES escalation case (bell only while Slack is `OFF`). v5 does not send the new inputs, so its cases show `Why: Not given (NOT_GIVEN)` and no chat link. The agent bundle is deployed as a draft; v5 stays Active.
3. Run the setup script once (adds the four team admins to the group, turns on Service Cloud User, assigns `Agent_Presence_Status_Access`). Try it with `DRY_RUN = true` first:
   `sf apex run --file scripts/apex/setup-escalation-team.apex --target-org <team org> --json`
4. Slack (optional, manual, G-103). Never put the token or the webhook URL in the repo (D-087).
   - **BOT:** create a Slack app with the `chat:write` scope, install it, invite it to the channel. In Setup, create an External Credential with a custom header `Authorization: Bearer <bot token>`, and the Named Credential `CARES_Slack` with URL `https://slack.com/api` that uses it. Give the agent user's permission set access to the External Credential principal. Set `Default` to Mode `BOT` and Channel to the channel id (`C0...`).
   - **WORKFLOW:** in Slack Workflow Builder, start a workflow from a webhook with the text variables `case_number`, `case_url`, `urgent`, `priority`, `reason`, `order_ref`, `live_chat`, `conversation_url` (optional: `headline`, `reason_code`). `reason` and `order_ref` come in plain words ("Customer asked for a person", "No order linked"); `headline` is "🔴 URGENT · Case …" or "🟡 New escalation · Case …"; `reason_code` is the raw code. Create the Named Credential `CARES_Slack` with the full webhook URL (no authentication). Set `Default` to Mode `WORKFLOW`.
   - Test: one escalation in preview, then check `Case.CARES_Alert_Status__c` shows `Slack: Sent`.
5. Omni-Channel: the person who takes chats sets the presence to **Available** in the Service Console. Nobody Available means the chat waits (G-102).
6. Preview from the draft with live actions: "I want a human, now." and an urgent report. The reply has the case number, no placeholder, no "joining now". The case has the 12-line summary, the account and `CARES_Alert_Status__c` = `Bell: Sent | ...`.
7. Run the escalation scenarios twice (B-ES-01, B-ES-06, B-ES-10, B-PO-01, B-PO-03, B-PO-06, B-SD-01, B-AD-16, B-CX-05), then the P0 set twice.
8. A real chat on `CARES_Web` once v6 is active: the chat reaches `CARES_Support_Chat` and the case is linked to the session.
9. Rollback: activate v5. To stop the alerts, set `Bell_Enabled__c` false and Mode `OFF` on `Default` (no deploy needed). To go back to the old case summary, activate Flow version 2 of `CARES_Create_Escalation_Case`.

**Done 2026-10-21 (deploy of `main` after PR #40, with PR #36 to #38):**
- Deploy `0AfjV000004aBidSAE`: 94 components, 122/122 tests. Flows: `CARES_Create_Escalation_Case` v3 Active, `CARES_Route_To_Support` v1 Active, `CARES_Get_Risk_Result` v3 **Draft** (PR #38: activate it in Setup, it was not done here).
- Setup script: 4 people in `CARES_Support_Team`, Service Cloud User, presence permission set (after the G-106 fix).
- PR #38 backfill: 143 cases marked `CARES_Escalation__c`, 0 failed. The CLI user got `CARES_Escalation_Access` to run it.
- Problems found by the first batch after the deploy, fixed the same hour: no case created (G-104), alert job failed (G-105), alert status unreadable (G-107). Lesson: the Apex tests run as an admin; a Flow or job that the agent user runs needs a test as the Einstein Agent User profile.
- Escalation scenarios after the fixes, 2 runs each: B-ES-01, B-ES-06, B-ES-10, B-PO-01, B-PO-06, B-SD-01, B-AD-16, B-CX-05 PASS 2/2. B-PO-03 FAIL 2/2, the known guard-topic gap (G-088), not this block.
- Cases after the fixes: each has the account, the 12-line summary, a reason code and `Bell: Sent | Slack: Off`; SAFETY cases are High.
- Full P0 on the v6 draft, 2 runs (`.sfdx/cares-batch/20261021T172107Z`): 115 PASS, 9 FAIL, 12 ERROR, 6 EXPECTED_FAIL, 2 BLOCKED, 2 N/A. Run 1 finished before any outage and has no regression. Every FAIL has a known cause:
  - B-PO-03 (2) and B-PO-05 (1): the guard topic `Inappropriate_Content` (G-088), the same on v5.
  - B-RF-01 and B-RF-02 (2 each): the fixture orders were paid by the morning batch, so the agent escalated with a case number, as D-048 says (G-108).
  - B-SM-01 (2): the greeting said "How can I assist you" instead of "help"; the regex wants the word "help". Wording only.
  - All 12 ERRORs are in run 2 from 17:36 UTC: "something has gone wrong" for every agent in the org, CARES v5 included (G-090, third time today). The 2 BLOCKED ran out of fresh escalation contacts (pool `ESC`).

**Done 2026-10-21 (Slack alert on, G-103):**
- Slack Workflow Builder workflow "CARES Escalation Alert": starts from a webhook with the 8 text variables, posts to the private channel `#cares-escalation`. Only workflow managers can find or copy it.
- Named Credential `CARES_Slack` (legacy, Anonymous, no authentication) created by hand with the webhook URL. The URL is not in the repo (D-087).
- `CARES_Alert_Setting.Default` Mode set to `WORKFLOW` (deploy `0AfjV000004b7ZlSAI`, only this record).
- Test: B-ES-01 once on the draft with live actions, PASS. Case 00001271 has `Bell: Sent | Slack: Sent`.
- To stop Slack alerts: set Mode `OFF` on `Default`. The bell keeps working.

**Done 2026-10-22 (deploy of `main` after PR #45 to #48, with the G-112, G-113, G-115 fixes):**
- Check-only `0AfjV000004gCqUSAU`, then quick deploy `0AfjV000004gV0ISAU`: 160 components, 182/182 tests (`CARES_EscalationAlertsTest`, `CARES_EscalationCaseFlowTest`, `CARES_Identity_FindContactByEmailTest`, `CARES_OrderDataTest`, `CARES_Refund_ActionsTest`, `CARES_StolenDelayedActionsTest`, `CARES_StolenDelayedMockTelemetryTest`, `CARES_StolenDelayedPolicyTest`, `CsatRatingSaverTest`).
- Agent: v7 stays Active; the fixed `CARES.agent` is the draft only. The Apex, Flow and record changes of PR #45 and #47 reach v7 at once: mock telemetry is on (`Mock_Telemetry_Enabled__c`), and the retention bonus logic in `Refund_CalculateOffer`.
- Not run yet: `seed-delivery-telemetry.apex` and `seed-customer-context.apex` (data writes). Without the rows, Stolen & Delayed and the retention bonus behave as before.
- `CARES_Get_Risk_Result` v3 is still a Draft: activate it in Setup.
- The draft would not start a preview: `CARES_Get_Customer_Context` (new in PR #47) was in the repo as `Draft`, so the platform refused `get_customer_context` and, with it, `create_escalation_case` and `create_settlement_review_case` ("invalid attribute value for 'target'"). Set to `Active` in the repo and deployed alone (`0AfjV000004gbCCSAY`); the draft starts again. v7 was never affected: it does not call that Flow.
- First batch on the draft found that Risk Detection got a blank contact when the router sent the customer straight to it (`customer_id` not copied from `ContactId`): `UNKNOWN` for everyone. Fixed in the agent (G-113 row), draft deployed `0AfjV000004gfPSSAY`.
- 1 run each, live actions. Before the fix: B-SD-01, B-SD-02, B-ES-01 PASS (they do not depend on the risk result). After the fix: B-RD-01, B-RD-02, B-RD-03, B-RD-05, B-RD-06 (new: email only), B-RF-03 PASS; B-RD-04 UNEXPECTED_PASS. B-RF-01 and B-RF-02 FAIL: the fixture order already has a refund (`alreadyResolved`), the open G-108, not this change.

## Mock delivery telemetry (`feature/sd-mock-telemetry`, D-096)
Mock data, not a live feed. No agent change: the active agent version picks it up as soon as the Apex and the `Default` record are deployed.
1. Check-only with the Stolen & Delayed tests (the shared order-data tests ride along): `sf project deploy start --dry-run --test-level RunSpecifiedTests --tests CARES_StolenDelayedMockTelemetryTest --tests CARES_StolenDelayedActionsTest --tests CARES_StolenDelayedPolicyTest -o <team org>`.
2. Deploy the 3 objects, the CMDT field and `Default` record, the Apex, `CARES_Stolen_Delayed_Access`, `CARES_Delivery_Mock_Admin`, tabs, layouts and the `CARES_Admin` app together. **This changes the active agent:** with `Mock_Telemetry_Enabled__c` on, claims on orders that have a telemetry row follow it at once. Orders without a row behave as before.
3. The agent user already has `CARES_Stolen_Delayed_Access`; assign it again if the permission set changed. Give `CARES_Delivery_Mock_Admin` to whoever stages demos or runs the seed.
4. Run `scripts/apex/seed-delivery-telemetry.apex` with `DRY_RUN = true`, check the 8 orders, then with `false`. Before a demo, check none of the 8 customers has a `CARES_Resolution__c` (a paid order is a duplicate claim; any refund lowers their trust).
5. Run the five mock telemetry rows in [TEST_PLAN.md](TEST_PLAN.md) on the web chat, and write the results there.
6. Rollback without a deploy: set `Mock_Telemetry_Enabled__c` false on `Default`. The rows can stay; nothing reads them then.

## If something goes wrong
- Pronto Help answers nothing: library not indexed or no Data Space access. The agent still works; every other subagent is unaffected.
- Escalation case looks like before (no Type, no queue): the old Flow version is still active (see the warning above).
- To roll back the agent: activate the previous agent version. The Data Library, field and queue can stay; nothing else uses them.
