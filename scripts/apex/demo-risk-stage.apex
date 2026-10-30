// Demo walkthrough, act 3 (docs/DEMO_WALKTHROUGH.md): a customer's relationship getting worse, case by case.
// Three different earlier complaints, each worse than the last, so Risk Detection moves the same customer from
// CLEAN (clean-history limit) to NOT_CLEAN (standard limit) to PATTERN_REVIEW (a person before any offer, D-062).
//   sf apex run --file scripts/apex/demo-risk-stage.apex --target-org <team org>
// Set STAGE, then run:
//   0 = reset: none of the cases is linked to the customer (CLEAN, the "before" of the demo)
//   1 = the first complaint is linked (NOT_CLEAN)
//   2 = the first two (NOT_CLEAN, the "after")
//   3 = all three (3 issues in 30 days: PATTERN_REVIEW, a person reviews)
// The cases are created once and kept between demos. Stage 0 only clears their contact, so they never count
// for anyone. They are Closed, Type "Customer Order Issue" (counted by CARES_Get_Risk_Result), not CARES
// escalations. They are created today, so they are inside the 30-day window; the story's timeline (3 weeks,
// 9 days, 2 days ago) is in each description. Mock data only.
// DRY_RUN = true prints what it would do and changes nothing.

Boolean DRY_RUN = true;
Integer STAGE = 0;
String CUSTOMER_EMAIL = 'geoff.wyllt@example.com';

// Oldest first: the relationship gets worse with each one. [subject, priority, days ago, description]
List<List<Object>> HISTORY = new List<List<Object>>{
    new List<Object>{
        'Demo history 1: one item missing',
        'Low',
        21,
        'The Side Salad was missing from the order. The customer was polite: "No big deal, just letting you know." Resolved with an apology.'
    },
    new List<Object>{
        'Demo history 2: wrong order, second time',
        'Medium',
        9,
        'Received someone else\'s order. The customer was annoyed: "This is the second time this month." Asked for a full refund.'
    },
    new List<Object>{
        'Demo history 3: late and cold, threatens to leave',
        'High',
        2,
        'Arrived 50 minutes late and cold. The customer was angry: "Third problem in a month. One more and I\'m switching apps."'
    }
};

List<Contact> customers = [SELECT Id, Name, AccountId FROM Contact WHERE Email = :CUSTOMER_EMAIL LIMIT 1];
if (customers.isEmpty()) {
    System.debug(LoggingLevel.WARN, 'No contact with the email ' + CUSTOMER_EMAIL);
    return;
}
Contact c = customers[0];
Map<String, Case> existing = new Map<String, Case>();
List<String> subjects = new List<String>();
for (List<Object> h : HISTORY) {
    subjects.add((String) h[0]);
}
for (Case k : [SELECT Id, Subject, ContactId FROM Case WHERE Subject IN :subjects]) {
    existing.put(k.Subject, k);
}

List<Case> toSave = new List<Case>();
for (Integer i = 0; i < HISTORY.size(); i++) {
    List<Object> h = HISTORY[i];
    Boolean linked = i < STAGE;
    Case k = existing.containsKey((String) h[0]) ? existing.get((String) h[0]) : new Case(Subject = (String) h[0]);
    k.Type = 'Customer Order Issue';
    k.Origin = 'Web';
    k.Status = 'Closed';
    k.Priority = (String) h[1];
    k.Description = h[2] + ' days ago (demo timeline). ' + (String) h[3];
    k.ContactId = linked ? c.Id : null;
    k.AccountId = linked ? c.AccountId : null;
    toSave.add(k);
    System.debug(LoggingLevel.WARN, (linked ? 'LINK   ' : 'unlink ') + h[0] + ' (' + h[1] + ', ' + h[2] + ' days ago)');
}
System.debug(LoggingLevel.WARN, 'Stage ' + STAGE + ' for ' + c.Name + ': ' + STAGE + ' earlier complaint(s) count in the last 30 days.');
if (DRY_RUN) {
    System.debug(LoggingLevel.WARN, 'DRY_RUN: nothing written. Set DRY_RUN = false to write.');
    return;
}
upsert toSave;

Flow.Interview risk = Flow.Interview.createInterview(
    'CARES_Get_Risk_Result',
    new Map<String, Object>{ 'contactId' => c.Id, 'lookbackDays' => 30 }
);
risk.start();
System.debug(LoggingLevel.WARN, 'Risk now: ' + risk.getVariableValue('riskStatus') + ', ' + risk.getVariableValue('issueCount') + ' issue(s).');
