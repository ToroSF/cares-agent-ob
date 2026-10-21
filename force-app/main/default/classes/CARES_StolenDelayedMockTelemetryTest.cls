@IsTest
private class CARES_StolenDelayedMockTelemetryTest {
  // Same real-order fixtures as CARES_StolenDelayedActionsTest (D-089), plus mock telemetry (D-096)
  private static final String APP_ID = 'PA-sd-mock-1';
  private static final String ORDER_ID = 'PR-241018-SDMOCK1';

  // Trip geofence points (D-097): a 1,025 m trip, so radius = 512 m + 50 m tolerance, centered on its midpoint
  private static final Decimal RESTAURANT_LAT = 40.741600, RESTAURANT_LON = -73.990000;
  private static final Decimal DROPOFF_LAT = 40.750000, DROPOFF_LON = -73.985000;
  private static final Decimal AT_DOOR_LAT = 40.749918, AT_DOOR_LON = -73.985049; // 10 m before the door
  private static final Decimal PAST_DOOR_LAT = 40.750123, PAST_DOOR_LON = -73.984927; // 15 m past the door, away from the restaurant
  private static final Decimal NEAR_RESTAURANT_LAT = 40.741846, NEAR_RESTAURANT_LON = -73.989854; // 30 m from the restaurant
  private static final Decimal FAR_AWAY_LAT = 40.760000, FAR_AWAY_LON = -73.970000; // 2.2 km from the center

  private static Id contactId;
  private static User sdUser;

  private static List<Object> row(String orderId, String status, String total) {
    return new List<Object>{
      APP_ID,
      orderId,
      '2024-10-18 18:00:00.000 UTC',
      status,
      'Test Kitchen',
      total,
      'Cheeseburger; Large Fries',
      null,
      null,
      status == 'Delivered' ? '2024-10-18 18:40:00.000 UTC' : null
    };
  }

  // A mock telemetry row like the seed script's LOSS_ABSORPTION profile (driver at the door); tests change one field at a time
  private static CARES_Delivery_Telemetry__c goodTelemetry() {
    return new CARES_Delivery_Telemetry__c(
      Order_ID__c = ORDER_ID,
      Driver_ID__c = 'DRV-TEST-1',
      Restaurant_Location__Latitude__s = RESTAURANT_LAT,
      Restaurant_Location__Longitude__s = RESTAURANT_LON,
      Dropoff_Location__Latitude__s = DROPOFF_LAT,
      Dropoff_Location__Longitude__s = DROPOFF_LON,
      Driver_Location__Latitude__s = AT_DOOR_LAT,
      Driver_Location__Longitude__s = AT_DOOR_LON,
      Driver_Wait_Seconds__c = 240,
      Driver_Calls__c = 1,
      Driver_Chats__c = 0,
      Driver_NonDelivery_Rate__c = 0.2,
      Driver_Delivery_Count__c = 900,
      Redispatch_Eligible__c = true
    );
  }

  /**
   * A high-trust customer (6 delivered orders, no claims), the telemetry row (or none),
   * and a user holding CARES_Stolen_Delayed_Access. Mock telemetry on, platform off.
   */
  private static void customer(CARES_Delivery_Telemetry__c telemetry) {
    Contact c = new Contact(LastName = 'SD Mock', Pronto_App_Account_Id__c = APP_ID);
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    contactId = c.Id;
    if (telemetry != null) {
      Database.insert(telemetry, AccessLevel.SYSTEM_MODE);
    }
    List<List<Object>> rows = new List<List<Object>>{ row(ORDER_ID, 'Delivered', '38.50') };
    for (Integer i = 1; i < 6; i++) {
      rows.add(row('PR-2409' + String.valueOf(10 + i) + '-OLDER0' + String.valueOf(i), 'Delivered', '20.00'));
    }
    CARES_OrderData.mockRows = rows;
    CARES_StolenDelayedPolicy.Settings s = new CARES_StolenDelayedPolicy.Settings();
    s.mockTelemetryEnabled = true;
    CARES_StolenDelayedPolicy.settingsOverride = s;
    sdUser = makeUser();
  }

