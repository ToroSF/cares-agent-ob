// Seed one ordinary issue Case for the FX-NOTCLEAN test fixture, so the Risk Flow returns NOT_CLEAN for it.
// Run once (again after the Case is removed or unlinked):
//   sf apex run --file scripts/apex/seed-risk-fixture.apex --target-org <team org>
// Safe to run again: it does nothing when the contact already has the seeded Case.
// Set DRY_RUN = true to print what would change without writing.
//
// Why: Risk Flow v3 does not count the escalation Cases CARES opens itself (CARES_Escalation__c, D-082).
// Before v3, every NOT_CLEAN fixture was NOT_CLEAN only because of those Cases, so after v3 the org had
// no contact with 1-2 issue Cases and the NOT_CLEAN scenarios (B-RD-01, B-RD-06, B-RF-12a, B-RD-16) saw CLEAN.
// The contact is Barclay Scarsbrooke, the earlier FX-NOTCLEAN (Explorer, latest order above the clean cap).
// All data is mock. To undo: unlink the Case (ContactId = null).

Boolean DRY_RUN = false;
String FIXTURE_NAME = 'Barclay Scarsbrooke';
String SUBJECT = 'CARES test fixture: order arrived with a missing item';

List<Contact> cs = [SELECT Id, AccountId FROM Contact WHERE Name = :FIXTURE_NAME LIMIT 1];
if (cs.isEmpty()) {
    System.debug('SEED risk fixture: contact not found: ' + FIXTURE_NAME);
} else {
    Contact c = cs[0];
    Integer existing = [SELECT COUNT() FROM Case WHERE ContactId = :c.Id AND Subject = :SUBJECT];
    if (existing > 0) {
        System.debug('SEED risk fixture: ' + FIXTURE_NAME + ' already has the seeded Case');
    } else if (DRY_RUN) {
        System.debug('SEED risk fixture: would add 1 issue Case for ' + FIXTURE_NAME + ' (dry run)');
    } else {
        insert new Case(
            ContactId = c.Id,
            AccountId = c.AccountId,
            Subject = SUBJECT,
            Type = 'Customer Order Issue',
            Origin = 'Web',
            Status = 'Closed'
        );
        System.debug('SEED risk fixture: added 1 issue Case for ' + FIXTURE_NAME);
    }
}
