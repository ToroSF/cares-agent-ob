// Mark the escalation Cases CARES opened before Case.CARES_Escalation__c existed (D-082, G-101).
// Run once, after CARES_Escalation__c and the new CARES_Create_Escalation_Case version are deployed:
//   sf apex run --file scripts/apex/backfill-cares-escalation-flag.apex --target-org <team org>
// Starts with DRY_RUN = true: it prints the counts and changes nothing. Set it to false to write.
// Safe to run again: only Cases still marked false are updated.
//
// A CARES escalation Case is one created by the agent user (profile Einstein Agent User) with a
// Subject starting "CARES" and containing "escalation". That covers both Flow versions: v1 wrote
// Origin = Chat and Subject "CARES escalation", v2 writes Origin = Agentforce and a Subject per
// category. On 2026-10-21 both rules matched the same 143 Cases in the team org.
//
// The person who runs it needs Edit on Case.CARES_Escalation__c: anonymous Apex checks field
// access when it compiles. CARES_Escalation_Access grants it.

Boolean DRY_RUN = true;

List<Case> toMark = [
    SELECT Id, Origin
    FROM Case
    WHERE CARES_Escalation__c = false
        AND CreatedBy.Profile.Name = 'Einstein Agent User'
        AND Subject LIKE 'CARES%escalation%'
    LIMIT 10000
];

Map<String, Integer> byOrigin = new Map<String, Integer>();
for (Case c : toMark) {
    String origin = c.Origin == null ? '(blank)' : c.Origin;
    byOrigin.put(origin, (byOrigin.containsKey(origin) ? byOrigin.get(origin) : 0) + 1);
    c.CARES_Escalation__c = true;
}
System.debug(LoggingLevel.WARN, 'CARES escalation Cases to mark: ' + toMark.size() + ' by Origin ' + byOrigin);

if (DRY_RUN) {
    System.debug(LoggingLevel.WARN, 'DRY_RUN: nothing written. Set DRY_RUN = false to update.');
} else {
    List<Database.SaveResult> results = Database.update(toMark, false);
    Integer failed = 0;
    for (Database.SaveResult r : results) {
        if (!r.isSuccess()) {
            failed++;
            System.debug(LoggingLevel.ERROR, 'Not updated: ' + r.getId() + ' ' + r.getErrors());
        }
    }
    System.debug(LoggingLevel.WARN, 'Updated: ' + (toMark.size() - failed) + ', failed: ' + failed);
}

System.debug(
    LoggingLevel.WARN,
    'Still unmarked after this run: ' +
    [
        SELECT COUNT()
        FROM Case
        WHERE CARES_Escalation__c = false
            AND CreatedBy.Profile.Name = 'Einstein Agent User'
            AND Subject LIKE 'CARES%escalation%'
    ]
);
