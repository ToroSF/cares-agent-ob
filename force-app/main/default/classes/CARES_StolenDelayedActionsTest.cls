@IsTest
private class CARES_StolenDelayedActionsTest {
  // Real-order fixtures (D-089): a Contact linked to an app account, and Order__dlm rows in CARES_OrderData.mockRows
  private static final String APP_ID = 'PA-sd-test-1';
  private static final String ORDER_ID = 'PR-241018-SDTEST1';
  // Trust job tests only: no record behind it
  private static final String FAKE_CONTACT_ID = '003000000000001';

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

  /**
   * The claimed order plus earlier delivered orders, for a customer with
   * `orders` non-canceled orders in total. Creates the customer and a user
   * holding CARES_Stolen_Delayed_Access (all DML happens here, before any callout).
   */
  private static void customer(Integer orders, String status, String total) {
    Contact c = new Contact(LastName = 'SD Orders', Pronto_App_Account_Id__c = APP_ID);
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    contactId = c.Id;
    List<List<Object>> rows = new List<List<Object>>{ row(ORDER_ID, status, total) };
    for (Integer i = 1; i < orders; i++) {
      rows.add(row('PR-2409' + String.valueOf(10 + i) + '-OLDER0' + String.valueOf(i).right(1), 'Delivered', '20.00'));
    }
    CARES_OrderData.mockRows = rows;
    sdUser = makeUser();
  }

