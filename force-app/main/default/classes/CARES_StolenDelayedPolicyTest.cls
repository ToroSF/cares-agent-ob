@IsTest
private class CARES_StolenDelayedPolicyTest {
  private static CARES_StolenDelayedPolicy.Settings settings() {
    return new CARES_StolenDelayedPolicy.Settings();
  }

  private static CARES_StolenDelayedTelemetry good() {
    return CARES_StolenDelayedTelemetry.parse(
      JSON.serialize(CARES_StolenDelayedPlatformMock.goodContext())
    );
  }

  private static CARES_StolenDelayedPolicy.Outcome decide(
    CARES_StolenDelayedTelemetry t
  ) {
    return CARES_StolenDelayedPolicy.decide(t, settings());
  }

  // Matrix

  @IsTest
  static void highTrustBothExcellentAndGpsMatchAbsorbsLoss() {
    CARES_StolenDelayedPolicy.Outcome d = decide(good());
    Assert.areEqual(CARES_StolenDelayedPolicy.LOSS_ABSORPTION, d.decision);
    Assert.areEqual(
      CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL,
      d.driverCompensation
    );
    Assert.areEqual(
      CARES_StolenDelayedPolicy.RESTAURANT_REIMBURSE,
      d.restaurantReimbursement
    );
    Assert.isTrue(d.fullRefundApproved());
    Assert.isFalse(d.needsPerson());
  }

