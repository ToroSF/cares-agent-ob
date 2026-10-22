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
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
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
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'CARES_Experience_Rating_Access'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );
    return u;
  }

  private static CsatRatingSaver.Request request(
    String contactId,
    Decimal score,
    String comment
  ) {
    return request(contactId, score, comment, 'POSITIVE');
  }

  private static CsatRatingSaver.Request request(
    String contactId,
    Decimal score,
    String comment,
    String sentiment
  ) {
    CsatRatingSaver.Request req = new CsatRatingSaver.Request();
    req.contactId = contactId;
    req.score = score;
    req.comment = comment;
    req.sentiment = sentiment;
    return req;
  }

  private static CsatRatingSaver.Result save(
    String contactId,
    Decimal score,
    String comment
  ) {
    return CsatRatingSaver.execute(
      new List<CsatRatingSaver.Request>{ request(contactId, score, comment) }
    )[0];
  }

  private static CsatRatingSaver.Result save(
    String contactId,
    Decimal score,
    String comment,
    String sentiment
  ) {
    return CsatRatingSaver.execute(
      new List<CsatRatingSaver.Request>{
        request(contactId, score, comment, sentiment)
      }
    )[0];
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
      saved = [
        SELECT Contact__c, Account__c, Score__c, Comment__c, Interaction_Date__c
        FROM CSAT_Rating__c
        WHERE Id = :r.ratingId
      ];
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
      System.assertEquals(
        false,
        r.isSuccess,
        'Score ' + score + ' must be rejected'
      );
      System.assert(String.isNotBlank(r.errorMessage));
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM CSAT_Rating__c],
      'Nothing saved for invalid scores'
    );
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
    System.assertEquals(
      false,
      r.isSuccess,
      'Without the permission set the save must fail, not throw'
    );
    System.assertEquals(0, [SELECT COUNT() FROM CSAT_Rating__c]);
  }

  // The profile the real agent user has; System Administrator hid G-089
  private static User agentUser() {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Einstein Agent User'
      LIMIT 1
    ];
    User u = new User(
      Alias = 'csata',
      Email = 'csat.agent@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'CSAT Agent',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'csat.agent.' + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'CARES_Experience_Rating_Access'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );
    return u;
  }

  @IsTest
  static void agentProfileNeverThrows() {
    // Live on v5 the Contact query threw for the agent user (G-089), so the agent got an action error
    // and no isSuccess. Whatever access the profile has, the result must say what happened (INV-9)
    Contact c = makeContact();
    CsatRatingSaver.Result r;
    System.runAs(agentUser()) {
      try {
        r = save(c.Id, 5, null);
      } catch (Exception e) {
        System.assert(
          false,
          'Threw instead of returning an error: ' + e.getMessage()
        );
      }
    }
    System.assertNotEquals(null, r);
    Integer saved = [SELECT COUNT() FROM CSAT_Rating__c];
    System.assertEquals(
      r.isSuccess ? 1 : 0,
      saved,
      'isSuccess must match what was saved: ' + r.errorMessage
    );
  }

  @IsTest
  static void agentProfileSavesLinkedToTheAccount() {
    // G-089 fix: with Read on Account in the permission set, the agent profile saves the rating
    // linked to the customer's account
    Contact c = makeContact();
    CsatRatingSaver.Result r;
    System.runAs(agentUser()) {
      r = save(c.Id, 5, 'Customer was happy with the refund.');
    }
    System.assert(r.isSuccess, r.errorMessage);
    CSAT_Rating__c saved = [
      SELECT Contact__c, Account__c, Score__c
      FROM CSAT_Rating__c
      WHERE Id = :r.ratingId
      WITH SYSTEM_MODE
    ];
    System.assertEquals(c.Id, saved.Contact__c);
    System.assertEquals(c.AccountId, saved.Account__c);
    System.assertEquals(5, saved.Score__c);
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
        System.assert(
          false,
          'Contact id "' +
            bad +
            '" threw instead of returning an error: ' +
            e.getMessage()
        );
      }
      System.assertEquals(
        false,
        r.isSuccess,
        'Contact id "' + bad + '" must not save'
      );
    }
  }

  @IsTest
  static void resultsLineUpWithRequestsInABatch() {
    Contact c = makeContact();
    List<CsatRatingSaver.Result> rs;
    System.runAs(ratingUser()) {
      rs = CsatRatingSaver.execute(
        new List<CsatRatingSaver.Request>{
          request(c.Id, 5, null),
          request(c.Id, 9, null)
        }
      );
    }
    System.assertEquals(2, rs.size());
    System.assertEquals(
      true,
      rs[0].isSuccess,
      'First request (valid) must get the first result: ' + rs[0].errorMessage
    );
    System.assertEquals(
      false,
      rs[1].isSuccess,
      'Second request (score 9) must get the second result'
    );
  }

  @IsTest
  static void rejectsAnythingOutsideTheFourSentimentValues() {
    Contact c = makeContact();
    for (String sentiment : new List<String>{ 'HAPPY', '', null, 'positive' }) {
      CsatRatingSaver.Result r = save(c.Id, 4, null, sentiment);
      System.assertEquals(
        false,
        r.isSuccess,
        'Sentiment "' + sentiment + '" must be rejected'
      );
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM CSAT_Rating__c],
      'Nothing saved for an invalid sentiment'
    );
  }

  @IsTest
  static void savingAFrustratedSentimentOpensTheCustomerContext() {
    Contact c = makeContact();
    System.runAs(ratingUser()) {
      CsatRatingSaver.Result r = save(
        c.Id,
        2,
        'Still waiting on a refund',
        'FRUSTRATED'
      );
      System.assertEquals(true, r.isSuccess, 'Save failed: ' + r.errorMessage);
    }
    CARES_Customer_Context__c ctx = [
      SELECT Contact__c, Sentiment__c, Has_Open_Context__c, Source_Rating__c
      FROM CARES_Customer_Context__c
      WHERE Contact__c = :c.Id WITH SYSTEM_MODE
    ];
    System.assertEquals('FRUSTRATED', ctx.Sentiment__c);
    System.assertEquals(true, ctx.Has_Open_Context__c);
    System.assertNotEquals(null, ctx.Source_Rating__c);
  }

  @IsTest
  static void aThumbsUpNeverOpensTheContextWhateverTheSentiment() {
    // G-133: the customer asked to be marked FRUSTRATED, then gave a thumbs up (score 5)
    Contact c = makeContact();
    System.runAs(ratingUser()) {
      CsatRatingSaver.Result r = save(
        c.Id,
        5,
        'Asked to be marked as frustrated for a better deal',
        'FRUSTRATED'
      );
      System.assertEquals(true, r.isSuccess, 'Save failed: ' + r.errorMessage);
    }
    CARES_Customer_Context__c ctx = [
      SELECT Sentiment__c, Has_Open_Context__c
      FROM CARES_Customer_Context__c
      WHERE Contact__c = :c.Id WITH SYSTEM_MODE
    ];
    System.assertEquals('FRUSTRATED', ctx.Sentiment__c, 'The read is still kept');
    System.assertEquals(false, ctx.Has_Open_Context__c, 'No bonus from a thumbs up');
  }

  @IsTest
  static void savingAPositiveSentimentClosesAnOpenContext() {
    Contact c = makeContact();
    System.runAs(ratingUser()) {
      CsatRatingSaver.Result first = save(
        c.Id,
        2,
        'This was frustrating',
        'FRUSTRATED'
      );
      System.assertEquals(true, first.isSuccess, 'Save failed: ' + first.errorMessage);
    }
    System.assertEquals(
      true,
      [
        SELECT Has_Open_Context__c
        FROM CARES_Customer_Context__c
        WHERE Contact__c = :c.Id WITH SYSTEM_MODE
      ]
      .Has_Open_Context__c
    );

    System.runAs(ratingUser()) {
      // A second, separate rating later in time (e.g. the next resolved case) reports POSITIVE
      CsatRatingSaver.Result second = save(c.Id, 5, 'All good now', 'POSITIVE');
      System.assertEquals(true, second.isSuccess, 'Save failed: ' + second.errorMessage);
    }

    List<CARES_Customer_Context__c> rows = [
      SELECT Sentiment__c, Has_Open_Context__c
      FROM CARES_Customer_Context__c
      WHERE Contact__c = :c.Id WITH SYSTEM_MODE
    ];
    System.assertEquals(
      1,
      rows.size(),
      'One evolving row per contact, not an append-only history'
    );
    System.assertEquals('POSITIVE', rows[0].Sentiment__c);
    System.assertEquals(false, rows[0].Has_Open_Context__c);
  }

  @IsTest
  static void agentProfileSavesTheRatingAndTheContextTogether() {
    // CARES_Experience_Rating_Access grants both CSAT_Rating__c and CARES_Customer_Context__c
    // access, so the agent profile's single save_csat_rating call produces both rows.
    Contact c = makeContact();
    CsatRatingSaver.Result r;
    System.runAs(agentUser()) {
      r = save(c.Id, 5, 'Customer was happy', 'POSITIVE');
    }
    System.assertEquals(true, r.isSuccess, 'Save failed: ' + r.errorMessage);
    System.assertEquals(1, [SELECT COUNT() FROM CSAT_Rating__c]);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM CARES_Customer_Context__c WHERE Contact__c = :c.Id]
    );
  }
}
