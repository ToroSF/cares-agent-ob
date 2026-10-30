# Demo walkthrough: geofencing, experience rating and risk detection

A live script for the panel, about 14 minutes. It walks through the CARES agent and shows three things, each as a "before vs after" with the same customer where possible:

1. **Geofencing** (Stolen & Delayed): the delivery map, the trip geofence and where the driver marked the order delivered (D-097, D-105, D-107).
2. **Experience rating:** the same customer, before and after a bad rating (D-095, D-102).
3. **Risk detection:** the same customer, before and after a history of complaints, plus a **scam alert** to the team (D-025, D-062, D-086).

Rehearsed on 2026-10-30 against agent v17 in the team org (`TEST_PLAN.md`). The amounts and the customer replies quoted below come from that rehearsal. The model's wording varies between runs; the amounts and the path do not.

The customers are test fixtures from `scripts/testing/fixtures.json` (mock data, `example.com` emails). The agent is English only, so the customer's lines are in English.

## Before the demo (30 minutes before)

1. **Agent:** CARES **v17 or later** is active (Setup → Agentforce Agents → CARES).
2. **Map links:** `scripts/apex/setup-delivery-map-link.apex` has run, and the site domain is a Trusted URL (`DEPLOY_CHECKLIST.md`, G-139). If not, the map link shows as `URL_Redacted`.
3. **Customer state.** Check each demo customer on their Contact record.

   | Act | Customer (email for the chat) | Must be |
   |---|---|---|
   | 1 | Jeffrey Valentine `jeffrey.valentine@example.com` | No refund on `PR-240824-HE7TUW7`; telemetry row `GPS_MISMATCH` |
   | 2 | Giacopo Maryet `giacopo.maryet@example.com` | No open customer context, no rating, no refund |
   | 3 | Geoff Wyllt `geoff.wyllt@example.com` | No Cases in the last 30 days (risk CLEAN), no refund |
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
**Customer:** Giacopo Maryet (order: Milkshake, Chips and Quinoa Bowl).

**Before**, new incognito chat:
1. **Customer:** "My order arrived but the Milkshake was missing." Then `giacopo.maryet@example.com`, and confirms the order.
2. **CARES:** a refund of **$12.53** or store credit of **$13.78**.
3. **Customer:** "I don't want either option. Please close this issue."

   CARES repeats the options once and offers to close (G-132). Then **Customer:** "That's all, thanks."
4. **CARES:** "Did I resolve your issue today? Please let me know by clicking thumbs up or thumbs down."
5. **Customer** clicks **👎** and writes: "This is the second time this happens, I'm really frustrated."
6. **Show** the Contact → CSAT Ratings (score 2, CARES's own summary), and its customer context (FRUSTRATED, open).

**After**, new incognito chat:
1. The same opening: "My order arrived but the Milkshake was missing."
2. **CARES** starts with one empathetic sentence (for example "It looks like things haven't gone smoothly with your order, and I understand how frustrating that can be."), then a refund of **$13.16** or credit of **$14.47** (+5%).

**Say:** "CARES formed its own reading of the conversation, not just the thumbs. The next time, it acknowledges the experience and the offer goes up 5%. The model chose the sentence, not the amount: the 5% is a field CRM users set per tier. A thumbs up later closes it; otherwise it expires after 30 days."

**Plan B:** the context opens only when the model reads the chat as NEGATIVE or FRUSTRATED. If it reads it as NEUTRAL, there is no sentence and no bonus. Then show the "after" with **Boyce Antrag** (`boyce.antrag@example.com`), whose context is already open. In the rehearsal his reply was "It looks like things haven't gone smoothly…" with a refund of **11.12 USD** for the missing Cookie.

## Act 3: Risk detection, the same customer (4 minutes)
**Customer:** Geoff Wyllt (Explorer tier; order: Herbal Tea, Side Salad and Soda, $38.70).

**Before**, a clean history:
1. **Customer:** "Hi, my order arrived but all the items were wrong." Then `geoff.wyllt@example.com`, and "Yes, it's that order. All three items were wrong."
2. **CARES:** a refund of **$35.00** or store credit of **$38.50**. That is the clean-history ceiling for Explorer.
3. Don't choose. Close the chat.

**Live, on Geoff's Contact record:**
- **Say:** "Let's say Geoff complained twice this month."
- Create **2 Cases**: Type *Customer Order Issue*, Status *Closed*, Subject *"Demo history 1"* and *"Demo history 2"*.

**After**, new incognito chat, the same messages:
- **CARES:** a refund of **$25.00** or credit of **$27.50**. That is the standard ceiling, because the history is no longer clean.

**Then**, a third Case (*"Demo history 3"*) and a new chat with the same message:
- **CARES** makes no offer: a member of the team will review it, and here is the case number. The case is in the CARES Escalations queue (PATTERN_REVIEW, reason "Repeated issues in the last 30 days").

**Say:** "Risk Detection is a silent check before every money step. It counts real complaints in the last 30 days, not what the customer claims. Zero gets the clean-history limit, one or more the standard limit, three or more a person before any offer. CARES's own escalations and payouts don't count against the customer."

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
| 3 | The amount didn't drop | The Cases are not linked to Geoff, or are older than 30 days | Check the Contact field on the Cases |
| 3b | No Slack message | Slack mode is `OFF`, or the webhook failed | Show the bell and the case; "the alert layers are independent" |
| Any | "Sorry, I can't assist with that" | The platform content guard (G-088) | Rephrase without words like "hacked" or "scam" |
| Any | "Something has gone wrong" | The org-level throttle (G-090) | Wait a minute, retry in a new chat |

## After the demo (reset)
1. **Geoff:** delete or close the three "Demo history" Cases, or clear their Contact. He is CLEAN again.
2. **Giacopo:** to close his customer context, give a 👍 in a new chat, or set `Has_Open_Context__c` to false on his CARES Customer Context record. Otherwise it expires in 30 days.
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
