@IsTest
private class CARES_StolenDelayedTimingTest {
  // An order placed at 18:00 UTC; the estimate, when there is one, is 18:39 (the data's median)
  private static final Datetime ORDERED = Datetime.newInstanceGmt(2024, 10, 18, 18, 0, 0);

  private static CARES_StolenDelayedPolicy.Settings settings() {
    return new CARES_StolenDelayedPolicy.Settings();
  }

  private static CARES_StolenDelayedTelemetry delivered(Integer tookMinutes) {
    CARES_StolenDelayedTelemetry t = base('DELIVERED');
    t.deliveryMinutes = tookMinutes;
    t.deliveredAt = ORDERED.addMinutes(tookMinutes);
    return t;
  }

  // On its way, the customer writing minutesSinceOrder after ordering (demo clock)
  private static CARES_StolenDelayedTelemetry onItsWay(Integer minutesSinceOrder, Boolean pickedUp) {
    CARES_StolenDelayedTelemetry t = base('IN_TRANSIT');
    t.acceptedAt = ORDERED.addMinutes(10);
    t.estimatedDeliveryAt = ORDERED.addMinutes(39);
    t.pickedUpAt = pickedUp ? ORDERED.addMinutes(20) : null;
    t.minutesSinceOrder = minutesSinceOrder;
    return t;
  }

  // A high-trust customer (6 orders, no claims), $48.00, USD
  private static CARES_StolenDelayedTelemetry base(String status) {
    CARES_StolenDelayedTelemetry t = new CARES_StolenDelayedTelemetry();
    t.orderFound = true;
    t.customerMatches = true;
    t.orderStatus = status;
    t.orderTotal = 48.00;
    t.currencyIsoCode = 'USD';
    t.priorClaimOnOrder = false;
    t.customerOrderCount = 6;
    t.customerClaimRate = 0;
    t.orderCreatedAt = ORDERED;
    return t;
  }

  private static CARES_StolenDelayedTiming.Result classify(CARES_StolenDelayedTelemetry t) {
    return CARES_StolenDelayedTiming.classify(t, settings(), System.now());
  }

  private static CARES_StolenDelayedPolicy.Outcome decide(CARES_StolenDelayedTelemetry t, String claim) {
    t.claimType = claim;
    return CARES_StolenDelayedPolicy.decide(t, settings());
  }

  // Delivered: minutes the delivery took against the 40-minute promise

  @IsTest
  static void deliveredWithinFortyMinutesIsOnTime() {
    CARES_StolenDelayedTiming.Result r = classify(delivered(40));
    Assert.areEqual(CARES_StolenDelayedTiming.ON_TIME, r.timing);
    Assert.areEqual(0, r.minutesLate);
    Assert.areEqual(CARES_StolenDelayedTiming.STAGE_DELIVERED, r.stage);
  }

