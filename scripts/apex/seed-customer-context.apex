// Seed CARES_Customer_Context__c rows for the two stable named test fixtures (D-083).
// Run once after CARES_Customer_Context__c and its permission sets are deployed:
//   sf apex run --file scripts/apex/seed-customer-context.apex --target-org <team org>
// Safe to run again: rows are upserted by Contact__c, matching CsatRatingSaver's own upsert key.
// Set DRY_RUN = true to print what would change without writing.
//
// All sentiment labels here are mock data for this project (D-083) - there is no real Pronto
// sentiment feed. The two contacts seeded are the repo's existing stable NAMED fixtures
// (scripts/testing/build_fixtures.py), reused here instead of inventing a third test persona:
//   - Boyce Antrag (FX-CLEAN-BIG): CLEAN risk status, seeded FRUSTRATED + Has_Open_Context__c =
//     true. Proves the retention bonus path (B-RD-15): PATTERN_REVIEW does not fire for this
//     contact, so the context read runs and the bonus applies.
//   - Alex Morgan (FX-DIRTY): already the PATTERN_REVIEW fixture (5+ issue cases). Seeded
//     FRUSTRATED + Has_Open_Context__c = true anyway, specifically to prove the abuse gate wins:
//     the trace should show PATTERN_REVIEW firing and get_customer_context never even running.
//
// FX-NOTCLEAN (B-RD-16, proves the bonus never stacks with an existing NOT_CLEAN result) is
// picked dynamically at test-build time (scripts/testing/build_fixtures.py), not a fixed name, so
// it is not seeded here - overlay a context row on whichever contact that run resolves to, or
// extend build_fixtures.py to call the seed logic per-run if this scenario needs to be automated.
//
// The person who runs it needs the CARES_Experience_Rating_Access permission set (Create/Edit on
// CARES_Customer_Context__c, same access CsatRatingSaver itself uses).

Boolean DRY_RUN = false;

Map<String, String> CONTEXT_BY_NAME = new Map<String, String>{
    'Boyce Antrag' => 'FRUSTRATED',
    'Alex Morgan' => 'FRUSTRATED'
};

Map<Id, Contact> contactsByName = new Map<Id, Contact>();
Map<String, Id> contactIdByName = new Map<String, Id>();
for (Contact c : [SELECT Id, Name FROM Contact WHERE Name IN :CONTEXT_BY_NAME.keySet()]) {
    contactsByName.put(c.Id, c);
    contactIdByName.put(c.Name, c.Id);
}

Map<Id, CARES_Customer_Context__c> existingByContact = new Map<Id, CARES_Customer_Context__c>();
for (CARES_Customer_Context__c ctx : [
    SELECT Id, Contact__c
    FROM CARES_Customer_Context__c
    WHERE Contact__c IN :contactsByName.keySet()
]) {
    existingByContact.put(ctx.Contact__c, ctx);
}

List<CARES_Customer_Context__c> toUpsert = new List<CARES_Customer_Context__c>();
List<String> seeded = new List<String>();
for (String name : CONTEXT_BY_NAME.keySet()) {
    Id contactId = contactIdByName.get(name);
    if (contactId == null) {
        System.debug('SEED customer context: contact not found, skipping: ' + name);
        continue;
    }
    CARES_Customer_Context__c ctx = existingByContact.get(contactId);
    if (ctx == null) {
        ctx = new CARES_Customer_Context__c(Contact__c = contactId);
    }
    ctx.Sentiment__c = CONTEXT_BY_NAME.get(name);
    ctx.Has_Open_Context__c = true;
    ctx.Last_Interaction_Date__c = Datetime.now();
    toUpsert.add(ctx);
    seeded.add(name + ' -> ' + CONTEXT_BY_NAME.get(name));
}

if (!DRY_RUN) {
    upsert toUpsert;
}
System.debug('SEED customer context: ' + seeded + (DRY_RUN ? ' (dry run)' : ''));
