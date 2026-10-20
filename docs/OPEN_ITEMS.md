# Open items after merging Risk Detection, Experience Rating and Stolen & Delayed Orders

Status date: 2026-10-19. All three subagent PRs (#1 Risk Detection, #2 Experience Rating, #3 Stolen & Delayed Orders) are merged into `main`. This file lists what is still missing to call CARES done, and the connections between subagents that exist in the code but are not yet backed by real infrastructure (org config, metadata, or a deploy). Each row is tagged with the GitHub username whose subagent scope it falls under, so the right person picks it up. Cross-cutting items are tagged `Team` or `Merger` per the ownership rules in `CONTRIBUTING.md`.

This file does not replace `GAPS.md` or `DECISIONS.md` — it is the merge-time checklist. Items already tracked there are referenced by ID instead of repeated.

## 1. Subagents not yet built

| Item | What's missing | Tag | Related |
|---|---|---|---|
| Refund | **Built with stubs on `feature/refund-subagent` (PR #5)**: reads `risk_status` and the Stolen & Delayed context (D-028 to D-032); owner confirmed (D-027). Was: still the original placeholder. Did not read `risk_status`, `stolen_delayed_full_refund_approved`, `stolen_delayed_loss_absorption`, `stolen_delayed_driver_compensation`, `stolen_delayed_restaurant_reimbursement`, `stolen_delayed_customer_choice`, `stolen_delayed_order_total` or `stolen_delayed_currency` — all of this context is now computed and stored by Risk Detection and Stolen & Delayed Orders with nowhere to land. | **@lucasmpalomanes** — *inferred, not confirmed*: the only repo collaborator with no subagent PR open or merged so far. Team: please confirm or reassign in `DECISIONS.md`. | G-013 |

## 2. Connections wired in `.agent`/Apex but not backed by real org config

These are places where the code assumes something exists in the org that no PR has actually created. None of this blocks local compile or `sf agent validate authoring-bundle` — it will only surface at deploy or live-preview time.

| Item | Detail | Tag |
|---|---|---|
| Missing Named Credential `CARES_Delivery_Platform` | `CARES_StolenDelayedPlatformClient.cls` calls `callout:CARES_Delivery_Platform/v1`. No `.namedCredential-meta.xml` (or the External Credential it would need) exists anywhere in this repo. A deploy that includes this class will succeed (Apex doesn't validate callout targets at compile time), but any live call will fail at runtime with a callout exception the first time `evaluate_delivery_exception` or `handoff_approved_claim` actually runs. | **@rojasC10** |
| `CARES_Experience_Rating_Access` permission set not assigned | The permission set exists in the repo (by design — see `experience-rating-changelog.md`) but is assigned to no one. The Einstein Agent User running CARES currently has no grant on `CSAT_Rating__c`, so `CsatRatingSaver`'s `insert as user` will fail silently from the agent's point of view (`isSuccess = False`, generic `errorMessage`) the first time Experience Rating tries to save a rating. | **@ToroSF** (or whoever runs the final deploy — see `CONTRIBUTING.md`, "one person deploys... at the end") |
| `CARES_Get_Risk_Result` Flow: account-only branch unreachable | Already flagged as a PR review comment on #1, repeating here so it's visible at the repo level and not just in a closed PR's comment thread: `Get_Contact`, `Contact_Found`, `Has_Account`, `Only_Contact` have no incoming connector anywhere in the Flow. The D-013 account-only counting path never executes. Risk Detection can return `CLEAN` for a customer whose real issues are logged only against their Account. | **@Mateus-Goes** |
| Stolen & Delayed → Refund context has no consumer yet | `handoff_approved_claim` and `evaluate_delivery_exception` both set rich context (loss absorption, driver/restaurant compensation, customer choice, order total/currency) intended for Refund to read. Until Refund is built, this context is computed, stored in variables, and never used. Not a bug — just not wired end to end yet. | **@rojasC10** (producer) / **@lucasmpalomanes** (consumer: wired in PR #5, untested until the platform exists, G-032) |
| Risk Detection → Refund loop risk on Flow failure | G-020 (already in `GAPS.md`): if `get_risk_result` errors without setting `risk_status`, `risk_checked` can stay `False`, and Refund's `before_reasoning` sends the conversation back to Risk Detection — a possible loop. D-018 proposes gating on the action result instead of `risk_checked`, but that option is not built. | **@Mateus-Goes** |
| Nothing has been deployed to `cares-onboarding` since the three merges | The local `.agent`, the new Apex classes, the Flow, the custom metadata type, and the permission set are all validated locally (compiler + `sf agent validate authoring-bundle`) but a deploy of the merged `main` has not been run in this session. Per `CONTRIBUTING.md`, this is an explicit, single-owner step at the end, not a side effect of merging PRs. | **Merger** (whoever the team names for the end-of-week deploy, per `CONTRIBUTING.md`) |

## 3. Known risk-detection correctness gap (tracked in `GAPS.md`, repeated here for visibility)

G-010 / G-016: 1 of 5 account-only cases in the shared org still cannot be assigned to a single contact (the account has 3 contacts), so it stays invisible to Risk Detection even once the Flow wiring above is fixed. This needs a data fix at case creation, not a code fix. **Team** (no single owner — needs a data decision, see `GAPS.md` "Items the team will close together").

## 4. Suggested next step per owner

- **@Mateus-Goes**: reconnect the account-only branch in `CARES_Get_Risk_Result.flow-meta.xml` (`Has_Contact`'s "no direct contact" branch → `Has_Account` → `Only_Contact` → `Get_Account_Only_Cases` → `Loop_Account_Cases` → `Add_One_Account`), then update G-010/G-016/D-013's status in `GAPS.md`/`DECISIONS.md` once it's actually reachable. Also look at D-018 (gate on action result) to close G-020.
- **@rojasC10**: author the `CARES_Delivery_Platform` Named Credential (and External Credential if needed) as metadata in this repo, even if it points at a mock/sandbox endpoint for now — so the next deploy doesn't fail at the first live callout.
- **@lucasmpalomanes** (or Refund's actual owner, if different): build Refund to read `risk_status` (G-013) and the Stolen & Delayed context variables listed above, inside the existing `before_reasoning` gate pattern from D-015.
- **@ToroSF**: assign `CARES_Experience_Rating_Access` to the Einstein Agent User as part of (or right before) the next deploy, not silently bundled into it.
- **Merger**: once Refund is built and the Named Credential exists, run the end-of-week deploy sequence from `CONTRIBUTING.md` (validate → deploy → test → publish → activate) against `cares-onboarding`, and close out the "Deploying" gaps (G-014, G-015) with real evidence instead of local-only validation.
