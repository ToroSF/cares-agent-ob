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
  static void canceledOrderEscalatesBeforeTheValueAndTrustRules() {
    CARES_StolenDelayedTelemetry t = good();
    t.orderStatus = CARES_StolenDelayedOrderSource.CANCELED;
    t.orderTotal = 500;
    CARES_StolenDelayedPolicy.Outcome d = decide(t);
    Assert.areEqual(CARES_StolenDelayedPolicy.ESCALATE, d.decision);
    Assert.areEqual('ORDER_CANCELED', d.reasonCode, 'D-091, ahead of HIGH_VALUE');
  }

  @IsTest
  static void orderDataStatusWordsMapToTheDeliveryStatus() {
    Assert.areEqual('DELIVERED', CARES_StolenDelayedOrderSource.deliveryStatus('Delivered'));
    Assert.areEqual('CANCELED', CARES_StolenDelayedOrderSource.deliveryStatus('Canceled'));
    for (String onTheWay : new List<String>{ 'Preparing', 'PickedUp', 'Out for Delivery', '' }) {
      Assert.areEqual('IN_TRANSIT', CARES_StolenDelayedOrderSource.deliveryStatus(onTheWay), onTheWay);
    }
  }

  @IsTest
  static void platformAddsOnlyWhatTheOrderDataLacks() {
    CARES_StolenDelayedTelemetry t = new CARES_StolenDelayedTelemetry();
    t.orderFound = true;
    t.customerMatches = true;
    t.orderStatus = 'DELIVERED';
    t.orderTotal = 38.50;
    t.customerClaimRate = 0.0;
    t.customerOrderCount = 6;
    CARES_StolenDelayedTelemetry platform = good();
    platform.orderTotal = 999;
    platform.customerClaimRate = 0.9;
    CARES_StolenDelayedPolicy.enrich(t, platform);
    Assert.isTrue(t.orderTotal == 38.50, 'Order facts stay from the real order');
    Assert.isTrue(t.customerClaimRate == 0.0, 'Trust stays from CARES counts (D-090)');
    Assert.isTrue(t.driverDistanceMeters == 20, 'GPS comes from the platform');
    Assert.isTrue(t.redispatchEligible);
  }

  @IsTest
  static void aPlatformAnswerForAnotherCustomerAddsNothing() {
    CARES_StolenDelayedTelemetry t = new CARES_StolenDelayedTelemetry();
    CARES_StolenDelayedTelemetry platform = good();
    platform.customerMatches = false;
    CARES_StolenDelayedPolicy.enrich(t, platform);
    Assert.isNull(t.driverDistanceMeters);
    CARES_StolenDelayedPolicy.enrich(t, null);
    Assert.isNull(t.redispatchEligible);
  }

  @IsTest
  static void thePlatformIsOffByDefault() {
    Assert.isFalse(CARES_StolenDelayedPolicy.loadSettings().platformEnabled, 'Off until the Named Credential exists (D-089)');
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
    Assert.areEqual('ORD-1', d.orderId, 'G-098: the case keeps the order the customer named');
  }

  @IsTest
  static void earlyEscalationDropsAMalformedOrderId() {
    CARES_StolenDelayedPolicy.Outcome d = CARES_StolenDelayedPolicy.evaluate(
      '003000000000001',
      '../admin?x=1',
      'The driver assaulted me'
    );
    Assert.areEqual('SENSITIVE_TOPIC', d.reasonCode);
    Assert.isNull(d.orderId, 'Only a well-formed order id goes on the case');
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

  // Trip geofence (D-097): a 1,025 m trip, radius = 512 m + 50 m tolerance, centered on its midpoint

  private static CARES_StolenDelayedTelemetry trip(Decimal driverLat, Decimal driverLon) {
    CARES_StolenDelayedTelemetry t = good();
    t.restaurantLatitude = 40.741600;
    t.restaurantLongitude = -73.990000;
    t.dropoffLatitude = 40.750000;
    t.dropoffLongitude = -73.985000;
    t.driverLatitude = driverLat;
    t.driverLongitude = driverLon;
    return t;
  }

  @IsTest
  static void geofenceIsCenteredOnTheMidpointWithHalfTheTripPlusTolerance() {
    Location restaurant = Location.newInstance(40.741600, -73.990000);
    Location dropoff = Location.newInstance(40.750000, -73.985000);
    Location center = CARES_StolenDelayedPolicy.midpoint(restaurant, dropoff);
    Assert.isTrue(Math.abs(center.getLatitude() - 40.745800) < 0.00001, String.valueOf(center.getLatitude()));
    Assert.isTrue(Math.abs(center.getLongitude() - -73.987500) < 0.00001, String.valueOf(center.getLongitude()));
    Decimal radius = CARES_StolenDelayedPolicy.geofenceRadiusMeters(restaurant, dropoff, settings());
    Assert.isTrue(Math.abs(radius - 562.3) < 1, 'Half of 1,024.6 m plus 50 m, got ' + radius);
  }

  @IsTest
  static void driverInsideTheGeofenceIsAMatchAndOutsideIsAMismatch() {
    Assert.areEqual(
      CARES_StolenDelayedPolicy.GPS_MATCH,
      CARES_StolenDelayedPolicy.gpsResult(trip(40.749918, -73.985049), settings()),
      'At the door'
    );
    Assert.areEqual(
      CARES_StolenDelayedPolicy.GPS_MISMATCH,
      CARES_StolenDelayedPolicy.gpsResult(trip(40.760000, -73.970000), settings()),
      '2.2 km from the center'
    );
  }

  @IsTest
  static void geofenceNeverReturnsAmbiguous() {
    CARES_StolenDelayedTelemetry t = trip(40.749918, -73.985049);
    t.driverDistanceMeters = 75; // ambiguous under the old rule; ignored when there are locations
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MATCH, CARES_StolenDelayedPolicy.gpsResult(t, settings()));
  }

  @IsTest
  static void toleranceKeepsADriverJustPastTheDoorInside() {
    CARES_StolenDelayedTelemetry pastDoor = trip(40.750123, -73.984927);
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MATCH, CARES_StolenDelayedPolicy.gpsResult(pastDoor, settings()));
    // Why the tolerance exists: without it the door is on the edge and 15 m past it is outside
    CARES_StolenDelayedPolicy.Settings noTolerance = settings();
    noTolerance.gpsMatchMaxMeters = 0;
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MISMATCH, CARES_StolenDelayedPolicy.gpsResult(pastDoor, noTolerance));
  }

  @IsTest
  static void driverAtTheRestaurantIsInside() {
    // Known consequence (G-111): the restaurant end of the trip is inside the geofence
    Assert.areEqual(
      CARES_StolenDelayedPolicy.GPS_MATCH,
      CARES_StolenDelayedPolicy.gpsResult(trip(40.741600, -73.990000), settings())
    );
  }

  @IsTest
  static void aVeryShortTripStillHasTheToleranceAsRadius() {
    Location restaurant = Location.newInstance(40.741600, -73.990000);
    Location dropoff = Location.newInstance(40.741700, -73.990000); // about 11 m
    Decimal radius = CARES_StolenDelayedPolicy.geofenceRadiusMeters(restaurant, dropoff, settings());
    Assert.isTrue(radius >= 50 && radius < 60, String.valueOf(radius));
  }

  @IsTest
  static void partialCoordinatesFallBackToTheDistanceRule() {
    CARES_StolenDelayedTelemetry t = trip(null, null);
    t.driverDistanceMeters = 450;
    Assert.isFalse(t.hasGeofenceCoordinates());
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MISMATCH, CARES_StolenDelayedPolicy.gpsResult(t, settings()));
    t.driverDistanceMeters = null;
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_UNKNOWN, CARES_StolenDelayedPolicy.gpsResult(t, settings()));
  }

  @IsTest
  static void enrichCopiesTheGeofenceLocations() {
    CARES_StolenDelayedTelemetry fromPlatform = trip(40.749918, -73.985049);
    fromPlatform.orderFound = true;
    fromPlatform.customerMatches = true;
    CARES_StolenDelayedTelemetry t = new CARES_StolenDelayedTelemetry();
    CARES_StolenDelayedPolicy.enrich(t, fromPlatform);
    Assert.isTrue(t.hasGeofenceCoordinates());
    Assert.areEqual(40.749918, t.driverLatitude);
  }
}