  private static User makeUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    User u = new User(
      Alias = 'sdtest',
      Email = 'sd.test@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'SD Test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'sd.test.' + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'CARES_Stolen_Delayed_Access' LIMIT 1];
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    return u;
  }

  // A payout CARES already made, on this or another order (SYSTEM_MODE: test setup only)
  private static void resolution(String orderId) {
    Database.insert(
      new CARES_Resolution__c(
        Contact__c = contactId,
        Order_Id__c = orderId,
        Resolution_Type__c = 'Refund',
        Amount__c = 10.00,
        Status__c = 'Issued'
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  private static void platformOn() {
    CARES_StolenDelayedPolicy.Settings s = new CARES_StolenDelayedPolicy.Settings();
    s.platformEnabled = true;
    CARES_StolenDelayedPolicy.settingsOverride = s;
  }

  private static CARES_StolenDelayedPlatformMock mockWith(Map<String, Object> context) {
    CARES_StolenDelayedPlatformMock mock = new CARES_StolenDelayedPlatformMock()
      .respondWith('GET', '/orders/', 200, JSON.serialize(context))
      .respondWith('POST', '/orders/', 200, '{"redispatchId":"RD-77"}')
      .respondWith('POST', '/trust-events', 202, '{}');
    Test.setMock(HttpCalloutMock.class, mock);
    return mock;
  }

  private static CARES_StolenDelayedEvaluateAction.Result evaluateOrder(String orderId, String report) {
    CARES_StolenDelayedEvaluateAction.Request r = new CARES_StolenDelayedEvaluateAction.Request();
    r.contactId = contactId;
    r.orderId = orderId;
    r.customerReport = report;
    CARES_StolenDelayedEvaluateAction.Result res;
    System.runAs(sdUser) {
      res = CARES_StolenDelayedEvaluateAction.evaluate(
        new List<CARES_StolenDelayedEvaluateAction.Request>{ r }
      )[0];
    }
    return res;
  }

  private static CARES_StolenDelayedEvaluateAction.Result evaluate(String report) {
    return evaluateOrder(ORDER_ID, report);
  }

  private static CARES_StolenDelayedHandoffAction.Result handoff(String expectedDecision, String choice) {
    CARES_StolenDelayedHandoffAction.Request r = new CARES_StolenDelayedHandoffAction.Request();
    r.contactId = contactId;
    r.orderId = ORDER_ID;
    r.expectedDecision = expectedDecision;
    r.customerChoice = choice;
    CARES_StolenDelayedHandoffAction.Result res;
    System.runAs(sdUser) {
      res = CARES_StolenDelayedHandoffAction.handoff(
        new List<CARES_StolenDelayedHandoffAction.Request>{ r }
      )[0];
    }
    return res;
  }

  // Evaluate on the real orders, platform off (the default)

  @IsTest
  static void deliveredOrderOfAHighTrustCustomerGetsAFullRefund() {
    customer(6, 'Delivered', '38.50');
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('App says delivered but nothing at my door');
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, r.decision, 'Six orders and no claims is high trust (D-090)');
    Assert.isTrue(r.fullRefundApproved);
    Assert.areEqual(
      CARES_StolenDelayedPolicy.DRIVER_HOLD_FOR_REVIEW,
      r.driverCompensation,
      'GPS is unknown without the platform, so driver pay waits for a person'
    );
    Assert.areEqual(ORDER_ID, r.orderId);
    Assert.isTrue(r.orderTotal == 38.50);
    Assert.areEqual(UserInfo.getDefaultCurrency(), r.currencyIsoCode);
    Assert.isFalse(r.redispatchEligible, 'No platform, no re-dispatch');
  }

  @IsTest
  static void orderNotYetDeliveredUsesTheStandardPath() {
    customer(6, 'Out for Delivery', '38.50');
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('It is very late');
    Assert.areEqual(CARES_StolenDelayedPolicy.STANDARD_PATH, r.decision);
    Assert.areEqual('NOT_MARKED_DELIVERED', r.reasonCode);
    Assert.areEqual(ORDER_ID, r.orderId);
  }

  @IsTest
  static void canceledOrderGoesToAPerson() {
    customer(6, 'Canceled', '38.50');
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('It never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ESCALATE, r.decision);
    Assert.areEqual('ORDER_CANCELED', r.reasonCode, 'D-091');
    Assert.isTrue(r.needsPerson);
    Assert.areEqual(ORDER_ID, r.orderId);
  }

  @IsTest
  static void frequentClaimerGoesToManualReview() {
    customer(5, 'Delivered', '38.50');
    resolution('PR-240911-OLDER01');
    resolution('PR-240912-OLDER02');
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.MANUAL_REVIEW, r.decision, '2 claims over 5 orders is at least 20%');
    Assert.areEqual('LOW_TRUST_CUSTOMER', r.reasonCode);
  }

  @IsTest
  static void fewOrdersIsNotATrackRecordYet() {
    customer(2, 'Delivered', '38.50');
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.MANUAL_REVIEW, r.decision);
    Assert.areEqual('TRUST_NOT_ESTABLISHED', r.reasonCode);
  }

  @IsTest
  static void anOrderAlreadyPaidIsADuplicateClaim() {
    customer(6, 'Delivered', '38.50');
    resolution(ORDER_ID);
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ESCALATE, r.decision);
    Assert.areEqual('DUPLICATE_CLAIM', r.reasonCode);
  }

  @IsTest
  static void orderAboveTheEscalationAmountGoesToAPerson() {
    customer(6, 'Delivered', '120.00');
    Assert.areEqual('HIGH_VALUE', evaluate('Never arrived').reasonCode);
  }

  @IsTest
  static void unknownOrderIsNotFoundAndCanBeRetried() {
    customer(6, 'Delivered', '38.50');
    CARES_StolenDelayedEvaluateAction.Result r = evaluateOrder('PR-241020-NOPE001', 'Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ORDER_NOT_FOUND, r.decision);
    Assert.isFalse(r.isFinal);
    Assert.isTrue(r.orderTotal == 0);
  }

  @IsTest
  static void numberInAnotherFormatIsNotFoundButKeptForTheCase() {
    customer(6, 'Delivered', '38.50');
    CARES_StolenDelayedEvaluateAction.Result r = evaluateOrder('ORD-1001', 'Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ORDER_NOT_FOUND, r.decision);
    Assert.areEqual('INVALID_ORDER_ID', r.reasonCode);
    Assert.areEqual('ORD-1001', r.orderId, 'G-098: a well-formed number the customer gave is kept');
  }

  @IsTest
  static void customerWithoutAnAppAccountGoesToAPersonWithTheOrder() {
    customer(6, 'Delivered', '38.50');
    Database.update(new Contact(Id = contactId, Pronto_App_Account_Id__c = null), AccessLevel.SYSTEM_MODE);
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ESCALATE, r.decision);
    Assert.areEqual('NO_ACCOUNT_LINK', r.reasonCode);
    Assert.isTrue(r.needsPerson);
    Assert.areEqual(ORDER_ID, r.orderId, 'G-098');
  }

  @IsTest
  static void orderDataOutageEscalatesWithTheOrder() {
    customer(6, 'Delivered', '38.50');
    CARES_OrderData.mockQueryFails = true;
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ESCALATE, r.decision);
    Assert.areEqual('DATA_UNAVAILABLE', r.reasonCode);
    Assert.areEqual(ORDER_ID, r.orderId, 'The escalation case keeps the order the customer named (G-098)');
  }

  @IsTest
  static void evaluateWithoutContactEscalatesWithoutAnyLookup() {
    CARES_StolenDelayedEvaluateAction.Request r = new CARES_StolenDelayedEvaluateAction.Request();
    r.orderId = ORDER_ID;
    CARES_StolenDelayedEvaluateAction.Result res = CARES_StolenDelayedEvaluateAction.evaluate(
      new List<CARES_StolenDelayedEvaluateAction.Request>{ r }
    )[0];
    Assert.areEqual('NO_VERIFIED_CONTACT', res.reasonCode);
    Assert.areEqual(ORDER_ID, res.orderId, 'G-098');
  }

  @IsTest
  static void evaluateRejectsAMalformedOrderId() {
    customer(6, 'Delivered', '38.50');
    CARES_StolenDelayedEvaluateAction.Result res = evaluateOrder('../admin?x=1', 'Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ORDER_NOT_FOUND, res.decision);
    Assert.isNull(res.orderId, 'Only a well-formed order id goes on the case');
  }

  // Evaluate with the platform switched on: it adds what the order data lacks

  @IsTest
  static void platformAddsDriverDataForLossAbsorption() {
    customer(6, 'Delivered', '38.50');
    platformOn();
    Test.startTest();
    CARES_StolenDelayedPlatformMock mock = mockWith(CARES_StolenDelayedPlatformMock.goodContext());
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('App says delivered but nothing at my door');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, r.decision);
    Assert.isTrue(r.redispatchEligible);
    Assert.isTrue(r.orderTotal == 38.50, 'The order facts come from the real order, not the platform');
    Assert.areEqual(1, mock.requests.size(), 'One platform read');
    Assert.isTrue(mock.requests[0].getEndpoint().contains('customerRef=' + contactId));
  }

  @IsTest
  static void platformFailureStillDecidesFromTheOrder() {
    customer(6, 'Delivered', '38.50');
    platformOn();
    Test.startTest();
    Test.setMock(HttpCalloutMock.class, new CARES_StolenDelayedPlatformMock().respondWith('GET', '/orders/', 503, ''));
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('Never arrived');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, r.decision, 'A platform outage no longer escalates every claim');
  }

  // Hand-off

  @IsTest
  static void refundChoiceIsHandedToRefundWithoutMovingMoney() {
    customer(6, 'Delivered', '38.50');
    Test.startTest();
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.FULL_REFUND, 'wallet_credit');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedHandoffAction.READY_FOR_REFUND, r.handoffStatus);
    Assert.areEqual('WALLET_CREDIT', r.customerChoice);
    Assert.isTrue(r.orderTotal == 38.50);
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_HOLD_FOR_REVIEW, r.driverCompensation);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'],
      'No trust events without the platform'
    );
  }

  @IsTest
  static void withThePlatformTheHandoffQueuesTrustEvents() {
    customer(6, 'Delivered', '38.50');
    platformOn();
    Test.startTest();
    CARES_StolenDelayedPlatformMock mock = mockWith(CARES_StolenDelayedPlatformMock.goodContext());
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, 'REFUND');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedHandoffAction.READY_FOR_REFUND, r.handoffStatus);
    Assert.isTrue(r.lossAbsorption);
    Assert.areEqual(CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL, r.driverCompensation);
    Assert.areEqual(CARES_StolenDelayedPolicy.RESTAURANT_REIMBURSE, r.restaurantReimbursement);
    Assert.areEqual(2, mock.count('POST', '/trust-events'), 'Customer and driver flagged');
    for (HttpRequest req : mock.requests) {
      Assert.isFalse(req.getEndpoint().containsIgnoreCase('refund'));
      Assert.isFalse(req.getEndpoint().containsIgnoreCase('credit'));
      Assert.isFalse(req.getEndpoint().containsIgnoreCase('payout'));
    }
  }

  @IsTest
  static void redispatchChoiceSendsOrderAgain() {
    customer(6, 'Delivered', '38.50');
    platformOn();
    Test.startTest();
    CARES_StolenDelayedPlatformMock mock = mockWith(CARES_StolenDelayedPlatformMock.goodContext());
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, 'REDISPATCH');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedHandoffAction.REDISPATCHED, r.handoffStatus);
    Assert.areEqual('RD-77', r.redispatchReference);
    Assert.areEqual(1, mock.count('POST', '/redispatch'));
    for (HttpRequest req : mock.requests) {
      if (req.getMethod() == 'POST') {
        Assert.isNotNull(req.getHeader('Idempotency-Key'));
      }
    }
  }

  @IsTest
  static void redispatchWithoutThePlatformIsNotEligible() {
    customer(6, 'Delivered', '38.50');
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.FULL_REFUND, 'REDISPATCH');
    Assert.areEqual(CARES_StolenDelayedHandoffAction.BLOCKED, r.handoffStatus);
    Assert.areEqual('REDISPATCH_NOT_ELIGIBLE', r.reasonCode);
  }

  @IsTest
  static void failedRedispatchQueuesNoTrustEvents() {
    customer(6, 'Delivered', '38.50');
    platformOn();
    Test.startTest();
    Test.setMock(
      HttpCalloutMock.class,
      new CARES_StolenDelayedPlatformMock()
        .respondWith('GET', '/orders/', 200, JSON.serialize(CARES_StolenDelayedPlatformMock.goodContext()))
        .respondWith('POST', '/orders/', 500, '')
    );
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, 'REDISPATCH');
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedHandoffAction.FAILED, r.handoffStatus);
    Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable']);
  }

  @IsTest
  static void handoffBlocksWhenTheDecisionChanged() {
    customer(6, 'Delivered', '38.50');
    // Paid between the check and the hand-off: the re-check now finds a duplicate claim
    resolution(ORDER_ID);
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.FULL_REFUND, 'REFUND');
    Assert.areEqual(CARES_StolenDelayedHandoffAction.BLOCKED, r.handoffStatus);
    Assert.areEqual('DECISION_CHANGED', r.reasonCode);
    Assert.isTrue(r.orderTotal == 0);
  }

  @IsTest
  static void handoffRefusesDecisionsThatAreNotApproved() {
    customer(6, 'Delivered', '38.50');
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.MANUAL_REVIEW, 'REFUND');
    Assert.areEqual('NOT_APPROVED', r.reasonCode);
  }

  @IsTest
  static void handoffRefusesUnknownChoice() {
    customer(6, 'Delivered', '38.50');
    CARES_StolenDelayedHandoffAction.Result r = handoff(CARES_StolenDelayedPolicy.FULL_REFUND, 'double refund please');
    Assert.areEqual('INVALID_CHOICE', r.reasonCode);
  }

  // Trust events

  @IsTest
  static void trustEventsFollowTheDecision() {
    CARES_StolenDelayedPolicy.Outcome absorbed = new CARES_StolenDelayedPolicy.Outcome(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      'HIGH_TRUST_CONFLICT'
    );
    absorbed.driverCompensation = CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL;
    CARES_StolenDelayedTrustScoreJob job = new CARES_StolenDelayedTrustScoreJob(ORDER_ID, FAKE_CONTACT_ID, absorbed);
    Assert.areEqual(CARES_StolenDelayedTrustScoreJob.CUSTOMER_LOSS_ABSORBED, job.customerEvent);
    Assert.areEqual(CARES_StolenDelayedTrustScoreJob.DRIVER_NO_FAULT, job.driverEvent);

    CARES_StolenDelayedPolicy.Outcome withheld = new CARES_StolenDelayedPolicy.Outcome(
      CARES_StolenDelayedPolicy.FULL_REFUND,
      'HIGH_TRUST_CUSTOMER'
    );
    withheld.driverCompensation = CARES_StolenDelayedPolicy.DRIVER_WITHHOLD;
    job = new CARES_StolenDelayedTrustScoreJob(ORDER_ID, FAKE_CONTACT_ID, withheld);
    Assert.areEqual(CARES_StolenDelayedTrustScoreJob.CUSTOMER_REFUNDED_NO_EVIDENCE, job.customerEvent);
    Assert.areEqual(CARES_StolenDelayedTrustScoreJob.DRIVER_NON_DELIVERY_SUSPECTED, job.driverEvent);
  }

  @IsTest
  static void trustJobSurvivesPlatformErrors() {
    CARES_StolenDelayedPlatformMock mock = new CARES_StolenDelayedPlatformMock()
      .respondWith('POST', '/trust-events', 500, '');
    Test.setMock(HttpCalloutMock.class, mock);
    CARES_StolenDelayedPolicy.Outcome d = new CARES_StolenDelayedPolicy.Outcome(
      CARES_StolenDelayedPolicy.FULL_REFUND,
      'HIGH_TRUST_CUSTOMER'
    );
    Test.startTest();
    System.enqueueJob(new CARES_StolenDelayedTrustScoreJob(ORDER_ID, FAKE_CONTACT_ID, d));
    Test.stopTest();
    Assert.areEqual(2, mock.count('POST', '/trust-events'), 'Both events attempted');
  }
}
