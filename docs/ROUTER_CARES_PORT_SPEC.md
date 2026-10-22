# Spec: port the router redesign from CARES_Router_V2 into CARES

Status date: 2026-10-22. Status: `PROPOSAL`. Nothing in this file is built yet.

- **Branch:** `fix/router-cares-port`.
- **Source:** `main` at `735e77a` (PRs #48 to #52), plus R-D10 and the batch-runner timeout fix carried on this branch.
- **Target:** `force-app/main/default/aiAuthoringBundles/CARES/CARES.agent`. It is **v8, Active in the team org** (v7 is Inactive).
- **Other docs:**
  - The design and decisions R-D1 to R-D10 are in [ROUTER_REDESIGN_SPEC.md](ROUTER_REDESIGN_SPEC.md). This spec doesn't repeat them.
  - The analysis and the target diagram are in [ROUTER_AUDIT.md](ROUTER_AUDIT.md).
- **Line numbers:** `L…` is `CARES.agent` at `735e77a`. `V2 L…` is `CARES_Router_V2.agent` on this branch.

## 1. Why a port, and what it must not undo

The redesign was built and tested in a separate draft agent, `CARES_Router_V2`, so the live agent was never touched. The draft is deployed to the team org and not published. That test agent was copied from `CARES.agent` at `c83591b`. Since then, `main` changed `CARES.agent` in one place only:

```
git diff c83591b 735e77a --stat -- force-app/main/default/aiAuthoringBundles/CARES/CARES.agent
  1 file changed, 15 insertions(+), 5 deletions(-)      # PR #49, Risk Detection only
```

Checked on 2026-10-22:
- Every block the redesign doesn't change is **identical** in both files: `experience_rating`, `experience_rating_skipped`, `urgent_escalation`.
- The current `CARES.agent` compiles with no errors (`@sf-agentscript/agentforce` 2.9.27).

So the port is a copy of the V2 blocks, plus **one reconciliation**: PR #49's Risk Detection (section 2).

### What else changed on `main` since `c83591b`, and why the port is unaffected

| Change | Where | Effect on the port |
|---|---|---|
| #49 G-112: flat `if`s in Risk Detection | `CARES.agent` L882-892 | Kept in substance. V2's Risk Detection is flat too (V2 L1013-1015) |
| #49 G-113: `customer_id` for both risk lookups, and identify the customer before the check | `CARES.agent` L861-869, L871, L885 | Outcome kept. The routing is replaced (section 2) |
| #49 G-115: permission sets and `CsatRatingSaverTest` | metadata and Apex | None, it doesn't touch the agent |
| #52: `CARES_Get_Risk_Result` v3 and `CARES_Get_Customer_Context` are Active | Flows | None. V2 calls the same Flows with the same inputs. Both must stay Active (G-075) |
| #49 scenario B-RD-06, runner `no_contact` and start-failure handling | tests | B-RD-06's expected path changes (section 4) |
| #51: the D-095 rollout checklist | docs | Its open steps still apply: assign `CARES_Risk_Context_Access` to the agent user, run the seeds |

## 2. The one reconciliation: Risk Detection identity (#49 vs the V2 gate)

**#49 today** (L861-869). With no contact yet, Risk Detection does this:
1. Sets `router_active_task = "REFUND"`.
2. Sends the customer to Identify Customer.
3. `identify.continue_refund` brings them back to Refund, which sends them to Risk Detection again.
4. Risk Detection always exits to Refund (L891-892).

That works today because Refund is the only order path behind the risk check.

**After the port it would be wrong.** A whole-order problem now goes router → Risk Detection → Stolen & Delayed, and Risk Detection's exit depends on the task (R-D10, V2 L1017-1020). If #49's `set router_active_task = "REFUND"` stayed, a customer identified by email partway through a "never arrived" claim would come back from identification marked `REFUND`. They would then go to Refund instead of Stolen & Delayed, and the G-087 fix would be undone for every web-chat customer.

**Decision for the port:** take V2's Risk Detection block whole (V2 L930-1058). It keeps everything #49 delivered:

| #49 outcome | Where V2 does it |
|---|---|
| `ContactId` copied into `customer_id` first | Gate, first line after the reset |
| Customer identified before the risk check, so it runs once on the right contact | `customer_id == ""` → `identify_pending = True` → Identify Customer, before `get_risk_result` |
| `get_risk_result` and `get_customer_context` take `customer_id` | Both `with contactId = @variables.customer_id` |
| No nested `if` (G-112) | Top-level `if`s only, including the NOT_CLEAN override |
| PATTERN_REVIEW never reads the retention context (D-083) | The `get_customer_context` call sits in the `else` of the threshold check |

What changes against #49:
- **The return from Identify Customer goes back to Risk Detection** (`continue_to_risk`), which then exits by task. It no longer goes through Refund.
- **PATTERN_REVIEW is a flag** (`risk_needs_review`), acted on by Refund and S&D (R-D6), not a transition out of Risk Detection.

Keep #49's two code comments in the new block, so the history stays readable: the G-113 note on `customer_id` and the G-112 note on flat checks.

## 3. The port, block by block

The mechanics are simple: copy each V2 block over the CARES block, then review `git diff` against `735e77a` one block at a time. Each subagent owner reviews their own block (CONTRIBUTING.md). The router has no owner, so the team reviews it.

| `CARES.agent` block | Action | Owner reviews | Main content |
|---|---|---|---|
| `system.instructions` (L2) | Take V2's | Team | The list of specialist areas |
| `config` (L7-11) | **Keep CARES's** `developer_name: "CARES"` and `agent_label: "CARES"`. Description: "CARES is a customer care router agent: order problems go through a silent check to Refund or Stolen & Delayed Orders; it also handles order status, Pronto's rules, escalation to a person and feedback." | Team | No "test copy" text |
| `access`, `knowledge`, `language`, `connection messaging` | Unchanged | — | Same values in both files |
| `variables` | Add `identify_pending`, `identify_turns`, `risk_needs_review` (V2 L150-155). Take V2's descriptions for `router_active_task` and `customer_id` | Team | R-D5, R-D6, R-D8 |
| `agent_router` (L169-228) | Replace with V2 L176-234 | Team | 11 routes: two order routes, four continuation-only routes, urgent and person routes, fallback |
| `refund` (L229-640) | Take V2 L235-707 | Refund owner | Per-issue reset when Refund is the first stop. Its own identify bounce removed. PATTERN_REVIEW flag. `close_issue`. `WRAP_UP`. `channelContactId = customer_id` (R-D2) |
| `stolen_delayed_orders` (L641-855) | Take V2 L708-929 | S&D owner | PATTERN_REVIEW flag, `go_to_refund_items`, `continue_to_refund` goes straight to Refund, identify bounce removed, `WRAP_UP` on redispatch |
| `risk_detection` (L856-930) | Take V2 L930-1058 (section 2) | Risk Detection owner | Reset, identity gate, both checks on `customer_id`, flag, exit by task |
| `experience_rating`, `experience_rating_skipped`, `urgent_escalation` | Unchanged | — | Already identical |
| `escalate_to_human` (L1025-1153) | Take V2 L1153-1286 | Escalate owner | `identify_pending` cleared, `channelContactId = customer_id`, `WRAP_UP` only without a live transfer and never for URGENT |
| `pronto_help` (L1166-1241) | Take V2 L1299-1369 | Pronto Help owner | Hand-offs removed. `WRAP_UP` when no other task is open |
| `order_status` (L1242-1306) | Take V2 L1370-1435 | Order Status owner | Delivery and item split, `identify_pending`, `WRAP_UP` once the order is found, escalate route removed |
| `identify_customer` (L1307-1370) | Take V2 L1436-1496 | Identify owner | `continue_to_risk` and `continue_order_status`, turn cap |
| `off_topic` (L1371-1394) | **Delete** | Team | Merged into the fallback |
| `ambiguous_question` (L1395-1418) | Take V2 L1497-1510 | Team | Label "Off-topic / Ambiguous", custom prompt |

**After copying, check** (no org involved):
- The local compile gives 0 severity-1 errors.
- `grep -n "off_topic\|Test copy\|CARES_Router_V2" CARES.agent` finds nothing.
- `git diff 735e77a -- CARES.agent` shows changes only in the blocks marked above. In particular, the three unchanged subagents and `connection messaging` show no diff.
- No `description` is longer than 255 characters (the check in ROUTER_REDESIGN_SPEC D4).

## 4. Tests

### 4.1 Scenario expectations that must change

`run_batch.py` checks `path` as an **ordered subsequence** (`run_batch.py:181`). So most expectations still hold under the new paths: the item path `refund > risk_detection > refund` still contains `risk_detection > refund`, and a delivery path still contains `stolen_delayed_orders`. These are the ones that break, worked out from the new graph:

| Scenario | Today's `expect.path` | New path | Change to |
|---|---|---|---|
| B-RD-06 (email only, #49) | `risk_detection > identify_customer > refund > risk_detection > refund` | `refund > risk_detection > identify_customer > risk_detection > refund` | that new path |
| B-SM-03, B-RF-16 (no contact) | `risk_detection > refund > identify_customer` | `refund > risk_detection > identify_customer > risk_detection > refund` | `risk_detection > identify_customer > risk_detection > refund` |
| B-PO-02 (safety mid-refund) | `refund > urgent_escalation` | `urgent_escalation > escalate_to_human` (safety route) | `urgent_escalation` |
| B-RT-05 | `off_topic` | `ambiguous_question` | `ambiguous_question` |
| B-ER-01, B-ER-02, B-ER-03, B-ER-06 (rating) | `… experience_rating` | Rating only follows a finished issue plus a closing message (`WRAP_UP`) | Check each one's turns include the closing message. Add one if not |
| B-IN-01 | `risk_detection > refund > stolen_delayed_orders` | Depends on the first message: item → `refund…`; whole order → `risk_detection > stolen_delayed_orders` | Re-read the scenario, then set the path for its first message |

Every other path expectation (about 60 across the four files) stays as it is.

The P0 run on `CARES_Router_V2` (section 4.3) confirms this list. A scenario that fails only on a path not listed here is a finding for the review, not something to fix silently.

### 4.2 New scenarios

Add these to `p1-router.json` and `p0.json`. They come from ROUTER_REDESIGN_SPEC: A4 (two issues in one chat), B3 (email-identified PATTERN_REVIEW, re-ask cap), C4 (G-087 "never showed up" / "50 minutes late" reach S&D), D5 (the A6 message set, the G-088 safety cases, G-094, G-095) and E6 (Pronto question then "thanks" → rating).

Add one more for R-D10: **a logged-in "one item in my last order was missing"** must reach `refund` with no order-number question and `find_order` with a blank number. That's the regression the first draft test showed.

### 4.3 Evidence before the port: CARES vs CARES_Router_V2, P0, 1 run each, live actions, team org

| Agent | PASS | FAIL | Other |
|---|---|---|---|
| `CARES` (main with the G-112 fix, before #49) | 63 | 5 | 2 UNEXPECTED_PASS, 1 EXPECTED_FAIL, 1 N/A, 1 not run (runner crash, fixed on this branch) |
| `CARES_Router_V2` | *to fill in when the run ends* | | |

The 5 baseline failures:
- **B-PO-02 and B-PO-05:** guard topic chosen for a safety report (G-088).
- **B-RF-01, B-RF-02 and B-RF-20:** Refund offered 0. B-RF-01 and B-RF-02 are G-108: the fixture order already has a refund. B-RF-20 is to be checked.

For the comparison, split the test agent's failures into **path-only** (section 4.1) and **outcome changes** (amounts, actions, escalations, what the customer was told). Only outcome changes block the port.

## 5. Release

A person does this, under CLAUDE.md and CONTRIBUTING.md. Confirm the org at every step.

1. **Before the PR merges:**
   - `sf agent validate authoring-bundle --api-name CARES -o team-pronto --json`.
   - Every Flow the agent calls is `Active` in the repo (G-075). Otherwise the draft won't even start a preview, as happened with `CARES_Get_Customer_Context`.
2. **Agent user:** assign `CARES_Risk_Context_Access` if it's still missing (D-095 checklist, step 4). The planner checks every action at startup, so a missing permission fails the whole agent.
3. **Draft:**
   - Deploy the bundle: `sf project deploy start --metadata AiAuthoringBundle:CARES`. This is the draft only; v8 stays Active.
   - Run P0 on the draft: `run_batch.py --org team-pronto` (default bundle `CARES`), with `--burned` set to the orders that already have a refund. Compare with section 4.3.
4. **Publish v9, then activate.** Smoke test on v9 with `--api-name`: "Hi", one item problem, one "never arrived".
5. **Rollback:** `sf agent activate --api-name CARES --version 8 -o team-pronto`.
6. Record v9 in `DEPLOY_CHECKLIST.md` (same format as the v8 record).

## 6. After the release

- **Remove the test agent:** delete `aiAuthoringBundles/CARES_Router_V2/` from the repo, and its draft from the org. A person confirms, because it's a destructive operation. Also delete the `--bundle CARES_Router_V2` example from the runner docstring.
- **DECISIONS.md:** R-D1 to R-D10 become D-rows, with the amendments listed in ROUTER_REDESIGN_SPEC section R.
- **GAPS.md:**
  - Close G-047, G-087, G-094 and G-095 when their scenarios pass on v9.
  - Update G-088 with the safety-route result.
  - Keep G-065 open: email identity treated as verified is for the demo only (R-D7).
- **Subagent docs and SPEC.md:** the list in ROUTER_REDESIGN_SPEC "Docs".
- **Part F** (rename S&D to Delivery Exceptions) stays a separate change.

## 7. Risks

- **Seeds not run.** Without them, S&D's GPS and driver rules and the retention bonus behave as before. The port doesn't depend on them, but results won't show those paths.
- **Mock telemetry is ON** (`Mock_Telemetry_Enabled__c`, G-110).
- **The live chat transfer can't be tested in preview.** `WRAP_UP` after an escalation is only reachable without a transfer (R-D4).
- **Test data:** live-action runs use up fixture orders. Pass `--burned`, and prefer customers outside the pools P0 uses for demos (both runs on 2026-10-22 shared the team org).
- **Concurrent changes:** if another PR touches `CARES.agent` before this port merges, redo section 3's diff review against the new `main`, and re-check that Risk Detection hasn't regained a forced `REFUND` task.
