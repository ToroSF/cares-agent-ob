/**
 * Unit tests for CsatRatingSaver (Experience Rating, save_csat_rating).
 * The agent trusts isSuccess to decide what it tells the customer (INV-9),
 * so every failure must come back as isSuccess = false, never as an exception,
 * and results must line up with requests.
 * Saves run as a user holding CARES_Experience_Rating_Access, the permission set
 * the agent user needs (field access on CSAT_Rating__c comes only from it).
 */
@IsTest
private class CsatRatingSaverTest {
    private static Contact makeContact() {
        Account a = new Account(Name = 'CARES Test Account');
        insert a;
        Contact c = new Contact(LastName = 'CARES Test', AccountId = a.Id);
        insert c;
        return c;
    }

    private static User ratingUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            Alias = 'csatt',
            Email = 'csat.test@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'CSAT Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'csat.test.' + System.currentTimeMillis() + '@example.com'
        );
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'CARES_Experience_Rating_Access' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    private static CsatRatingSaver.Request request(String contactId, Decimal score, String comment) {
        CsatRatingSaver.Request req = new CsatRatingSaver.Request();
        req.contactId = contactId;
        req.score = score;
        req.comment = comment;
        return req;
    }

    private static CsatRatingSaver.Result save(String contactId, Decimal score, String comment) {
        return CsatRatingSaver.execute(new List<CsatRatingSaver.Request>{ request(contactId, score, comment) })[0];
    }

    @IsTest
    static void savesAValidRatingAgainstTheContactAndAccount() {
        Contact c = makeContact();
        CsatRatingSaver.Result r;
        CSAT_Rating__c saved;
        Test.startTest();
        System.runAs(ratingUser()) {
            r = save(c.Id, 2, 'Fries were cold');
            System.assertEquals(true, r.isSuccess, 'Save failed: ' + r.errorMessage);
            System.assertNotEquals(null, r.ratingId);
            saved = [SELECT Contact__c, Account__c, Score__c, Comment__c, Interaction_Date__c FROM CSAT_Rating__c WHERE Id = :r.ratingId];
        }
        Test.stopTest();

        System.assertEquals(c.Id, saved.Contact__c);
        System.assertEquals(c.AccountId, saved.Account__c);
        System.assertEquals(2, saved.Score__c);
        System.assertEquals('Fries were cold', saved.Comment__c);
        System.assertNotEquals(null, saved.Interaction_Date__c);
    }

    @IsTest
    static void commentIsOptional() {
        Contact c = makeContact();
        CsatRatingSaver.Result r;
        System.runAs(ratingUser()) {
            r = save(c.Id, 5, null);
        }
        System.assertEquals(true, r.isSuccess, 'Save failed: ' + r.errorMessage);
    }

    @IsTest
    static void rejectsScoresOutsideOneToFive() {
        Contact c = makeContact();
        for (Decimal score : new List<Decimal>{ 0, 6, -3, 11, null }) {
            CsatRatingSaver.Result r = save(c.Id, score, null);
            System.assertEquals(false, r.isSuccess, 'Score ' + score + ' must be rejected');
            System.assert(String.isNotBlank(r.errorMessage));
        }
        System.assertEquals(0, [SELECT COUNT() FROM CSAT_Rating__c], 'Nothing saved for invalid scores');
    }

    @IsTest
    static void saveFailsHonestlyWithoutThePermissionSet() {
        // What the agent user hits until CARES_Experience_Rating_Access is assigned (OPEN_ITEMS, B-ER-08)
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'csatn',
            Email = 'csat.noperm@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'CSAT No Perm',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'csat.noperm.' + System.currentTimeMillis() + '@example.com'
        );
        insert u;
        Contact c = makeContact();
        CsatRatingSaver.Result r;
        System.runAs(u) {
            r = save(c.Id, 4, null);
        }
        System.assertEquals(false, r.isSuccess, 'Without the permission set the save must fail, not throw');
        System.assertEquals(0, [SELECT COUNT() FROM CSAT_Rating__c]);
    }

    @IsTest
    static void unknownContactIsAnErrorNotASave() {
        Contact c = makeContact();
        Id goneId = c.Id;
        delete c;
        CsatRatingSaver.Result r = save(goneId, 4, null);
        System.assertEquals(false, r.isSuccess);
        System.assertEquals(0, [SELECT COUNT() FROM CSAT_Rating__c]);
    }

    @IsTest
    static void malformedOrBlankContactIdFailsGracefully() {
        // The agent can pass whatever is in ContactId; a bad value must give isSuccess = false, not an exception
        for (String bad : new List<String>{ 'not-an-id', '' }) {
            CsatRatingSaver.Result r;
            try {
                r = save(bad, 4, null);
            } catch (Exception e) {
                System.assert(false, 'Contact id "' + bad + '" threw instead of returning an error: ' + e.getMessage());
            }
            System.assertEquals(false, r.isSuccess, 'Contact id "' + bad + '" must not save');
        }
    }

    @IsTest
    static void resultsLineUpWithRequestsInABatch() {
        Contact c = makeContact();
        List<CsatRatingSaver.Result> rs;
        System.runAs(ratingUser()) {
            rs = CsatRatingSaver.execute(new List<CsatRatingSaver.Request>{
                request(c.Id, 5, null),
                request(c.Id, 9, null)
            });
        }
        System.assertEquals(2, rs.size());
        System.assertEquals(true, rs[0].isSuccess, 'First request (valid) must get the first result: ' + rs[0].errorMessage);
        System.assertEquals(false, rs[1].isSuccess, 'Second request (score 9) must get the second result');
    }
}
