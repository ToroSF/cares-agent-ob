# Socratic question patterns

Mentor rules:
- **Ask, don't tell.** One theme per question.
- **Ground it:** quote the member's own artifact (a decision, gap, risk, PR or file), and ask for a two-sentence answer.
- **Frame it:** use the C-suite role most likely to ask it.
- **Don't compare** members, and don't reveal anyone else's score.

Fill `{…}` from the evidence JSON. Prefer the weakest lines first.

## Use Case & Business Framing
- "You built {artifact}. If {CFO|CRO} asks which KPI it moves, what do you say in two sentences?"
- "Which executive in the room cares most about {artifact}, and why them?"
- "How would a 30-day pilot show that {artifact} kept customers, not just saved cost?"

## Configure
- "In {decision} you chose {X} over {Y}. What would {Y} have cost you, and would {CTO} agree?"
- "Which part of {subagent} is decided by code and which by the model? Why that split?"
- "If you rebuilt {subagent} tomorrow, what would you structure differently?"

## Ground
- "Where does {subagent} get {fact} from, and how did you check it was right?"
- "{gap} says {data limit}. How would you admit that to {CIO} without losing the room?"
- "Give one number that proves {source} is trustworthy. Where can the panel see it?"

## Risks & Safeguards
- "What failure does {safeguard} prevent, and what does it *not* catch?"
- "{risk} is open. If {CTO} asks what happens when it fires in production, what do you say?"
- "A customer types someone else's email. Walk {CRO} through what happens next."

## Recommended Approach
- "{gap} was fixed. How do you know the fix works, and where is the evidence?"
- "{gap} is still open. Why was it deferred, and what does it cost to leave it?"
- "Your last test run is on {version}; the org runs {version}. How do you answer {CTO}?"

## Justification & Strategic Communication
- "Explain {decision} to {CFO} as decision, why, and what we gave up, in three sentences."
- "Which of your decisions would you defend hardest in the panel, and which would you change?"
- "Tie {artifact} back to business value in one sentence a non-technical executive repeats."

## Follow-up (when an answer is partial)
Ask the missing check only:
- **Not clear** → "Say it again in two sentences for {role}."
- **No value** → "So what does that mean for {KPI}?"
- **No trade-off** → "What did you give up for that?"
- **No evidence** → "How would the panel check that?"
