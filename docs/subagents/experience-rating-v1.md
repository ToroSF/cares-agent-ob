# Experience Rating — v1 (baseline)

Snapshot of what shipped in commit `4c5c3a2` ("Implement Experience Rating
sub-agent (CSAT v1)"), before the grounding/guardrail/scalability hardening
pass. Use this to diff functionality as the sub-agent evolves.

## Scope

Capture-and-store only. No behavioral adaptation — Risk Detection (a separate
sub-agent, separate branch) is expected to consume this history later.

## Flow (as implemented)

1. CARES transitions to `experience_rating` automatically once a case is
   resolved (no explicit customer request needed).
2. The sub-agent asks the customer to rate the interaction 1-5 ("presented as
   a slider in the UI" — instruction text only; no LWC slider component
   exists yet in this repo).
3. If the customer declines or doesn't respond, the agent accepts that and
   ends the conversation. `save_csat_rating` is never called.
4. Once a score is given:
   - If score ≤ 3: the agent asks one optional open follow-up question about
     what could have gone better.
   - Regardless of the follow-up, the agent calls `save_csat_rating` exactly
     once with `contactId`, `score`, `comment` (comment may be blank).
5. After the action runs, the agent thanks the customer. The
   `csat_score_captured` variable gates the action so it cannot run twice in
   the same case.

## Data model (as implemented)

`CSAT_Rating__c` (ReadWrite sharing model):

| Field | Type | Required | Notes |
|---|---|---|---|
| `Score__c` | Number(1,0) | Yes | No validation rule enforcing 1-5 range at the schema level — only enforced in Apex. |
| `Comment__c` | LongTextArea(32768) | No | No security classification / compliance group set. |
| `Contact__c` | Lookup → Contact | Yes | `deleteConstraint: Cascade` — deleting the Contact deletes their CSAT history. |
| `Account__c` | Lookup → Account | No | `deleteConstraint: SetNull`. |
| `Interaction_Date__c` | DateTime | Yes | Set server-side to `Datetime.now()`; not passed from the agent. |

No `OwnerId`-based sharing considerations documented. No field-level
`securityClassification`/`complianceGroup` set on `Comment__c`, even though it
holds free-text customer-submitted content.

## Action implementation (as implemented)

`CsatRatingSaver.cls` — single `@InvocableMethod`:

- **Input validation:** rejects a request if `contactId` doesn't resolve to a
  real `Contact` (via a bulk `WITH USER_MODE` query), or if `score` is null or
  outside 1-5. Both return an `errorResult(...)` with no distinct error code —
  just a free-text `errorMessage`.
- **Insert:** `insert as user` (enforces the running user's object/field
  permissions and sharing rules).
- **No permission set** exists yet granting the Einstein Agent User access to
  `CSAT_Rating__c` — `insert as user` will silently rely on whatever access
  that user already has in the org; if it has none, the insert fails at
  runtime with a generic Apex error, not a clean agent-facing message.
- **No injection/confidentiality guardrail instructions** in the
  `experience_rating` subagent (unlike `off_topic` and `ambiguous_question`,
  which both carry an explicit anti-prompt-injection rule block) — despite
  this subagent being the one place in the agent that stores raw customer
  free text (`Comment__c`).
- **No explicit handling for a missing/empty `ContactId`** — the instructions
  assume `@variables.ContactId` (linked from `MessagingEndUser.ContactId`) is
  always populated. In a channel/session where it isn't, the agent would
  still ask for a rating and then fail silently inside Apex when it tries to
  save.
- **Failure messaging:** not explicitly specified in the agent instructions —
  there is no guidance for what to tell the customer if `isSuccess == False`.

## Known gaps going into the next pass

- No grounding safeguard preventing the model from telling the customer
  "your feedback has been saved" when the save actually failed.
- No guard for missing `ContactId` (anonymous/unauthenticated session).
- No anti-prompt-injection / confidentiality instructions on this subagent.
- No Permission Set wiring the Einstein Agent User to `CSAT_Rating__c`
  (object + field access) for production use.
- No schema-level validation rule constraining `Score__c` to 1-5 (Apex-only
  today).
- No `securityClassification`/`complianceGroup` tagging on `Comment__c`.
