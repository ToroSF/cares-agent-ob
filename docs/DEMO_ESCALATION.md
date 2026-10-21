# Demo: an escalation that lands

A live script for the panel, about 3 minutes. It shows that a person gets the case, the alert and the chat, and that the customer does not repeat anything (SPEC: "the customer never has to repeat themselves"). Design: [subagents/escalate-to-human.md](subagents/escalate-to-human.md).

## Before the demo (the morning of)
1. CARES with this branch is the active version. Check with `sf agent preview` that an escalation reply has a case number.
2. The setup script has run: the four presenters are in `CARES_Support_Team`, have Service Cloud User and the presence permission set.
3. The person who answers the chat opens the Service Console and sets Omni-Channel to **Available**.
4. Slack: `CARES_Alert_Setting__mdt.Default` is `BOT` or `WORKFLOW`, and the channel is open on the shared screen. Send one test escalation and check that `Case.CARES_Alert_Status__c` says `Slack: Sent`.
5. Salesforce mobile app signed in on one phone, notifications on.
6. A signed-in demo customer on the website chat (`CARES_Web`). Use a fixture from `.claude/skills/cares-testing/personas.md`.

## Three screens
| Screen | Who | Shows |
|---|---|---|
| Website chat | Presenter as the customer | What the customer sees |
| Slack channel | Shared | The alert |
| Service Console, Omni-Channel | A teammate as the support person | The chat arriving, with the case |

## Script
1. **Customer:** "My son is having an allergic reaction to the order I just got."
2. **CARES** (one reply): sorry, get medical help now, case number, the team is treating it as urgent. In a real chat the platform then shows "Connecting you with a member of the Pronto support team now. Please stay in this chat."
3. **At the same time:**
   - Slack: a red **URGENT** message with `@here`, the case number, the reason `SAFETY`, the order, and the "Open case" and "Open conversation" buttons. No name or email.
   - The phone gets a push: "URGENT: CARES case 0000xxxx".
   - Omni-Channel rings in the console.
4. **Support person** accepts the chat. The case is linked to the conversation; its Description has the summary (category, order, what CARES checked, what was offered).
5. **Support person** writes to the customer without asking for the order or the story again.
6. **Say to the panel:** the model only wrote the sentence. The case, the reason code, the alerts and whether a transfer happens are all decided by script and Flow (D-083 to D-086).

## If something fails live
| Failure | What still works | What to say |
|---|---|---|
| Nobody accepts in Omni | The case is in the queue, Slack and the bell are sent | "When nobody is online the chat waits; that is G-102" |
| Slack does not post | The bell and the case. `CARES_Alert_Status__c` shows why | "The alert layers are independent, here is the recorded failure" |
| The website chat fails | Run the same message in `sf agent preview` on the active agent: the reply has the case number, no transfer (D-084) | "Outside a real chat there is no session to transfer, so CARES gives the case number" |

## After the demo
Close the demo cases or leave them; they are mock data. Set the Slack mode back to `OFF` if the channel is shared with other teams.
