// Set up the Stolen & Delayed delivery map links (D-107):
//   1. CARES_Map_Link_Setting__c org default: a new random signing key (only if there is none), the site that
//      serves /delivery-map, its URL (the agent user can't look it up) and how long a link lives.
//   2. The CARES_Delivery_Map_Guest permission set on that site's guest user, so the page can call
//      CARES_DeliveryMapLink.
// Run after CARES_Map_Link_Setting__c, CARES_DeliveryMapLink and the permission set are deployed:
//   sf apex run --file scripts/apex/setup-delivery-map-link.apex --target-org <team org>
// Starts with DRY_RUN = true: it prints what it would do and changes nothing. Set it to false to write.
// The key is never printed. Set ROTATE_KEY = true only to replace it: every live link stops working (G-138).
// Run it twice: Salesforce can't save a setting and a permission set assignment in one go (MIXED_DML), so the
// first run saves the setting and the second gives the guest user the permission set.

Boolean DRY_RUN = true;
Boolean ROTATE_KEY = false;
String SITE_NAME = 'Customer Support';
Integer MINUTES = 30;

CARES_Map_Link_Setting__c s = CARES_Map_Link_Setting__c.getOrgDefaults();
Boolean hasKey = s != null && String.isNotBlank(s.Signing_Key__c);
if (s == null || s.Id == null) {
    s = new CARES_Map_Link_Setting__c(SetupOwnerId = UserInfo.getOrganizationId());
}
List<Network> sites = [SELECT Id FROM Network WHERE Name = :SITE_NAME LIMIT 1];
if (sites.isEmpty()) {
    System.debug(LoggingLevel.WARN, 'No site named "' + SITE_NAME + '". Check SITE_NAME.');
    return;
}
List<Site> siteRows = [SELECT GuestUserId FROM Site WHERE MasterLabel = :SITE_NAME OR Name = :SITE_NAME.replace(' ', '_') LIMIT 1];
Id guestId = siteRows.isEmpty() ? null : siteRows[0].GuestUserId;
PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'CARES_Delivery_Map_Guest' LIMIT 1];
Boolean assigned = guestId != null &&
    [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :guestId AND PermissionSetId = :ps.Id] > 0;

System.debug(LoggingLevel.WARN, 'Setting: site "' + SITE_NAME + '", ' + MINUTES + ' minutes, key ' +
    (hasKey && !ROTATE_KEY ? 'kept' : (hasKey ? 'ROTATED' : 'created')));
System.debug(LoggingLevel.WARN, 'Guest user: ' + (guestId == null ? 'NOT FOUND' : (assigned ? 'already has the permission set' : 'gets the permission set')));
if (DRY_RUN) {
    System.debug(LoggingLevel.WARN, 'DRY_RUN: nothing written. Set DRY_RUN = false to write.');
    return;
}
String siteUrl = CARES_DeliveryMapLink.siteUrl(SITE_NAME);
Boolean settingNeeded = !hasKey || ROTATE_KEY || s.Site_Name__c != SITE_NAME || s.Minutes__c != MINUTES || s.Site_Url__c != siteUrl;
if (settingNeeded) {
    if (!hasKey || ROTATE_KEY) {
        s.Signing_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    }
    s.Site_Name__c = SITE_NAME;
    s.Site_Url__c = siteUrl;
    s.Minutes__c = MINUTES;
    upsert s;
    System.debug(LoggingLevel.WARN, assigned ? 'Setting saved. Done.' : 'Setting saved. Run the script again to give the guest user the permission set.');
} else if (guestId != null && !assigned) {
    insert new PermissionSetAssignment(AssigneeId = guestId, PermissionSetId = ps.Id);
    System.debug(LoggingLevel.WARN, 'Guest user has the permission set. Done.');
} else {
    System.debug(LoggingLevel.WARN, 'Nothing to do: already set up.');
}