  private static User makeUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    User u = new User(
      Alias = 'sdmock',
      Email = 'sd.mock@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'SD Mock',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'sd.mock.' + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'CARES_Stolen_Delayed_Access' LIMIT 1];
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    return u;
  }

  private static CARES_StolenDelayedEvaluateAction.Result evaluate() {
    CARES_StolenDelayedEvaluateAction.Request r = new CARES_StolenDelayedEvaluateAction.Request();
    r.contactId = contactId;
    r.orderId = ORDER_ID;
    r.customerReport = 'App says delivered but nothing at my door';
    CARES_StolenDelayedEvaluateAction.Result res;
    System.runAs(sdUser) {
      res = CARES_StolenDelayedEvaluateAction.evaluate(new List<CARES_StolenDelayedEvaluateAction.Request>{ r })[0];
    }
    return res;
  }

  private static CARES_StolenDelayedHandoffAction.Result handoff(String expectedDecision, String choice) {
    CARES_StolenDelayedHandoffAction.Request r = new CARES_StolenDelayedHandoffAction.Request();
    r.contactId = contactId;
    r.orderId = ORDER_ID;
    r.expectedDecision = expectedDecision;
    r.customerChoice = choice;
    CARES_StolenDelayedHandoffAction.Result res;
    System.runAs(sdUser) {
      res = CARES_StolenDelayedHandoffAction.handoff(new List<CARES_StolenDelayedHandoffAction.Request>{ r })[0];
    }
    return res;
  }

  // The matrix with mock telemetry

