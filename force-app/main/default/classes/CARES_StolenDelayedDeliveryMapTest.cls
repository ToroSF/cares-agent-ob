@IsTest
private class CARES_StolenDelayedDeliveryMapTest {
  // Same fixtures as CARES_StolenDelayedMockTelemetryTest: real-order rows (D-089) plus mock telemetry (D-096)
  private static final String APP_ID = 'PA-sd-card-1';
  private static final String ORDER_ID = 'PR-241018-SDCARD1';
  private static final Decimal RESTAURANT_LAT = 40.741600,
    RESTAURANT_LON = -73.990000;
  private static final Decimal DROPOFF_LAT = 40.750000,
    DROPOFF_LON = -73.985000;
  private static final Decimal AT_DOOR_LAT = 40.749918,
    AT_DOOR_LON = -73.985049;
  private static final Decimal FAR_AWAY_LAT = 40.760000,
    FAR_AWAY_LON = -73.970000;

  private static Id contactId;
  private static User sdUser;

  private static List<Object> row(String orderId, String total) {
    return new List<Object>{
      APP_ID,
      orderId,
      '2024-10-18 18:00:00.000 UTC',
      'Delivered',
      'Test Kitchen',
      total,
      'Cheeseburger; Large Fries',
      null,
      null,
      '2024-10-18 18:40:00.000 UTC'
    };
  }

  private static CARES_Delivery_Telemetry__c telemetry(
    Decimal driverLat,
    Decimal driverLon
  ) {
    return new CARES_Delivery_Telemetry__c(
      Order_ID__c = ORDER_ID,
      Driver_ID__c = 'DRV-TEST-1',
      Restaurant_Location__Latitude__s = RESTAURANT_LAT,
      Restaurant_Location__Longitude__s = RESTAURANT_LON,
      Dropoff_Location__Latitude__s = DROPOFF_LAT,
      Dropoff_Location__Longitude__s = DROPOFF_LON,
      Driver_Location__Latitude__s = driverLat,
      Driver_Location__Longitude__s = driverLon,
      Driver_Wait_Seconds__c = 240,
      Driver_Calls__c = 1,
      Driver_Chats__c = 0,
      Driver_NonDelivery_Rate__c = 0.2,
      Driver_Delivery_Count__c = 900,
      Redispatch_Eligible__c = true
    );
  }

  // A customer with `orders` delivered orders and no claims (6 or more is high trust), the telemetry row, and
  // the agent's permission set. Mock telemetry on, platform off.
  private static void customer(CARES_Delivery_Telemetry__c t, Integer orders) {
    Contact c = new Contact(
      LastName = 'SD Card',
      Pronto_App_Account_Id__c = APP_ID
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    contactId = c.Id;
    if (t != null) {
      Database.insert(t, AccessLevel.SYSTEM_MODE);
    }
    List<List<Object>> rows = new List<List<Object>>{ row(ORDER_ID, '38.50') };
    for (Integer i = 1; i < orders; i++) {
      rows.add(
        row(
          'PR-2409' + String.valueOf(10 + i) + '-OLDERC' + String.valueOf(i),
          '20.00'
        )
      );
    }
    CARES_OrderData.mockRows = rows;
    CARES_StolenDelayedPolicy.Settings s = new CARES_StolenDelayedPolicy.Settings();
    s.mockTelemetryEnabled = true;
    CARES_StolenDelayedPolicy.settingsOverride = s;
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    sdUser = new User(
      Alias = 'sdcard',
      Email = 'sd.card@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'SD Card',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'sd.card.' + System.currentTimeMillis() + '@example.com'
    );
    insert sdUser;
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'CARES_Stolen_Delayed_Access'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = sdUser.Id,
      PermissionSetId = ps.Id
    );
  }

  private static CARES_StolenDelayedDeliveryMap.Result show(
    String forContact,
    String orderId
  ) {
    CARES_StolenDelayedDeliveryMap.Request r = new CARES_StolenDelayedDeliveryMap.Request();
    r.contactId = forContact;
    r.orderId = orderId;
    CARES_StolenDelayedDeliveryMap.Result res;
    System.runAs(sdUser) {
      res = CARES_StolenDelayedDeliveryMap.show(
        new List<CARES_StolenDelayedDeliveryMap.Request>{ r }
      )[0];
    }
    return res;
  }

