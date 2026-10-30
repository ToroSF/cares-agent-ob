# Demo walkthrough: geofencing, experience rating and risk detection

A live script for the panel, about 14 minutes. It walks through the CARES agent and shows three things, each as a "before vs after" with the same customer where possible:

1. **Geofencing** (Stolen & Delayed): the delivery map, the trip geofence and where the driver marked the order delivered (D-097, D-105, D-107).
2. **Experience rating:** the same customer, before and after a bad rating (D-095, D-102).
3. **Risk detection:** the same customer, before and after a history of complaints, plus a **scam alert** to the team (D-025, D-062, D-086).

Rehearsed on 2026-10-30 against agent v17 in the team org (`TEST_PLAN.md`), act 2 and act 3 again after Giacopo's Milkshake chat and the history cases. The amounts and the customer replies quoted below come from that rehearsal. The model's wording varies between runs; the amounts and the path do not.

The customers are test fixtures from `scripts/testing/fixtures.json` (mock data, `example.com` emails). The agent is English only, so the customer's lines are in English.

## Before the demo (30 minutes before)

1. **Agent:** CARES **v17 or later** is active (Setup → Agentforce Agents → CARES).
2. **Map links:** `scripts/apex/setup-delivery-map-link.apex` has run, and the site domain is a Trusted URL (`DEPLOY_CHECKLIST.md`, G-139). If not, the map link shows as `URL_Redacted`.
3. **Customer state.** Check each demo customer on their Contact record.

   | Act | Customer (email for the chat) | Must be |
   |---|---|---|
   | 1 | Jeffrey Valentine `jeffrey.valentine@example.com` | No refund on `PR-240824-HE7TUW7`; telemetry row `GPS_MISMATCH` |
   | 2 | Giacopo Maryet `giacopo.maryet@example.com` | Customer context **open (FRUSTRATED)** from his bad Milkshake experience; no refund on `PR-240628-7FEN2KY` |
   | 3 | Geoff Wyllt `geoff.wyllt@example.com` | Risk CLEAN: run `scripts/apex/demo-risk-stage.apex` with `STAGE = 0`. No refund |
   | 3b | Bruce Clemendot `bruce.clemendot@example.com` | Telemetry row `FRAUD` on `PR-240827-HQ2DT25` |

4. **Slack:** `CARES_Alert_Setting__mdt.Default` is `WORKFLOW` (or `BOT`), and `#cares-escalation` is open.
5. **Tabs:**
   - the website chat in a **new incognito window**, one per act;
   - Slack;
   - CARES Admin: Delivery Telemetry, Resolutions;
   - the four Contact records;
   - the Service Console with the CARES Escalations queue, and the bell.

## Screens

| Screen | Who | Shows |
|---|---|---|
| Website chat (incognito) | Presenter as the customer | What the customer sees |
| Delivery map page | Opened from the chat link | The result band and the real map (Google Maps) |
| CARES Admin / Contact record | Presenter | What CARES saved, and the customer's history |
| Slack `#cares-escalation`, bell, queue | Shared | What the team gets |

## Opening (1 minute)
- **Say:** "Today a complaint becomes a ticket and a 3-to-5-day wait. CARES answers in the chat, in minutes. The model writes the words; every decision about money, risk and data is code we can test. Three things show that: where the driver really was, how CARES remembers a bad experience, and how it treats a customer with a history."

## Act 1: Geofencing (3 minutes)
**Customer:** Jeffrey Valentine.

1. **Customer:** "My order says delivered but I never got it."
2. CARES asks for the email (the site chat starts as a guest). **Customer:** `jeffrey.valentine@example.com`, then confirms the order (Caesar Salad and Iced Tea).
3. **CARES** (one reply): apologises; offers the full **18.10 USD** as a refund, or app wallet credit worth a little more; and adds:
   > View your delivery map (valid for 30 minutes): https://…/delivery-map?t=…
4. **Open the link.** The page shows "Order PR-240824-HE7TUW7 · $18.10" and a pink band: **"GPS mismatch · the driver marked the order delivered 2.2 km from the centre of the trip"**. Below it is the real map (Google Maps), with:
   - the orange circle (the trip geofence);
   - Restaurant and Drop-off;
   - the driver's marker, outside the circle.
5. **Optional contrast:** CARES Admin → Delivery Telemetry → `INSIDE_NEAR_RESTAURANT` (Peyton Batrick). There the band is green, "GPS match", and the driver's marker sits right next to the restaurant, inside the circle.

**Say:**
- "The geofence is a circle around the middle of the trip, half the trip plus 50 metres. The driver marked this order delivered 2.2 km from the centre, so CARES pays the customer in full and holds the driver's pay. The model never sees these numbers; the policy in Apex decides, and the band and the circle on the map come from the same calculation."
- On the contrast: "Our honest limit: the restaurant end of the trip is inside too, so a driver who never left can pass (G-111)."
- "The link is signed and expires in 30 minutes. Change one character and the page shows nothing."

