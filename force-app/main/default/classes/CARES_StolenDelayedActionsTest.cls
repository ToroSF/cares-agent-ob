@IsTest
private class CARES_StolenDelayedActionsTest {
  private static final String CONTACT_ID = '003000000000001';
  private static final String ORDER_ID = 'ORD-1001';

  private static CARES_StolenDelayedPlatformMock mockWith(
    Map<String, Object> context
  ) {
    CARES_StolenDelayedPlatformMock mock = new CARES_StolenDelayedPlatformMock()
      .respondWith('GET', '/orders/', 200, JSON.serialize(context))
      .respondWith('POST', '/orders/', 200, '{"redispatchId":"RD-77"}')
      .respondWith('POST', '/trust-events', 202, '{}');
    Test.setMock(HttpCalloutMock.class, mock);
    return mock;
  }

  private static CARES_StolenDelayedEvaluateAction.Result evaluate(
    String report
  ) {
    CARES_StolenDelayedEvaluateAction.Request r = new CARES_StolenDelayedEvaluateAction.Request();
    r.contactId = CONTACT_ID;
    r.orderId = ORDER_ID;
    r.customerReport = report;
    return CARES_StolenDelayedEvaluateAction.evaluate(
      new List<CARES_StolenDelayedEvaluateAction.Request>{ r }
    )[0];
  }

  private static CARES_StolenDelayedHandoffAction.Result handoff(
    String expectedDecision,
    String choice
  ) {
    CARES_StolenDelayedHandoffAction.Request r = new CARES_StolenDelayedHandoffAction.Request();
    r.contactId = CONTACT_ID;
    r.orderId = ORDER_ID;
    r.expectedDecision = expectedDecision;
    r.customerChoice = choice;
    return CARES_StolenDelayedHandoffAction.handoff(
      new List<CARES_StolenDelayedHandoffAction.Request>{ r }
    )[0];
  }

  // Evaluate

  @IsTest
  static void evaluateReturnsLossAbsorptionContext() {
    CARES_StolenDelayedPlatformMock mock = mockWith(
      CARES_StolenDelayedPlatformMock.goodContext()
    );
    CARES_StolenDelayedEvaluateAction.Result r = evaluate(
      'App says delivered but nothing at my door'
    );
    Assert.areEqual(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, r.decision);
    Assert.isTrue(r.fullRefundApproved);
    Assert.isTrue(r.isFinal);
    Assert.isFalse(r.needsPerson);
    Assert.isTrue(r.orderTotal == 42.5);
    Assert.areEqual('USD', r.currencyIsoCode);
    Assert.areEqual(ORDER_ID, r.orderId);
    Assert.isTrue(r.redispatchEligible);
    Assert.areEqual(1, mock.requests.size(), 'Evaluate makes one read only');
    Assert.areEqual('GET', mock.requests[0].getMethod());
    Assert.isTrue(
      mock.requests[0].getEndpoint().contains('customerRef=' + CONTACT_ID)
    );
  }

