@IsTest
private class CARES_DeliveryMapLinkTest {
  private static final String ORDER_ID = 'PR-241018-MAPLNK1';
  private static final String CONTACT_ID = '003000000000001AAA';

  private static void setUp(Boolean withTelemetry) {
    CARES_DeliveryMapLink.settingOverride = new CARES_Map_Link_Setting__c(
      Signing_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256)),
      Minutes__c = 30
    );
    CARES_DeliveryMapLink.baseUrlOverride = 'https://example.test/customers/';
    CARES_DeliveryMapLink.nowOverride = 1800000000;
    if (withTelemetry) {
      Database.insert(
        new CARES_Delivery_Telemetry__c(
          Order_ID__c = ORDER_ID,
          Driver_ID__c = 'DRV-TEST-1',
          Restaurant_Location__Latitude__s = 40.741600,
          Restaurant_Location__Longitude__s = -73.990000,
          Dropoff_Location__Latitude__s = 40.750000,
          Dropoff_Location__Longitude__s = -73.985000,
          Driver_Location__Latitude__s = 40.760000,
          Driver_Location__Longitude__s = -73.970000
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  private static String token(String url) {
    return url.substringAfter('?t=');
  }

  @IsTest
  static void aValidLinkShowsTheCard() {
    setUp(true);
    String url = CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD');
    Assert.isTrue(
      url.startsWith('https://example.test/customers/delivery-map?t='),
      url
    );
    CARES_GeofenceCardView g = CARES_DeliveryMapLink.view(token(url));
    Assert.isNotNull(g);
    Assert.areEqual(ORDER_ID, g.orderId);
    Assert.areEqual(41.70, g.orderTotal);
    Assert.areEqual('USD', g.currencyIsoCode);
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MISMATCH, g.gpsResult);
    Assert.isTrue(
      Math.abs(g.radiusMeters - 562.3) < 1,
      String.valueOf(g.radiusMeters)
    );
  }

  @IsTest
  static void aChangedLinkShowsNothing() {
    setUp(true);
    String t = token(
      CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD')
    );
    String body = t.substringBefore('.');
    String signature = t.substringAfter('.');
    // Another order in the payload, same signature
    String otherBody = EncodingUtil.base64Encode(
        Blob.valueOf(
          'PR-000000-OTHER01|' + CONTACT_ID + '|41.70|USD|1800001800'
        )
      )
      .replace('+', '-')
      .replace('/', '_')
      .remove('=');
    Assert.isNull(CARES_DeliveryMapLink.view(otherBody + '.' + signature));
    // One character of the signature changed
    String flipped =
      signature.substring(0, signature.length() - 1) +
      (signature.endsWith('A') ? 'B' : 'A');
    Assert.isNull(CARES_DeliveryMapLink.view(body + '.' + flipped));
    Assert.isNull(CARES_DeliveryMapLink.view(body));
    Assert.isNull(CARES_DeliveryMapLink.view(''));
    Assert.isNull(CARES_DeliveryMapLink.view('not.a-token'));
  }

  @IsTest
  static void anExpiredLinkShowsNothing() {
    setUp(true);
    String t = token(
      CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD')
    );
    CARES_DeliveryMapLink.nowOverride = 1800000000 + 29 * 60;
    Assert.isNotNull(
      CARES_DeliveryMapLink.view(t),
      'Still valid after 29 minutes'
    );
    CARES_DeliveryMapLink.nowOverride = 1800000000 + 31 * 60;
    Assert.isNull(CARES_DeliveryMapLink.view(t), 'Expired after 30 minutes');
  }

  @IsTest
  static void aLinkSignedWithAnotherKeyShowsNothing() {
    setUp(true);
    String t = token(
      CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD')
    );
    CARES_DeliveryMapLink.settingOverride.Signing_Key__c = EncodingUtil.base64Encode(
      Crypto.generateAesKey(256)
    );
    Assert.isNull(
      CARES_DeliveryMapLink.view(t),
      'A rotated key invalidates live links (G-138)'
    );
  }

  @IsTest
  static void withoutAKeyOrASiteThereIsNoLink() {
    setUp(false);
    CARES_DeliveryMapLink.settingOverride.Signing_Key__c = null;
    Assert.isNull(
      CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD')
    );
    Assert.isNull(CARES_DeliveryMapLink.view('a.b'));
    setUp(false);
    CARES_DeliveryMapLink.baseUrlOverride = null;
    CARES_DeliveryMapLink.settingOverride.Site_Name__c = null;
    Assert.isNull(
      CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD')
    );
    Assert.isNull(CARES_DeliveryMapLink.issue('', CONTACT_ID, 41.7, 'USD'));
  }

  @IsTest
  static void aValidLinkForAnOrderWithoutTelemetryShowsNothing() {
    setUp(false);
    String t = token(
      CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD')
    );
    Assert.isNull(CARES_DeliveryMapLink.view(t));
  }

  @IsTest
  static void aGuestWithOnlyTheGuestPermissionSetSeesTheCard() {
    setUp(true);
    String t = token(
      CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD')
    );
    List<User> guests = [
      SELECT Id
      FROM User
      WHERE UserType = 'Guest' AND IsActive = TRUE
      LIMIT 1
    ];
    if (guests.isEmpty()) {
      return; // No site in this org
    }
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'CARES_Delivery_Map_Guest'
      LIMIT 1
    ];
    if (
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :guests[0].Id AND PermissionSetId = :ps.Id
      ] == 0
    ) {
      insert new PermissionSetAssignment(
        AssigneeId = guests[0].Id,
        PermissionSetId = ps.Id
      );
    }
    CARES_GeofenceCardView g;
    System.runAs(guests[0]) {
      g = CARES_DeliveryMapLink.view(t);
    }
    Assert.isNotNull(
      g,
      'The guest has no object access; the verified link reads in system mode'
    );
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MISMATCH, g.gpsResult);
  }

  @IsTest
  static void theSavedSiteUrlIsUsedForTheLink() {
    setUp(true);
    CARES_DeliveryMapLink.baseUrlOverride = null;
    CARES_DeliveryMapLink.settingOverride.Site_Url__c = 'https://example.test/customers';
    String url = CARES_DeliveryMapLink.issue(ORDER_ID, CONTACT_ID, 41.7, 'USD');
    Assert.isTrue(url.startsWith('https://example.test/customers/delivery-map?t='), url);
    Assert.isNull(CARES_DeliveryMapLink.siteUrl(null));
    Assert.isNull(CARES_DeliveryMapLink.siteUrl('No such site name'));
  }
}