  @IsTest
  static void anApprovedClaimWithTheDriverFarAwayGetsTheCard() {
    customer(telemetry(FAR_AWAY_LAT, FAR_AWAY_LON), 6);
    CARES_StolenDelayedDeliveryMap.Result res = show(contactId, ORDER_ID);
    Assert.isTrue(res.success);
    CARES_GeofenceCardView g = res.deliveryMap;
    Assert.areEqual(ORDER_ID, g.orderId);
    Assert.isTrue(
      g.orderTotal == 38.50,
      'The real order total, as the policy read it'
    );
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MISMATCH, g.gpsResult);
    Assert.isTrue(g.hasCoordinates);
    Assert.areEqual(FAR_AWAY_LAT, g.driverLatitude);
    Assert.isTrue(
      Math.abs(g.radiusMeters - 562.3) < 1,
      String.valueOf(g.radiusMeters)
    );
    Assert.isTrue(g.driverToCenterMeters > g.radiusMeters);
  }

  @IsTest
  static void aLossAbsorptionGetsAMatchCardWithTheSameNumbersAsTheAdminView() {
    customer(telemetry(AT_DOOR_LAT, AT_DOOR_LON), 6);
    CARES_GeofenceCardView g = show(contactId, ORDER_ID).deliveryMap;
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MATCH, g.gpsResult);
    CARES_GeofenceMapController.View admin;
    System.runAs(sdUser) {
      admin = CARES_GeofenceMapController.build(ORDER_ID, null);
    }
    Assert.areEqual(admin.radiusMeters, g.radiusMeters);
    Assert.areEqual(admin.driverToCenterMeters, g.driverToCenterMeters);
    Assert.areEqual(admin.center.latitude, g.centerLatitude);
  }

  @IsTest
  static void aClaimStillUnderReviewGetsNoCard() {
    // Two orders: trust is not established yet, so a person reviews it (MANUAL_REVIEW)
    customer(telemetry(FAR_AWAY_LAT, FAR_AWAY_LON), 2);
    CARES_StolenDelayedDeliveryMap.Result res = show(contactId, ORDER_ID);
    Assert.isFalse(res.success);
    Assert.isNull(res.deliveryMap);
  }

  @IsTest
  static void aFraudSignalGetsNoCard() {
    CARES_Delivery_Telemetry__c t = telemetry(FAR_AWAY_LAT, FAR_AWAY_LON);
    t.Fraud_Pattern__c = true;
    customer(t, 6);
    Assert.isFalse(show(contactId, ORDER_ID).success);
  }

  @IsTest
  static void anApprovedClaimWithoutLocationsGetsNoCard() {
    CARES_Delivery_Telemetry__c t = telemetry(null, null);
    t.Driver_Distance_Meters__c = 450;
    customer(t, 6);
    Assert.isFalse(show(contactId, ORDER_ID).success);
  }

  @IsTest
  static void anotherCustomersOrderGetsNoCard() {
    customer(telemetry(FAR_AWAY_LAT, FAR_AWAY_LON), 6);
    Contact other = new Contact(
      LastName = 'Someone Else',
      Pronto_App_Account_Id__c = 'PA-sd-card-other'
    );
    Database.insert(other, AccessLevel.SYSTEM_MODE);
    Assert.isFalse(show(other.Id, ORDER_ID).success);
  }

  @IsTest
  static void blankInputsGetNoCard() {
    customer(telemetry(FAR_AWAY_LAT, FAR_AWAY_LON), 6);
    Assert.isFalse(show('', ORDER_ID).success);
    Assert.isFalse(show(contactId, '').success);
  }

  // The page link outside the chat (D-107): only for a card, and only when links are set up
  @IsTest
  static void anApprovedClaimGetsASignedPageLinkWhenLinksAreSetUp() {
    customer(telemetry(FAR_AWAY_LAT, FAR_AWAY_LON), 6);
    CARES_DeliveryMapLink.settingOverride = new CARES_Map_Link_Setting__c(
      Signing_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256)),
      Minutes__c = 30
    );
    CARES_DeliveryMapLink.baseUrlOverride = 'https://example.test/customers';
    CARES_StolenDelayedDeliveryMap.Result res = show(contactId, ORDER_ID);
    Assert.isTrue(
      res.mapUrl.startsWith('https://example.test/customers/delivery-map?t='),
      res.mapUrl
    );
    Assert.areEqual(
      ORDER_ID,
      CARES_DeliveryMapLink.view(res.mapUrl.substringAfter('?t=')).orderId
    );
  }

  @IsTest
  static void noCardMeansNoPageLink() {
    customer(telemetry(FAR_AWAY_LAT, FAR_AWAY_LON), 2);
    CARES_DeliveryMapLink.settingOverride = new CARES_Map_Link_Setting__c(
      Signing_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256))
    );
    CARES_DeliveryMapLink.baseUrlOverride = 'https://example.test/customers';
    Assert.isNull(show(contactId, ORDER_ID).mapUrl);
  }

  @IsTest
  static void withoutLinkSetupTheCardStillComesWithoutALink() {
    customer(telemetry(FAR_AWAY_LAT, FAR_AWAY_LON), 6);
    CARES_StolenDelayedDeliveryMap.Result res = show(contactId, ORDER_ID);
    Assert.isTrue(res.success);
    Assert.isNull(res.mapUrl);
  }
}
