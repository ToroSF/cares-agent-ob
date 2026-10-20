/**
 * Unit tests for CARES_Identity_FindContactByEmail (D-058): a match only for
 * exactly one Contact, only the Id returned, and every bad input is "not found".
 */
@IsTest
private class CARES_Identity_FindContactByEmailTest {
  private static CARES_Identity_FindContactByEmail.Result lookup(String email) {
    CARES_Identity_FindContactByEmail.Request req = new CARES_Identity_FindContactByEmail.Request();
    req.email = email;
    return CARES_Identity_FindContactByEmail.execute(
      new List<CARES_Identity_FindContactByEmail.Request>{ req }
    )[0];
  }

  @IsTest
  static void findsTheSingleMatchingContact() {
    Contact c = new Contact(
      LastName = 'Identity Test',
      Email = 'identity.test@example.com'
    );
    insert c;
    CARES_Identity_FindContactByEmail.Result r = lookup(
      'identity.test@example.com'
    );
    System.assertEquals(true, r.found);
    System.assertEquals(String.valueOf(c.Id), r.contactId);
  }

  @IsTest
  static void ignoresCaseAndSurroundingSpaces() {
    Contact c = new Contact(
      LastName = 'Identity Test',
      Email = 'identity.test@example.com'
    );
    insert c;
    System.assertEquals(
      String.valueOf(c.Id),
      lookup('  Identity.Test@Example.COM ').contactId
    );
  }

  @IsTest
  static void twoContactsWithTheSameEmailIsNotAMatch() {
    insert new List<Contact>{
      new Contact(LastName = 'Twin One', Email = 'shared@example.com'),
      new Contact(LastName = 'Twin Two', Email = 'shared@example.com')
    };
    CARES_Identity_FindContactByEmail.Result r = lookup('shared@example.com');
    System.assertEquals(
      false,
      r.found,
      'Ambiguous emails must not pick a person'
    );
    System.assertEquals('', r.contactId);
  }

  @IsTest
  static void unknownEmailIsNotFound() {
    CARES_Identity_FindContactByEmail.Result r = lookup(
      'nobody.here@example.com'
    );
    System.assertEquals(false, r.found);
    System.assertEquals('', r.contactId);
  }

  @IsTest
  static void badInputIsNotFoundAndNeverThrows() {
    for (
      String bad : new List<String>{
        null,
        '',
        '   ',
        'not-an-email',
        'a@b',
        '%@example.com OR Id != null',
        'x@example.com\nselect'
      }
    ) {
      CARES_Identity_FindContactByEmail.Result r = lookup(bad);
      System.assertEquals(false, r.found, 'Input must not match: ' + bad);
      System.assertEquals('', r.contactId);
    }
  }

  @IsTest
  static void handlesABatchInOrder() {
    Contact c = new Contact(
      LastName = 'Identity Test',
      Email = 'identity.test@example.com'
    );
    insert c;
    CARES_Identity_FindContactByEmail.Request a = new CARES_Identity_FindContactByEmail.Request();
    a.email = 'nobody.here@example.com';
    CARES_Identity_FindContactByEmail.Request b = new CARES_Identity_FindContactByEmail.Request();
    b.email = 'identity.test@example.com';
    List<CARES_Identity_FindContactByEmail.Result> rs = CARES_Identity_FindContactByEmail.execute(
      new List<CARES_Identity_FindContactByEmail.Request>{ a, b }
    );
    System.assertEquals(false, rs[0].found);
    System.assertEquals(true, rs[1].found);
  }
}