Don't choose an option if you want to reuse Jeffrey; see *After the demo*.

## Act 2: Experience rating, the same customer (3 minutes)
**Customer:** Giacopo Maryet. Tell it as a story: the "before" already happened, the "after" is live.

**Before (already happened, tell it):** Giacopo's Milkshake was missing from order `PR-240819-CNK6KC0` (GreenFork Bistro Uptown).
- CARES offered a refund of **$12.53** or credit of **$13.78**, with no special words, and paid the refund.
- At the end he gave a **👎** and wrote that he was frustrated.
- **Show:**
  - his Contact → **CSAT Ratings**: score 2, with CARES's own summary of the chat;
  - his **CARES Customer Context**: FRUSTRATED, open.

**After (live)**, new incognito chat. **Say the order number in the first message:**
1. **Customer:** "Hi, my order PR-240628-7FEN2KY from GreenFork Downtown arrived without the Brownie." Then `giacopo.maryet@example.com` if asked, and confirm.
2. **CARES** starts by acknowledging the bad experience. In the rehearsal: "I'm sorry your order didn't arrive as expected and the Brownie was missing. I know that's frustrating and things haven't gone smoothly for you recently."
3. Then a refund of **10.08 USD** or store credit of **11.09 USD**. The Brownie is worth $9.60: without the open context the offer would be $9.60 / $10.56.

**Say:** "Last time Giacopo left unhappy. CARES formed its own reading of that conversation, not just the thumbs. This time it acknowledges the experience, without naming any check or record, and the offer goes up 5%. The model chose the sentence, not the amount: the 5% is a field CRM users set per tier. A thumbs up later closes it; otherwise it expires after 30 days."

**Watch out:**
- **The order number must be in the first message.** Otherwise CARES picks his most recent order, the Milkshake one, which was already paid, and says the item isn't on it.
- **Don't confirm the refund** if you want to reuse the order. Backup order: `PR-240611-6QRT0D6`, "the Smash Burger was missing", which gives **14.01 USD** (instead of $13.34).

**Plan B:** if Giacopo's context has expired, run the "before" live first:
1. a missing item on one order;
2. decline: "I don't want either option. Please close this issue";
3. "That's all, thanks";
4. 👎 with a frustrated sentence;
5. then the "after" on another order.

The context opens only if the model reads the chat as NEGATIVE or FRUSTRATED. If it reads NEUTRAL, use **Boyce Antrag** (`boyce.antrag@example.com`), whose context is already open: "my order PR-240826-B9FGO67 arrived without the Cookie" gives the sentence and **11.12 USD**.

## Act 3: Risk detection, the same customer (4 minutes)
**Customer:** Geoff Wyllt (Explorer tier; order `PR-240825-QN0SODC`: Herbal Tea, Side Salad and Soda, $38.70). His relationship with Pronto gets worse, complaint by complaint.

The three earlier complaints exist in the org, unlinked: Cases `Demo history 1`, `2` and `3`. `scripts/apex/demo-risk-stage.apex` links them to Geoff (set `STAGE`, then `DRY_RUN = false`).

| Case | When (story) | Priority | What happened |
|---|---|---|---|
| Demo history 1: one item missing | 3 weeks ago | Low | Side Salad missing. Polite: "No big deal, just letting you know." |
| Demo history 2: wrong order, second time | 9 days ago | Medium | Someone else's order. Annoyed: "This is the second time this month." |
| Demo history 3: late and cold, threatens to leave | 2 days ago | High | 50 minutes late and cold. Angry: "One more and I'm switching apps." |

**Before** (`STAGE = 0`, a clean history):
1. **Customer:** "Hi, my order PR-240825-QN0SODC arrived but all the items were wrong." Then `geoff.wyllt@example.com` if asked, and "All three items were wrong."
2. **CARES:** a refund of **$35.00** or store credit of **$38.50**. That is the clean-history ceiling for Explorer.
3. Don't choose. Close the chat.

**After** (`STAGE = 2`): show Geoff's Contact with complaints 1 and 2 (the polite one, then the annoyed one).
- A new incognito chat with the same messages gives a refund of **$25.00** or credit of **$27.50**. That is the standard ceiling, because the history is no longer clean.

**Then** (`STAGE = 3`): show complaint 3 ("one more and I'm switching apps").
- A new chat with the same message gets **no offer**: CARES says the support team will review it and gives the case number. If an earlier demo left Geoff's escalation case open, CARES adds to it instead of opening a new one; close old demo escalations first for a fresh number.
- The case is in the CARES Escalations queue: PATTERN_REVIEW, "Repeated issues in the last 30 days, a person reviews before any offer".

**Say:** "Risk Detection is a silent check before every money step. It counts the customer's real complaints in the last 30 days, not what they say in the chat. A clean history gets the higher limit. Once there are complaints, the standard limit. At three in a month, CARES stops automating and puts a person on it, because this customer is about to leave and deserves a human. CARES's own escalations and payouts don't count against the customer."