  @IsTest
  static void deliveredUpToFifteenMinutesLateIsMinor() {
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_MINOR, classify(delivered(41)).timing);
    CARES_StolenDelayedTiming.Result r = classify(delivered(55));
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_MINOR, r.timing);
    Assert.areEqual(15, r.minutesLate);
  }

  @IsTest
  static void deliveredMoreThanFifteenMinutesLateIsSevere() {
    CARES_StolenDelayedTiming.Result r = classify(delivered(56));
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_SEVERE, r.timing);
    Assert.areEqual(16, r.minutesLate);
  }

  @IsTest
  static void deliveredWithoutDeliveryMinutesUsesTheDeliveredTime() {
    CARES_StolenDelayedTelemetry t = delivered(50);
    t.deliveryMinutes = null;
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_MINOR, classify(t).timing);
  }

  // On its way: now (demo clock) against the estimate

  @IsTest
  static void onItsWayBeforeTheEstimateIsNotLateYet() {
    CARES_StolenDelayedTiming.Result r = classify(onItsWay(30, false));
    Assert.areEqual(CARES_StolenDelayedTiming.NOT_LATE_YET, r.timing);
    Assert.areEqual(9, r.minutesUntilExpected, 'Estimate 18:39, now 18:30');
    Assert.areEqual(CARES_StolenDelayedTiming.STAGE_KITCHEN, r.stage);
  }

  @IsTest
  static void graceKeepsFiveMinutesLateNotLateYet() {
    Assert.areEqual(CARES_StolenDelayedTiming.NOT_LATE_YET, classify(onItsWay(44, true)).timing, '5 minutes late');
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_MINOR, classify(onItsWay(45, true)).timing, '6 minutes late');
  }

  @IsTest
  static void onItsWayLateBandsAreMinorSevereAndLost() {
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_MINOR, classify(onItsWay(54, false)).timing, '15 late');
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_SEVERE, classify(onItsWay(55, false)).timing, '16 late');
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_SEVERE, classify(onItsWay(99, false)).timing, '60 late');
    CARES_StolenDelayedTiming.Result lost = classify(onItsWay(100, false));
    Assert.areEqual(CARES_StolenDelayedTiming.LIKELY_LOST, lost.timing, '61 late');
    Assert.areEqual(61, lost.minutesLate);
  }

  @IsTest
  static void aCourierLegFarLongerThanAnyTripIsLikelyLost() {
    // Picked up at 18:20; at 19:36 the courier has had it 76 minutes, though it is only 57 minutes late
    Assert.areEqual(CARES_StolenDelayedTiming.LIKELY_LOST, classify(onItsWay(96, true)).timing);
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_SEVERE, classify(onItsWay(96, false)).timing, 'Still in the kitchen');
  }

  @IsTest
  static void withoutAnEstimateTheExpectedTimeIsTheFortyMinutePromise() {
    CARES_StolenDelayedTelemetry t = onItsWay(46, false);
    t.estimatedDeliveryAt = null;
    CARES_StolenDelayedTiming.Result r = classify(t);
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_MINOR, r.timing, '6 minutes past 18:40');
    Assert.areEqual(ORDERED.addMinutes(40), r.expectedAt);
  }

  @IsTest
  static void withoutTheDemoClockAnOldOrderStillOnItsWayIsLikelyLost() {
    // The data is from 2024-2025: on the real clock an order still on its way is long overdue
    Assert.areEqual(CARES_StolenDelayedTiming.LIKELY_LOST, classify(onItsWay(null, true)).timing);
  }

  @IsTest
  static void withoutAnOrderTimeTimingIsUnknown() {
    CARES_StolenDelayedTelemetry t = onItsWay(30, false);
    t.orderCreatedAt = null;
    Assert.areEqual(CARES_StolenDelayedTiming.UNKNOWN, classify(t).timing);
  }

  // Decisions

  @IsTest
  static void aMinorDelayGoesToRefundWithFifteenPercent() {
    CARES_StolenDelayedPolicy.Outcome d = decide(onItsWay(50, true), CARES_StolenDelayedPolicy.CLAIM_LATE);
    Assert.areEqual(CARES_StolenDelayedPolicy.DELAY, d.decision);
    Assert.areEqual('MINOR_DELAY', d.reasonCode);
    Assert.areEqual(CARES_StolenDelayedPolicy.SEVERITY_MINOR, d.delaySeverity);
    Assert.isTrue(d.delayValue == 7.20, '15% of $48.00, got ' + d.delayValue);
    Assert.isFalse(d.fullRefundApproved());
    Assert.isFalse(d.needsPerson());
  }

  @IsTest
  static void aSevereDelayGoesToRefundWithFiftyPercent() {
    CARES_StolenDelayedPolicy.Outcome d = decide(onItsWay(80, false), CARES_StolenDelayedPolicy.CLAIM_UNSURE);
    Assert.areEqual(CARES_StolenDelayedPolicy.DELAY, d.decision);
    Assert.areEqual(CARES_StolenDelayedPolicy.SEVERITY_SEVERE, d.delaySeverity);
    Assert.isTrue(d.delayValue == 24.00, '50% of $48.00');
  }

  @IsTest
  static void anOrderWithinItsEstimateIsNotLateYetWhateverTheCustomerSays() {
    CARES_StolenDelayedPolicy.Outcome d = decide(onItsWay(25, false), CARES_StolenDelayedPolicy.CLAIM_NOT_RECEIVED);
    Assert.areEqual(CARES_StolenDelayedPolicy.NOT_LATE_YET, d.decision);
    Assert.areEqual(14, d.minutesUntilExpected);
    Assert.isTrue(d.delayValue == 0);
  }

  @IsTest
  static void aDeliveredOrderTheCustomerCallsLateButOnTimeIsDeliveredOnTime() {
    CARES_StolenDelayedPolicy.Outcome d = decide(delivered(30), CARES_StolenDelayedPolicy.CLAIM_LATE);
    Assert.areEqual(CARES_StolenDelayedPolicy.DELIVERED_ON_TIME, d.decision);
    Assert.isTrue(d.deliveryMinutes == 30);
    Assert.isFalse(d.fullRefundApproved());
  }

  @IsTest
  static void aDeliveredOrderThatWasLateIsADelayNotAStolenOrder() {
    CARES_StolenDelayedPolicy.Outcome d = decide(delivered(58), CARES_StolenDelayedPolicy.CLAIM_LATE);
    Assert.areEqual(CARES_StolenDelayedPolicy.DELAY, d.decision);
    Assert.areEqual(CARES_StolenDelayedPolicy.SEVERITY_SEVERE, d.delaySeverity);
  }

  @IsTest
  static void aDeliveredOrderNotReceivedStillUsesTheStolenMatrix() {
    CARES_StolenDelayedPolicy.Outcome d = decide(delivered(58), CARES_StolenDelayedPolicy.CLAIM_NOT_RECEIVED);
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, d.decision, 'Late or not, it never arrived');
    Assert.areEqual('HIGH_TRUST_CUSTOMER', d.reasonCode);
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_HOLD_FOR_REVIEW, d.driverCompensation, 'No GPS');
  }

  @IsTest
  static void aLostOrderOfAHighTrustCustomerGetsAFullRefund() {
    CARES_StolenDelayedPolicy.Outcome d = decide(onItsWay(130, true), CARES_StolenDelayedPolicy.CLAIM_NOT_RECEIVED);
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, d.decision);
    Assert.areEqual('LOST_IN_TRANSIT', d.reasonCode);
    Assert.areEqual(CARES_StolenDelayedTiming.LIKELY_LOST, d.timing);
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_HOLD_FOR_REVIEW, d.driverCompensation);
    Assert.isTrue(d.fullRefundApproved());
  }

  @IsTest
  static void aLostOrderOfALowTrustCustomerGoesToManualReview() {
    CARES_StolenDelayedTelemetry t = onItsWay(130, true);
    t.customerClaimRate = 0.35;
    CARES_StolenDelayedPolicy.Outcome d = decide(t, CARES_StolenDelayedPolicy.CLAIM_NOT_RECEIVED);
    Assert.areEqual(CARES_StolenDelayedPolicy.MANUAL_REVIEW, d.decision);
    Assert.areEqual('LOW_TRUST_CUSTOMER', d.reasonCode);
  }

  @IsTest
  static void preChecksStillWinOverTiming() {
    CARES_StolenDelayedTelemetry t = onItsWay(50, true);
    t.orderTotal = 120;
    Assert.areEqual('HIGH_VALUE', decide(t, CARES_StolenDelayedPolicy.CLAIM_LATE).reasonCode);
    t = onItsWay(50, true);
    t.priorClaimOnOrder = true;
    Assert.areEqual('DUPLICATE_CLAIM', decide(t, CARES_StolenDelayedPolicy.CLAIM_LATE).reasonCode);
  }

  @IsTest
  static void unknownTimingKeepsTheStandardPath() {
    CARES_StolenDelayedTelemetry t = onItsWay(30, false);
    t.orderCreatedAt = null;
    CARES_StolenDelayedPolicy.Outcome d = decide(t, CARES_StolenDelayedPolicy.CLAIM_LATE);
    Assert.areEqual(CARES_StolenDelayedPolicy.STANDARD_PATH, d.decision);
    Assert.areEqual('NOT_MARKED_DELIVERED', d.reasonCode);
  }

  @IsTest
  static void claimTypeIsNormalized() {
    Assert.areEqual('LATE', CARES_StolenDelayedPolicy.normalizeClaim(' late '));
    Assert.areEqual('NOT_RECEIVED', CARES_StolenDelayedPolicy.normalizeClaim('not_received'));
    Assert.areEqual('UNSURE', CARES_StolenDelayedPolicy.normalizeClaim('it is cold'));
    Assert.areEqual('UNSURE', CARES_StolenDelayedPolicy.normalizeClaim(null));
  }

  // End to end through the agent action, on real-order rows with stage times and the demo clock

  private static final String APP_ID = 'PA-sd-timing-1';

  private static User stolenDelayedUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    User u = new User(
      Alias = 'sdtime',
      Email = 'sd.timing@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'SD Timing',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'sd.timing.' + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'CARES_Stolen_Delayed_Access' LIMIT 1];
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    return u;
  }
  private static final String LATE_ORDER = 'PR-241018-SDTIME1';

  @IsTest
  static void evaluateActionReadsStageTimesAndTheDemoClock() {
    Contact c = new Contact(LastName = 'SD Timing', Pronto_App_Account_Id__c = APP_ID);
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    // Demo clock: the customer writes 50 minutes after ordering
    Database.insert(
      new CARES_Delivery_Telemetry__c(Order_ID__c = LATE_ORDER, Minutes_Since_Order__c = 50),
      AccessLevel.SYSTEM_MODE
    );
    // Columns: customer, order, created, status, restaurant, total, items, estimate, eta, delivered, accepted, picked up, minutes
    List<List<Object>> rows = new List<List<Object>>{
      new List<Object>{
        APP_ID, LATE_ORDER, '2024-10-18 18:00:00.000 UTC', 'Out for Delivery', 'Test Kitchen', '48.00',
        'Cheeseburger; Large Fries', '2024-10-18 18:39:00.000 UTC', '39', null,
        '2024-10-18 18:10:00.000 UTC', '2024-10-18 18:20:00.000 UTC', null
      }
    };
    for (Integer i = 1; i < 6; i++) {
      rows.add(new List<Object>{ APP_ID, 'PR-2409' + String.valueOf(10 + i) + '-OLDER0' + i, '2024-09-1' + i + ' 18:00:00.000 UTC', 'Delivered', 'Test Kitchen', '20.00', 'Soup', null, null, '2024-09-1' + i + ' 18:30:00.000 UTC' });
    }
    CARES_OrderData.mockRows = rows;
    CARES_StolenDelayedPolicy.Settings s = new CARES_StolenDelayedPolicy.Settings();
    s.mockTelemetryEnabled = true;
    CARES_StolenDelayedPolicy.settingsOverride = s;

    CARES_StolenDelayedEvaluateAction.Request req = new CARES_StolenDelayedEvaluateAction.Request();
    req.contactId = c.Id;
    req.orderId = LATE_ORDER;
    req.customerReport = 'My order is really late';
    req.claimType = 'LATE';
    CARES_StolenDelayedEvaluateAction.Result r;
    // As the agent: the order link and the telemetry are read with the user's field access (G-100)
    System.runAs(stolenDelayedUser()) {
      r = CARES_StolenDelayedEvaluateAction.evaluate(
        new List<CARES_StolenDelayedEvaluateAction.Request>{ req }
      )[0];
    }
    Assert.areEqual(CARES_StolenDelayedPolicy.DELAY, r.decision, r.reasonCode);
    Assert.areEqual(CARES_StolenDelayedTiming.DELAYED_MINOR, r.timing, '11 minutes past 18:39');
    Assert.areEqual('MINOR', r.delaySeverity);
    Assert.areEqual(11, r.minutesLate);
    Assert.isTrue(r.delayValue == 7.20);
    Assert.isFalse(r.fullRefundApproved);
    Assert.areEqual(LATE_ORDER, r.orderId);
  }
}