  @IsTest
  static void excellentDriverAndGpsMatchAbsorbTheLoss() {
    customer(goodTelemetry());
    CARES_StolenDelayedEvaluateAction.Result r = evaluate();
    Assert.areEqual(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, r.decision);
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL, r.driverCompensation);
    Assert.areEqual(CARES_StolenDelayedPolicy.RESTAURANT_REIMBURSE, r.restaurantReimbursement);
    Assert.isTrue(r.redispatchEligible);
    Assert.isTrue(r.orderTotal == 38.50, 'The order facts still come from the real order');
  }

  @IsTest
  static void driverOutsideTheGeofenceGetsAFullRefundAndWithholdsDriverPay() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Driver_Location__Latitude__s = FAR_AWAY_LAT;
    t.Driver_Location__Longitude__s = FAR_AWAY_LON;
    t.Driver_Wait_Seconds__c = 0;
    t.Driver_Calls__c = 0;
    customer(t);
    CARES_StolenDelayedEvaluateAction.Result r = evaluate();
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, r.decision);
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_WITHHOLD, r.driverCompensation);
    Assert.areEqual(CARES_StolenDelayedPolicy.RESTAURANT_NO_CHANGE, r.restaurantReimbursement);
  }

  @IsTest
  static void driverJustPastTheDoorIsStillInside() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Driver_Location__Latitude__s = PAST_DOOR_LAT;
    t.Driver_Location__Longitude__s = PAST_DOOR_LON;
    customer(t);
    CARES_StolenDelayedEvaluateAction.Result r = evaluate();
    Assert.areEqual(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, r.decision, 'The 50 m tolerance keeps the door inside');
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL, r.driverCompensation);
  }

  @IsTest
  static void driverNearTheRestaurantIsInsideToo() {
    // Known consequence of a trip-centered geofence (G-111): the restaurant end of the trip is inside
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Driver_Location__Latitude__s = NEAR_RESTAURANT_LAT;
    t.Driver_Location__Longitude__s = NEAR_RESTAURANT_LON;
    customer(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, evaluate().decision);
  }

  @IsTest
  static void rowWithoutLocationsUsesTheDistanceRule() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Driver_Location__Latitude__s = null;
    t.Driver_Location__Longitude__s = null;
    t.Driver_Distance_Meters__c = 75;
    t.Driver_Wait_Seconds__c = 10;
    t.Driver_Calls__c = 0;
    customer(t);
    CARES_StolenDelayedEvaluateAction.Result r = evaluate();
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, r.decision, '75 m is ambiguous under the old rule, not a match');
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_WITHHOLD, r.driverCompensation, 'Ambiguous and not diligent');
  }

  @IsTest
  static void driverWithAPoorRecordIsNotExcellent() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Driver_NonDelivery_Rate__c = 4;
    customer(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, evaluate().decision, '4% non-delivery is above the excellent limit');
  }

  @IsTest
  static void fraudFlagSendsTheClaimToAPerson() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Fraud_Pattern__c = true;
    customer(t);
    CARES_StolenDelayedEvaluateAction.Result r = evaluate();
    Assert.areEqual(CARES_StolenDelayedPolicy.ESCALATE, r.decision);
    Assert.areEqual('FRAUD_SIGNAL', r.reasonCode);
    Assert.isTrue(r.needsPerson);
  }

  @IsTest
  static void addressDuplicationSendsTheClaimToAPerson() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Address_Duplication__c = true;
    customer(t);
    Assert.areEqual('FRAUD_SIGNAL', evaluate().reasonCode);
  }

  @IsTest
  static void deviceDuplicationSendsTheClaimToAPerson() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Device_Duplication__c = true;
    customer(t);
    Assert.areEqual('FRAUD_SIGNAL', evaluate().reasonCode);
  }

  @IsTest
  static void orderWithoutARowKeepsTodaysBehavior() {
    customer(null);
    CARES_StolenDelayedEvaluateAction.Result r = evaluate();
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, r.decision);
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_HOLD_FOR_REVIEW, r.driverCompensation, 'GPS stays unknown');
    Assert.isFalse(r.redispatchEligible);
  }

  @IsTest
  static void mockTelemetryWinsOverThePlatform() {
    customer(goodTelemetry());
    CARES_StolenDelayedPolicy.settingsOverride.platformEnabled = true;
    CARES_StolenDelayedPlatformMock mock = new CARES_StolenDelayedPlatformMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Assert.areEqual(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, evaluate().decision);
    Assert.areEqual(0, mock.requests.size(), 'No platform call when the mock is on');
  }

  // Hand-off: re-dispatch and trust events as records

  @IsTest
  static void redispatchCreatesOneRequestAndReturnsItsReference() {
    customer(goodTelemetry());
    Test.startTest();
    CARES_StolenDelayedHandoffAction.Result first = handoff(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, 'REDISPATCH');
    CARES_StolenDelayedHandoffAction.Result again = handoff(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, 'REDISPATCH');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedHandoffAction.REDISPATCHED, first.handoffStatus);
    Assert.isTrue(first.redispatchReference.startsWith('RD-'), first.redispatchReference);
    Assert.areEqual(first.redispatchReference, again.redispatchReference, 'Asking again returns the same request');
    CARES_Redispatch__c rd = [SELECT Order_ID__c, Contact__c, Status__c FROM CARES_Redispatch__c WITH SYSTEM_MODE];
    Assert.areEqual(ORDER_ID, rd.Order_ID__c);
    Assert.areEqual(contactId, rd.Contact__c);
    Assert.areEqual('Requested', rd.Status__c);
    Assert.areEqual(2, [SELECT COUNT() FROM CARES_Trust_Event__c WITH SYSTEM_MODE], 'Customer and driver, once each');
  }

  @IsTest
  static void redispatchIsBlockedWhenTheRowSaysNotEligible() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Redispatch_Eligible__c = false;
    customer(t);
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, 'REDISPATCH');
    Assert.areEqual(CARES_StolenDelayedHandoffAction.BLOCKED, r.handoffStatus);
    Assert.areEqual('REDISPATCH_NOT_ELIGIBLE', r.reasonCode);
    Assert.areEqual(0, [SELECT COUNT() FROM CARES_Redispatch__c WITH SYSTEM_MODE]);
  }

  @IsTest
  static void refundChoiceWritesTrustEventsForBothProfiles() {
    customer(goodTelemetry());
    Test.startTest();
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, 'REFUND');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedHandoffAction.READY_FOR_REFUND, r.handoffStatus);
    Map<String, CARES_Trust_Event__c> bySubject = new Map<String, CARES_Trust_Event__c>();
    for (CARES_Trust_Event__c e : [
      SELECT Subject_Type__c, Event_Type__c, Order_ID__c, Contact__c, Driver_ID__c
      FROM CARES_Trust_Event__c
      WITH SYSTEM_MODE
    ]) {
      bySubject.put(e.Subject_Type__c, e);
    }
    Assert.areEqual(2, bySubject.size());
    CARES_Trust_Event__c customerEvent = bySubject.get(CARES_StolenDelayedTrustScoreJob.CUSTOMER);
    CARES_Trust_Event__c driverEvent = bySubject.get(CARES_StolenDelayedTrustScoreJob.DRIVER);
    Assert.areEqual(CARES_StolenDelayedTrustScoreJob.CUSTOMER_LOSS_ABSORBED, customerEvent.Event_Type__c);
    Assert.areEqual(contactId, customerEvent.Contact__c);
    Assert.areEqual(CARES_StolenDelayedTrustScoreJob.DRIVER_NO_FAULT, driverEvent.Event_Type__c);
    Assert.areEqual('DRV-TEST-1', driverEvent.Driver_ID__c, 'The driver id comes from the telemetry row');
    Assert.areEqual(ORDER_ID, driverEvent.Order_ID__c);
  }

  @IsTest
  static void withheldDriverPayFlagsTheDriver() {
    CARES_Delivery_Telemetry__c t = goodTelemetry();
    t.Driver_Location__Latitude__s = FAR_AWAY_LAT;
    t.Driver_Location__Longitude__s = FAR_AWAY_LON;
    customer(t);
    Test.startTest();
    handoff(CARES_StolenDelayedPolicy.FULL_REFUND, 'REFUND');
    Test.stopTest();
    Assert.areEqual(
      CARES_StolenDelayedTrustScoreJob.DRIVER_NON_DELIVERY_SUSPECTED,
      [SELECT Event_Type__c FROM CARES_Trust_Event__c WHERE Subject_Type__c = 'DRIVER' WITH SYSTEM_MODE].Event_Type__c
    );
  }

  @IsTest
  static void trustEventsAreNotDuplicated() {
    customer(goodTelemetry());
    System.runAs(sdUser) {
      for (Integer i = 0; i < 2; i++) {
        CARES_StolenDelayedMockTelemetry.recordTrustEvents(
          ORDER_ID,
          contactId,
          CARES_StolenDelayedTrustScoreJob.CUSTOMER_REFUNDED_NO_EVIDENCE,
          CARES_StolenDelayedTrustScoreJob.DRIVER_NO_FAULT
        );
      }
    }
    Assert.areEqual(2, [SELECT COUNT() FROM CARES_Trust_Event__c WITH SYSTEM_MODE]);
  }

  @IsTest
  static void withMockAndPlatformOffNothingIsWritten() {
    customer(goodTelemetry());
    CARES_StolenDelayedPolicy.settingsOverride = new CARES_StolenDelayedPolicy.Settings();
    Test.startTest();
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.FULL_REFUND, 'REFUND');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedHandoffAction.READY_FOR_REFUND, r.handoffStatus, 'Without the mock the row is ignored');
    Assert.areEqual(0, [SELECT COUNT() FROM CARES_Trust_Event__c WITH SYSTEM_MODE]);
    Assert.areEqual(0, [SELECT COUNT() FROM CARES_Redispatch__c WITH SYSTEM_MODE]);
  }
}