  @IsTest
  static void highTrustCustomerWithGpsMismatchGetsFullRefundAndDriverPayWithheld() {
    CARES_StolenDelayedTelemetry t = good();
    t.driverDistanceMeters = 450;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, d.decision);
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MISMATCH, d.gpsResult);
    Assert.areEqual(
      CARES_StolenDelayedPolicy.DRIVER_WITHHOLD,
      d.driverCompensation
    );
    Assert.areEqual(
      CARES_StolenDelayedPolicy.RESTAURANT_NO_CHANGE,
      d.restaurantReimbursement
    );
  }

  @IsTest
  static void highTrustCustomerWithAverageDriverAndGpsMatchGetsFullRefundDriverPaid() {
    CARES_StolenDelayedTelemetry t = good();
    t.driverNonDeliveryRate = 0.04;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, d.decision);
    Assert.areEqual(
      CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL,
      d.driverCompensation
    );
  }

  @IsTest
  static void ambiguousGpsWithoutDiligenceWithholdsDriverPay() {
    CARES_StolenDelayedTelemetry t = good();
    t.driverDistanceMeters = 75;
    t.driverWaitSeconds = 10;
    t.driverCallsToCustomer = 0;
    t.driverChatsToCustomer = 0;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, d.decision);
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_AMBIGUOUS, d.gpsResult);
    Assert.areEqual(
      CARES_StolenDelayedPolicy.DRIVER_WITHHOLD,
      d.driverCompensation
    );
  }

  @IsTest
  static void ambiguousGpsWithContactAttemptPaysDriver() {
    CARES_StolenDelayedTelemetry t = good();
    t.driverDistanceMeters = 75;
    t.driverWaitSeconds = 10;
    t.driverCallsToCustomer = 0;
    t.driverChatsToCustomer = 2;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.isTrue(d.driverDiligent);
    Assert.areEqual(
      CARES_StolenDelayedPolicy.DRIVER_PAY_IN_FULL,
      d.driverCompensation
    );
  }

  @IsTest
  static void unknownGpsHoldsDriverPayForReview() {
    CARES_StolenDelayedTelemetry t = good();
    t.driverDistanceMeters = null;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.FULL_REFUND, d.decision);
    Assert.areEqual(
      CARES_StolenDelayedPolicy.DRIVER_HOLD_FOR_REVIEW,
      d.driverCompensation
    );
  }

  @IsTest
  static void lowTrustCustomerGoesToManualReview() {
    CARES_StolenDelayedTelemetry t = good();
    t.customerClaimRate = 0.35;
    t.driverDistanceMeters = 900; // even with strong evidence for the customer
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.MANUAL_REVIEW, d.decision);
    Assert.areEqual('LOW_TRUST_CUSTOMER', d.reasonCode);
    Assert.isFalse(d.fullRefundApproved());
    Assert.isTrue(d.needsPerson());
  }

  @IsTest
  static void lowRateWithFewOrdersIsNotHighTrust() {
    CARES_StolenDelayedTelemetry t = good();
    t.customerOrderCount = 2;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.TRUST_MEDIUM, d.customerTrust);
    Assert.areEqual(CARES_StolenDelayedPolicy.MANUAL_REVIEW, d.decision);
  }

  @IsTest
  static void unknownClaimRateGoesToManualReview() {
    CARES_StolenDelayedTelemetry t = good();
    t.customerClaimRate = null;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.TRUST_UNKNOWN, d.customerTrust);
    Assert.areEqual(CARES_StolenDelayedPolicy.MANUAL_REVIEW, d.decision);
  }

  @IsTest
  static void claimRateThresholdBoundaries() {
    CARES_StolenDelayedTelemetry t = good();
    t.customerClaimRate = 0.05;
    Assert.areEqual(
      CARES_StolenDelayedPolicy.TRUST_HIGH,
      CARES_StolenDelayedPolicy.customerTrust(t, settings())
    );
    t.customerClaimRate = 0.20;
    Assert.areEqual(
      CARES_StolenDelayedPolicy.TRUST_LOW,
      CARES_StolenDelayedPolicy.customerTrust(t, settings())
    );
  }

  @IsTest
  static void gpsThresholdBoundaries() {
    CARES_StolenDelayedTelemetry t = good();
    t.driverDistanceMeters = 50;
    Assert.areEqual(
      CARES_StolenDelayedPolicy.GPS_MATCH,
      CARES_StolenDelayedPolicy.gpsResult(t, settings())
    );
    t.driverDistanceMeters = 100;
    Assert.areEqual(
      CARES_StolenDelayedPolicy.GPS_AMBIGUOUS,
      CARES_StolenDelayedPolicy.gpsResult(t, settings())
    );
    t.driverDistanceMeters = 100.5;
    Assert.areEqual(
      CARES_StolenDelayedPolicy.GPS_MISMATCH,
      CARES_StolenDelayedPolicy.gpsResult(t, settings())
    );
  }

  // Standard path

  @IsTest
  static void photoFromEitherSideUsesStandardPath() {
    CARES_StolenDelayedTelemetry t = good();
    t.driverPhotoProvided = true;
    Assert.areEqual('PHOTO_EVIDENCE', decide(t).reasonCode);
    t.driverPhotoProvided = false;
    t.customerPhotoProvided = true;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.STANDARD_PATH, d.decision);
    Assert.isFalse(d.fullRefundApproved());
  }

  @IsTest
  static void orderNotMarkedDeliveredUsesStandardPath() {
    CARES_StolenDelayedTelemetry t = good();
    t.orderStatus = 'IN_TRANSIT';
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.STANDARD_PATH, d.decision);
    Assert.areEqual('NOT_MARKED_DELIVERED', d.reasonCode);
  }

  // Human escalation

  @IsTest
  static void orderOverOneHundredUsdEscalates() {
    CARES_StolenDelayedTelemetry t = good();
    t.orderTotal = 100.01;
    Assert.areEqual('HIGH_VALUE', decide(t).reasonCode);
    t.orderTotal = 100;
    Assert.areEqual(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      decide(t).decision
    );
  }

  @IsTest
  static void highValueCheckRunsBeforePhotoCheck() {
    CARES_StolenDelayedTelemetry t = good();
    t.orderTotal = 250;
    t.driverPhotoProvided = true;
    Assert.areEqual(CARES_StolenDelayedPolicy.ESCALATE, decide(t).decision);
  }

  @IsTest
  static void foreignCurrencyIsConvertedBeforeTheLimit() {
    CARES_StolenDelayedPolicy.conversionRates = new Map<String, Decimal>{
      'USD' => 1,
      'MXN' => 20
    };
    CARES_StolenDelayedTelemetry t = good();
    t.currencyIsoCode = 'MXN';
    t.orderTotal = 1900; // 95 USD
    Assert.areEqual(
      CARES_StolenDelayedPolicy.LOSS_ABSORPTION,
      decide(t).decision
    );
    t.orderTotal = 2100; // 105 USD
    Assert.areEqual('HIGH_VALUE', decide(t).reasonCode);
  }

  @IsTest
  static void currencyWithoutRateEscalates() {
    CARES_StolenDelayedPolicy.conversionRates = new Map<String, Decimal>{
      'USD' => 1
    };
    CARES_StolenDelayedTelemetry t = good();
    t.currencyIsoCode = 'EUR';
    Assert.areEqual('AMOUNT_UNVERIFIED', decide(t).reasonCode);
    t.currencyIsoCode = null;
    Assert.areEqual('AMOUNT_UNVERIFIED', decide(t).reasonCode);
  }

  @IsTest
  static void eachFraudSignalEscalates() {
    CARES_StolenDelayedTelemetry t = good();
    t.fraudPatternDetected = true;
    Assert.areEqual('FRAUD_SIGNAL', decide(t).reasonCode);
    t = good();
    t.deviceDuplicationDetected = true;
    Assert.areEqual('FRAUD_SIGNAL', decide(t).reasonCode);
    t = good();
    t.addressDuplicationDetected = true;
    Assert.areEqual('FRAUD_SIGNAL', decide(t).reasonCode);
  }

  @IsTest
  static void secondClaimOnSameOrderEscalates() {
    CARES_StolenDelayedTelemetry t = good();
    t.priorClaimOnOrder = true;
    Assert.areEqual('DUPLICATE_CLAIM', decide(t).reasonCode);
  }

  @IsTest
  static void orderOfAnotherCustomerIsNotFound() {
    CARES_StolenDelayedTelemetry t = good();
    t.customerMatches = false;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.ORDER_NOT_FOUND, d.decision);
    Assert.isFalse(d.isFinal());
    Assert.isNull(
      d.orderTotal,
      'No order details may leak for another customer'
    );
  }

  @IsTest
  static void missingTelemetryEscalates() {
    Assert.areEqual('DATA_UNAVAILABLE', decide(null).reasonCode);
  }

  // Keywords

  @IsTest
  static void sensitiveKeywordsMatchWholeWordsOnly() {
    CARES_StolenDelayedPolicy.Settings s = settings();
    Assert.isTrue(
      CARES_StolenDelayedPolicy.containsSensitiveKeyword(
        'The driver THREATENED me at the door',
        s
      )
    );
    Assert.isTrue(
      CARES_StolenDelayedPolicy.containsSensitiveKeyword(
        'I will talk to my lawyer',
        s
      )
    );
    Assert.isFalse(
      CARES_StolenDelayedPolicy.containsSensitiveKeyword(
        'There is an issue with my order, it never came',
        s
      )
    );
    Assert.isFalse(CARES_StolenDelayedPolicy.containsSensitiveKeyword(null, s));
  }

  @IsTest
  static void sensitiveReportEscalatesBeforeAnyCallout() {
    CARES_StolenDelayedPlatformMock mock = new CARES_StolenDelayedPlatformMock();
    Test.setMock(HttpCalloutMock.class, mock);
    CARES_StolenDelayedPolicy.Outcome d = CARES_StolenDelayedPolicy.evaluate(
      '003000000000001',
      'ORD-1',
      'The driver assaulted me'
    );
    Assert.areEqual('SENSITIVE_TOPIC', d.reasonCode);
    Assert.areEqual(0, mock.requests.size());
  }

  // Settings

  @IsTest
  static void settingsLoadWithoutError() {
    CARES_StolenDelayedPolicy.Settings s = CARES_StolenDelayedPolicy.loadSettings();
    Assert.isNotNull(s.escalationAmountUsd);
    Assert.isTrue(s.gpsMatchMaxMeters <= s.gpsMismatchMinMeters);
    Assert.isTrue(s.highTrustMaxClaimRate < s.lowTrustMinClaimRate);
  }

  @IsTest
  static void settingsOverrideChangesTheMatrix() {
    CARES_StolenDelayedPolicy.Settings s = settings();
    s.escalationAmountUsd = 30;
    CARES_StolenDelayedPolicy.settingsOverride = s;
    Assert.areEqual(
      'HIGH_VALUE',
      CARES_StolenDelayedPolicy.decide(
          good(),
          CARES_StolenDelayedPolicy.loadSettings()
        )
        .reasonCode
    );
  }
}