Never confirm a payout in this act. Reset with `STAGE = 0`.

## Act 3b: Scam alert (2 minutes)
**Customer:** Bruce Clemendot (`PR-240827-HQ2DT25`; his delivery data carries a fraud flag).

1. **Customer:** "My order says delivered but I never got it." Then `bruce.clemendot@example.com`, and confirms the order.
2. **CARES:** "Thank you for letting us know — this sounds frustrating. Your support case number is 0000xxxx. The support team already has your details, so you will not need to repeat anything…"
   - No offer.
   - No mention of fraud.
   - No blame.
3. **Show:**
   - the case in the CARES Escalations queue (*Stolen & Delayed check: ESCALATE (FRAUD_SIGNAL)* in its description);
   - the **bell** notification;
   - the message in **#cares-escalation**: case number, reason and order, with no name or email.

**Say:** "CARES never accuses the customer. The fraud signal stops the automatic refund and puts a person on it, with the context, at once."

**Note:** today this alert is the yellow "🟡 New escalation" (claim review). Making fraud red "🔴 URGENT" is a one-line change in the Stolen & Delayed block, not done yet. Don't say "urgent" unless it's done.

## Closing (1 minute)
- **Say:** "We'd prove this in a 12-week pilot split by customer (`PILOT_PLAN.md`): reorder after a complaint, payouts inside policy, share resolved without a person, and thumbs up. The data shown today is mock; the first two pilot weeks replace it with Pronto's."

## If something fails live

| Act | Failure | Likely cause | What to do / say |
|---|---|---|---|
| Any | The chat escalates at once with a case number | That customer was already paid (`DUPLICATE_CLAIM`) | Use the backup customer; "a repeat claim on a paid order always goes to a person" |
| 1 | The link shows as `URL_Redacted` | Site domain not in Trusted URLs (G-139) | Open the page from CARES Admin → Delivery Telemetry instead |
| 1 | The page says the link expired | Over 30 minutes, or a changed link | Ask again in the chat; "that's the signature at work" |
| 1 | No link in the reply | The agent version is older than v17 | Show the map in CARES Admin |
| 1 | The map area is blank | Google Maps blocked or slow on the site | Show the same record in CARES Admin; the band still gives the result |
| 2 | No empathetic sentence after the 👎 | The model read the chat as NEUTRAL | Plan B with Boyce Antrag |
| 2 | "That's all" repeats the offer | G-132 | Say "I don't want either option, please close this issue" first |
| 2 | "I don't see a Brownie on this order" | The order number wasn't in the first message, so CARES used his latest order | Start a new chat with the number in the first message |
| 3 | The amount didn't drop | The script didn't write (`DRY_RUN = true`) or the Cases aren't on Geoff | Rerun with `DRY_RUN = false`; check the Cases' Contact |
| 3b | No Slack message | Slack mode is `OFF`, or the webhook failed | Show the bell and the case; "the alert layers are independent" |
| Any | "Sorry, I can't assist with that" | The platform content guard (G-088) | Rephrase without words like "hacked" or "scam" |
| Any | "Something has gone wrong" | The org-level throttle (G-090) | Wait a minute, retry in a new chat |

## After the demo (reset)
1. **Geoff:** run `scripts/apex/demo-risk-stage.apex` with `STAGE = 0`. The three Cases stay in the org, unlinked, so he is CLEAN again.
2. **Giacopo:** leave his customer context open for the next demo. It expires 30 days after his 👎. To close it, give a 👍 in a new chat. Delete the Resolution of any order he was paid for in the demo (keep `CARES-RES-00068`, the Milkshake: it is part of his story).
3. **Anyone who was paid:** delete their row in CARES Admin → Resolutions. Otherwise the next claim on that order goes to a person, and their claim rate rises.
4. **Escalation cases** from the demo: close them; they are mock data.
5. **Telemetry:** only if a profile was moved, rerun `scripts/apex/seed-delivery-telemetry.apex` (DRY_RUN first).

## Likely panel questions

| Question | Short answer |
|---|---|
| "Is the GPS data real?" | Mock telemetry in Salesforce (D-096, G-110): it shows the rule works, not that a real driver was at fault |
| "Couldn't a driver cheat the geofence?" | Yes, near the restaurant (G-111). We show it on purpose; a second check on the restaurant end is the fix |
| "Why show the customer the map at all?" | Only for approved claims, as evidence in their favour; it never shows for a claim still under review (R-18) |
| "Does the map send data to Google?" | Yes (G-136, D-108). Fine with mock data; a privacy review before real drivers |
| "Can a customer get a bigger refund by saying they're upset?" | No. The rating is CARES's own reading, the 5% is policy, and NOT_CLEAN customers never get it |
| "Who decides the amounts?" | The policy table in code (D-004). In testing, 65 of 65 payouts stayed inside policy |
| "What if a loyal customer just had a bad month?" | Three complaints in 30 days gets a person, not a refusal (D-062) |