  @IsTest
  static void evaluateTreats404AsOrderNotFound() {
    Test.setMock(
      HttpCalloutMock.class,
      new CARES_StolenDelayedPlatformMock()
        .respondWith('GET', '/orders/', 404, '')
    );
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ORDER_NOT_FOUND, r.decision);
    Assert.isFalse(r.isFinal);
    Assert.isTrue(r.orderTotal == 0);
  }

  @IsTest
  static void evaluateEscalatesWhenPlatformFails() {
    Test.setMock(
      HttpCalloutMock.class,
      new CARES_StolenDelayedPlatformMock()
        .respondWith('GET', '/orders/', 503, '')
    );
    CARES_StolenDelayedEvaluateAction.Result r = evaluate('Never arrived');
    Assert.areEqual(CARES_StolenDelayedPolicy.ESCALATE, r.decision);
    Assert.areEqual('DATA_UNAVAILABLE', r.reasonCode);
    Assert.isTrue(r.needsPerson);
    Assert.areEqual(ORDER_ID, r.orderId, 'The escalation case keeps the order the customer named (G-098)');
  }

  @IsTest
  static void evaluateEscalatesOnUnreadableBody() {
    Test.setMock(
      HttpCalloutMock.class,
      new CARES_StolenDelayedPlatformMock()
        .respondWith('GET', '/orders/', 200, 'not json')
    );
    Assert.areEqual('DATA_UNAVAILABLE', evaluate('Never arrived').reasonCode);
  }

  @IsTest
  static void evaluateWithoutContactEscalatesWithoutCallout() {
    CARES_StolenDelayedPlatformMock mock = mockWith(
      CARES_StolenDelayedPlatformMock.goodContext()
    );
    CARES_StolenDelayedEvaluateAction.Request r = new CARES_StolenDelayedEvaluateAction.Request();
    r.orderId = ORDER_ID;
    CARES_StolenDelayedEvaluateAction.Result res = CARES_StolenDelayedEvaluateAction.evaluate(
      new List<CARES_StolenDelayedEvaluateAction.Request>{ r }
    )[0];
    Assert.areEqual('NO_VERIFIED_CONTACT', res.reasonCode);
    Assert.areEqual(0, mock.requests.size());
    Assert.areEqual(ORDER_ID, res.orderId, 'G-098');
  }

  @IsTest
  static void evaluateRejectsMalformedOrderIdWithoutCallout() {
    CARES_StolenDelayedPlatformMock mock = mockWith(
      CARES_StolenDelayedPlatformMock.goodContext()
    );
    CARES_StolenDelayedEvaluateAction.Request r = new CARES_StolenDelayedEvaluateAction.Request();
    r.contactId = CONTACT_ID;
    r.orderId = '../admin?x=1';
    CARES_StolenDelayedEvaluateAction.Result res = CARES_StolenDelayedEvaluateAction.evaluate(
      new List<CARES_StolenDelayedEvaluateAction.Request>{ r }
    )[0];
    Assert.areEqual(CARES_StolenDelayedPolicy.ORDER_NOT_FOUND, res.decision);
    Assert.areEqual(0, mock.requests.size());
  }

  // Hand-off

  @IsTest
  static void refundChoiceIsHandedToRefundWithoutMovingMoney() {
    CARES_StolenDelayedPlatformMock mock = mockWith(
      CARES_StolenDelayedPlatformMock.goodContext()
    );
    Test.startTest();
    CARES_StolenDelayedHandoffAction.Result r = handoff(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      'wallet_credit'
    );
    Test.stopTest();

    Assert.areEqual(
      CARES_StolenDelayedHandoffAction.READY_FOR_REFUND,
      r.handoffStatus
    );
    Assert.areEqual('WALLET_CREDIT', r.customerChoice);
    Assert.isTrue(r.orderTotal == 42.5);
    Assert.isTrue(r.lossAbsorption);
    Assert.areEqual(
      CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL,
      r.driverCompensation
    );
    Assert.areEqual(
      CARES_StolenDelayedPolicy.RESTAURANT_REIMBURSE,
      r.restaurantReimbursement
    );
    Assert.areEqual(0, mock.count('POST', '/redispatch'));
    Assert.areEqual(
      2,
      mock.count('POST', '/trust-events'),
      'Customer and driver flagged'
    );
    for (HttpRequest req : mock.requests) {
      Assert.isFalse(req.getEndpoint().containsIgnoreCase('refund'));
      Assert.isFalse(req.getEndpoint().containsIgnoreCase('credit'));
      Assert.isFalse(req.getEndpoint().containsIgnoreCase('payout'));
    }
  }

  @IsTest
  static void redispatchChoiceSendsOrderAgain() {
    CARES_StolenDelayedPlatformMock mock = mockWith(
      CARES_StolenDelayedPlatformMock.goodContext()
    );
    Test.startTest();
    CARES_StolenDelayedHandoffAction.Result r = handoff(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      'REDISPATCH'
    );
    Test.stopTest();

    Assert.areEqual(
      CARES_StolenDelayedHandoffAction.REDISPATCHED,
      r.handoffStatus
    );
    Assert.areEqual('RD-77', r.redispatchReference);
    Assert.areEqual(1, mock.count('POST', '/redispatch'));
    Assert.areEqual(2, mock.count('POST', '/trust-events'));
    for (HttpRequest req : mock.requests) {
      if (req.getMethod() == 'POST') {
        Assert.isNotNull(req.getHeader('Idempotency-Key'));
      }
    }
  }

  @IsTest
  static void redispatchIsBlockedWhenNotEligible() {
    Map<String, Object> ctx = CARES_StolenDelayedPlatformMock.goodContext();
    ctx.put('redispatchEligible', false);
    CARES_StolenDelayedPlatformMock mock = mockWith(ctx);
    CARES_StolenDelayedHandoffAction.Result r = handoff(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      'REDISPATCH'
    );
    Assert.areEqual(CARES_StolenDelayedHandoffAction.BLOCKED, r.handoffStatus);
    Assert.areEqual('REDISPATCH_NOT_ELIGIBLE', r.reasonCode);
    Assert.areEqual(0, mock.count('POST', '/redispatch'));
  }

  @IsTest
  static void failedRedispatchQueuesNoTrustEvents() {
    Test.setMock(
      HttpCalloutMock.class,
      new CARES_StolenDelayedPlatformMock()
        .respondWith(
          'GET',
          '/orders/',
          200,
          JSON.serialize(CARES_StolenDelayedPlatformMock.goodContext())
        )
        .respondWith('POST', '/orders/', 500, '')
    );
    Test.startTest();
    CARES_StolenDelayedHandoffAction.Result r = handoff(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      'REDISPATCH'
    );
    Test.stopTest();
    Assert.areEqual(CARES_StolenDelayedHandoffAction.FAILED, r.handoffStatus);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable']
    );
  }

  @IsTest
  static void handoffBlocksWhenDecisionChanged() {
    Map<String, Object> ctx = CARES_StolenDelayedPlatformMock.goodContext();
    ctx.put('fraudPatternDetected', true);
    mockWith(ctx);
    CARES_StolenDelayedHandoffAction.Result r = handoff(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      'REFUND'
    );
    Assert.areEqual(CARES_StolenDelayedHandoffAction.BLOCKED, r.handoffStatus);
    Assert.areEqual('DECISION_CHANGED', r.reasonCode);
    Assert.isTrue(r.orderTotal == 0);
  }

  @IsTest
  static void handoffRefusesDecisionsThatAreNotApproved() {
    CARES_StolenDelayedPlatformMock mock = mockWith(
      CARES_StolenDelayedPlatformMock.goodContext()
    );
    CARES_StolenDelayedHandoffAction.Result r = handoff(
      CARES_StolenDelayedPolicy.MANUAL_REVIEW,
      'REFUND'
    );
    Assert.areEqual('NOT_APPROVED', r.reasonCode);
    Assert.areEqual(0, mock.requests.size());
  }

  @IsTest
  static void handoffRefusesUnknownChoice() {
    CARES_StolenDelayedPlatformMock mock = mockWith(
      CARES_StolenDelayedPlatformMock.goodContext()
    );
    CARES_StolenDelayedHandoffAction.Result r = handoff(
      CARES_StolenDelayedPolicy.FULL_REFUND,
      'double refund please'
    );
    Assert.areEqual('INVALID_CHOICE', r.reasonCode);
    Assert.areEqual(0, mock.requests.size());
  }

  // Trust events

  @IsTest
  static void trustEventsFollowTheDecision() {
    CARES_StolenDelayedPolicy.Outcome absorbed = new CARES_StolenDelayedPolicy.Outcome(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      'HIGH_TRUST_CONFLICT'
    );
    absorbed.driverCompensation = CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL;
    CARES_StolenDelayedTrustScoreJob job = new CARES_StolenDelayedTrustScoreJob(
      ORDER_ID,
      CONTACT_ID,
      absorbed
    );
    Assert.areEqual(
      CARES_StolenDelayedTrustScoreJob.CUSTOMER_LOSS_ABSORBED,
      job.customerEvent
    );
    Assert.areEqual(
      CARES_StolenDelayedTrustScoreJob.DRIVER_NO_FAULT,
      job.driverEvent
    );

    CARES_StolenDelayedPolicy.Outcome withheld = new CARES_StolenDelayedPolicy.Outcome(
      CARES_StolenDelayedPolicy.FULL_REFUND,
      'HIGH_TRUST_CUSTOMER'
    );
    withheld.driverCompensation = CARES_StolenDelayedPolicy.DRIVER_WITHHOLD;
    job = new CARES_StolenDelayedTrustScoreJob(ORDER_ID, CONTACT_ID, withheld);
    Assert.areEqual(
      CARES_StolenDelayedTrustScoreJob.CUSTOMER_REFUNDED_NO_EVIDENCE,
      job.customerEvent
    );
    Assert.areEqual(
      CARES_StolenDelayedTrustScoreJob.DRIVER_NON_DELIVERY_SUSPECTED,
      job.driverEvent
    );
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
    System.enqueueJob(
      new CARES_StolenDelayedTrustScoreJob(ORDER_ID, CONTACT_ID, d)
    );
    Test.stopTest();
    Assert.areEqual(
      2,
      mock.count('POST', '/trust-events'),
      'Both events attempted'
    );
  }
}
