# Node spec: Escalate to Human

How the Escalate to Human subagent and its hand-off work, as built on `feature/escalation-handoff`. For the why, read D-083 to D-087 in [../DECISIONS.md](../DECISIONS.md). Gaps: G-086, G-082, G-068 (and G-064, G-093, G-095, G-098). Owner: @Mateus-Goes.

State: built, compiled locally with no errors, `sf agent validate` passes, check-only deploy passes (94 components, 122/122 tests after the rebase onto `main` (PR #36 to #38), `CARES_EscalationAlerts` 95% coverage). **Not deployed yet.** Last updated: 2026-10-21.

## In one paragraph
When CARES cannot or must not finish a request itself (a safety report, repeated issues, a claim review, a failed step, a dispute, or a customer asking for a person), Escalate to Human logs one case with a fixed summary, tells the customer the case number and what happens next, and alerts the support team. In a real website chat it also transfers the chat to a person in Omni-Channel. The customer never has to repeat themselves, and the person never has to read the whole transcript.

## Where it sits
```
Router / Refund / Stolen & Delayed / Risk Detection / Order Status / Pronto Help / Identify Customer
              |  transition (category and state already set)
              v
     Escalate to Human
        before_reasoning: reason code -> create_escalation_case (Flow)
              |                                   |
              | reply: empathy + case number      | Case insert (queue CARES_Escalations)
              | + next step                       v
              |                          CARES_EscalationCaseTrigger -> CARES_EscalationAlerts (Queueable)
              |                                   +--> Bell + mobile push to CARES_Support_Team
              |                                   +--> Slack message (CARES_Slack Named Credential)
              |
              +-- real chat only: @utils.escalate --> flow://CARES_Route_To_Support
                                                     links the case to the chat, routes to CARES_Support_Chat
```

## Node card
| Field | Value |
|---|---|
| Type | Subagent that talks to the customer |
| Entered from | Router `go_to_escalate_human`, Urgent Escalation, Risk Detection (PATTERN_REVIEW), and the hand-off actions of Refund, Stolen & Delayed, Order Status, Pronto Help and Identify Customer |
| Deterministic part | `before_reasoning`: sets `escalation_category` (CLAIM_REVIEW when Stolen & Delayed needs a person), sets `escalation_reason`, runs `create_escalation_case` once (again only for a first URGENT report) |
| Model part | One reply: an empathetic sentence, the case number, the next step. In a real chat, also calls `escalate_to_human_action` |
| Actions | `create_escalation_case` → `flow://CARES_Create_Escalation_Case`; `escalate_to_human_action` → `@utils.escalate` |
| Live transfer gate | `escalation_attempted == False` and `RoutableId` is set. `RoutableId` (the MessagingSession id) is set only in a real `CARES_Web` chat, never in preview or Agent API sessions (D-084) |
| Writes | `escalation_reason`, `escalation_case_attempted`, `escalation_case_created`, `escalation_case_number`, `escalation_logged_category`, `escalation_attempted`; clears `router_active_task` |
| Failure behavior | No case created → apologize, no case number, no promise that anyone will contact them |

## Reason codes (D-085)
Set by the script from the state, in this order. The first match wins.

| Code | When |
|---|---|
| `SAFETY` | Category URGENT (Urgent Escalation: food safety, illness, harassment, fraud, legal) |
| `REPEATED_ISSUES` | Category PATTERN_REVIEW (Risk Detection: issues at the review threshold) |
| `CLAIM_REVIEW` | Category CLAIM_REVIEW (Stolen & Delayed needs a person) |
| `IDENTITY_FAILED` | No customer account found |
| `ISSUE_FAILED` | Issuing the refund or credit failed |
| `CLAIM_FAILED` | The Stolen & Delayed hand-off was BLOCKED or FAILED |
| `ORDER_NOT_FOUND` | Three order checks with no match |
| `NOT_ELIGIBLE` | Refund said no offer can be made |
| `OFFER_DISPUTED` | An offer was made and the customer did not accept it |
| `CUSTOMER_REQUEST` | Anything else: the customer asked for a person |

An agent version without the code (v5) sends nothing; the Flow writes `NOT_GIVEN`.

## What the customer sees
| Situation | Reply |
|---|---|
| Preview, Agent API, or a chat without a session (most tests) | "I'm sorry this happened. Your support case number is 0000xxxx and the support team already has the details. They will review it and contact you." No transfer is offered |
| URGENT | Same, plus: get medical help now, call the local emergency number if it is serious, the team is treating it as urgent |
| Real website chat | The model writes the same reply and calls the transfer. The platform replaces the text with the fixed `escalation_message`: "Connecting you with a member of the Pronto support team now. Please stay in this chat." The person who joins sees the case number on the conversation |
| The case could not be logged | An apology, no number, no promise |

Escalate ends the turn and replaces the model's text (G-086). That is why the model says the case number in the same reply, and not "after the transfer fails" as before (D-083).

## What the person gets (the case, G-082)
The Flow writes the Description from variables only, never from free chat text (R-14). One fact per line:
```
Escalated by CARES. Internal only: never share the risk status with the customer.
Category: URGENT
Priority: High
Why: Safety, health, fraud or legal report (SAFETY)
Customer: Verified (signed in to the chat)
Order: PR-250812-0LNZ2JM
Stolen & Delayed check: not run
Risk status (internal): CLEAN
Offer: none made
Customer chose: nothing confirmed
Chat: messaging session 0Mw... (live chat, transfer requested)
Next step: Contact the customer now. Safety first: no offer before a person reviews.
```
The case also gets `AccountId` from the contact, `CARES_Escalation_Reason__c` and `CARES_Messaging_Session_Id__c`. A second escalation for the same open issue adds the same block as a private comment instead of a new case (D-063).

## Who is told, and how (G-068, D-086)
Each layer works without the others, and none can change the reply to the customer: they start after the case is saved.

1. **Queue members.** The public group `CARES_Support_Team` (the four team admins) is a member of `CARES_Escalations` (cases) and `CARES_Support_Chat` (chats). Members are added by `scripts/apex/setup-escalation-team.apex`.
2. **Bell and mobile push.** Custom notification `CARES_Escalation_Alert` to the group, with the case as target. The title starts with "URGENT:" for High priority.
3. **Slack.** One Block Kit message per case: red and `<!here>` for URGENT, yellow otherwise, with the case number, priority, reason code, order and the buttons "Open case" and "Open conversation". **No name, email, phone or risk status** (D-087). The mode is set in `CARES_Alert_Setting__mdt.Default`: `OFF`, `BOT` (Slack app, `chat.postMessage`) or `WORKFLOW` (Workflow Builder webhook). The token or webhook URL lives only in the Named Credential `CARES_Slack` in the org.
4. **Live chat (real `CARES_Web` sessions only).** `@utils.escalate` calls the routing Flow `CARES_Route_To_Support`. It finds the case by the session id (or the contact's open CARES case when an old case was reused), links it to the MessagingSession, and routes the chat to the `CARES_Support_Chat` queue on the Messaging channel. A lookup problem still routes the chat: a person without the case is better than no person.

The result of the bell and Slack is written to `Case.CARES_Alert_Status__c`, for example `Bell: Sent | Slack: Failed: not_in_channel`. A blank value means the job never ran.

## Known limits
- When nobody is online in Omni-Channel, the chat waits in the queue (G-102). The case and the alerts still reach the team.
- The case-not-logged branch is covered by the instructions and by the Flow's fault paths, not by a live test: the Flow cannot be made to fail on demand.
- Slack needs a manual setup step in the org and in Slack ([../DEPLOY_CHECKLIST.md](../DEPLOY_CHECKLIST.md)). Until then the mode stays `OFF` and the bell still works.

## Tests
- Apex: `CARES_EscalationCaseFlowTest` (summary lines, account, reason, session, reuse comment, unknown customer) and `CARES_EscalationAlertsTest` (urgent and normal message, no personal data, HTTP 404, `ok:false`, timeout, workflow mode, off, no channel, non-CARES cases get no alert).
- Scenarios: B-ES-01, B-ES-06, B-ES-10, B-PO-01, B-PO-03, B-PO-06, B-SD-01 and B-AD-16 fail on the placeholder "User requested escalation" and need a case number in the reply. B-CX-05 fails on the placeholder.
- Live demo: [../DEMO_ESCALATION.md](../DEMO_ESCALATION.md).
