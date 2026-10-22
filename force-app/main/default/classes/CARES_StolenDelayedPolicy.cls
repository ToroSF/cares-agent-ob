/**
 * Stolen & Delayed Orders: decision policy for orders marked delivered that the
 * customer did not receive, when neither the customer nor the driver has a photo.
 *
 * This class only decides. It never issues a refund or credit: an approved
 * decision is handed to Refund (through Risk Detection) as context.
 *
 * Checks run in a fixed order and the first match wins:
 *   1. Sensitive keywords (assault, safety, legal)   -> ESCALATE
 *   2. No verified contact / platform unavailable    -> ESCALATE
 *   3. Order not found or not this customer's        -> ORDER_NOT_FOUND
 *   4. Fraud, device or address duplication          -> ESCALATE
 *   5. Order already claimed                         -> ESCALATE
 *   6. Value over the USD limit, or unknown          -> ESCALATE
 *   7. Timing (D-100): not delivered yet -> NOT_LATE_YET, DELAY or, when likely lost, the
 *      trust check below as a lost order; delivered and the customer says it was late
 *      -> DELIVERED_ON_TIME or DELAY. Unknown timing, or a photo -> STANDARD_PATH
 *   8. Low-trust customer                            -> MANUAL_REVIEW
 *   9. High-trust customer + excellent driver + GPS match -> LOSS_ABSORPTION
 *  10. High-trust customer                           -> FULL_REFUND
 *  11. Anything else (trust not established)         -> MANUAL_REVIEW
 */
public with sharing class CARES_StolenDelayedPolicy {
  public static final String STANDARD_PATH = 'STANDARD_PATH';
  public static final String FULL_REFUND = 'FULL_REFUND';
  public static final String LOSS_ABSORPTION = 'LOSS_ABSORPTION';
  public static final String MANUAL_REVIEW = 'MANUAL_REVIEW';
  public static final String ESCALATE = 'ESCALATE';
  public static final String ORDER_NOT_FOUND = 'ORDER_NOT_FOUND';
  // Timing outcomes (D-100)
  public static final String DELAY = 'DELAY';
  public static final String NOT_LATE_YET = 'NOT_LATE_YET';
  public static final String DELIVERED_ON_TIME = 'DELIVERED_ON_TIME';

  // What the customer says happened (D-100)
  public static final String CLAIM_NOT_RECEIVED = 'NOT_RECEIVED';
  public static final String CLAIM_LATE = 'LATE';
  public static final String CLAIM_UNSURE = 'UNSURE';

  public static final String SEVERITY_MINOR = 'MINOR';
  public static final String SEVERITY_SEVERE = 'SEVERE';

  public static final String TRUST_HIGH = 'HIGH';
  public static final String TRUST_MEDIUM = 'MEDIUM';
  public static final String TRUST_LOW = 'LOW';
  public static final String TRUST_UNKNOWN = 'UNKNOWN';

  public static final String GPS_MATCH = 'MATCH';
  public static final String GPS_AMBIGUOUS = 'AMBIGUOUS';
  public static final String GPS_MISMATCH = 'MISMATCH';
  public static final String GPS_UNKNOWN = 'UNKNOWN';

  public static final String DRIVER_PAY_IN_FULL = 'PAY_IN_FULL';
  public static final String DRIVER_WITHHOLD = 'WITHHOLD_DELIVERY_PAY';
  public static final String DRIVER_HOLD_FOR_REVIEW = 'HOLD_FOR_REVIEW';

  public static final String RESTAURANT_REIMBURSE = 'REIMBURSE';
  public static final String RESTAURANT_NO_CHANGE = 'NO_CHANGE';

  private static final Pattern ORDER_ID_FORMAT = Pattern.compile(
    '^[A-Za-z0-9-]{1,40}$'
  );

  // Currency code -> conversion rate against the corporate currency. Tests set it.
  @TestVisible
  private static Map<String, Decimal> conversionRates;

  public class Outcome {
    public String decision;
    public String reasonCode;
    public String orderId;
    public String customerTrust = TRUST_UNKNOWN;
    public String gpsResult = GPS_UNKNOWN;
    public Boolean driverExcellent = false;
    public Boolean driverDiligent = false;
    public Decimal orderTotal;
    public String currencyIsoCode;
    public Boolean redispatchEligible = false;
    public String driverCompensation = '';
    public String restaurantReimbursement = '';
    // Timing (D-100)
    public String timing = CARES_StolenDelayedTiming.UNKNOWN;
    public String stage = '';
    public Integer minutesLate = 0;
    public Integer minutesUntilExpected = 0;
    public Decimal deliveryMinutes;
    // DELAY only: MINOR or SEVERE, and the value Refund starts from (order total x the delay %)
    public String delaySeverity = '';
    public Decimal delayValue = 0;

    public Outcome(String decision, String reasonCode) {
      this.decision = decision;
      this.reasonCode = reasonCode;
    }

    public Boolean isFinal() {
      return decision != ORDER_NOT_FOUND;
    }

    public Boolean needsPerson() {
      return decision == ESCALATE || decision == MANUAL_REVIEW;
    }

    public Boolean fullRefundApproved() {
      return decision == FULL_REFUND || decision == LOSS_ABSORPTION;
    }
  }

  public class Settings {
    public Decimal gpsMatchMaxMeters = 50;
    public Decimal gpsMismatchMinMeters = 100;
    public Decimal minDriverWaitSeconds = 180;
    public Decimal minDriverContactAttempts = 1;
    public Decimal highTrustMaxClaimRate = 0.05;
    public Decimal lowTrustMinClaimRate = 0.20;
    public Decimal highTrustMinOrders = 5;
    public Decimal excellentDriverMaxNonDeliveryRate = 0.01;
    public Decimal excellentDriverMinDeliveries = 50;
    public Decimal escalationAmountUsd = 100;
    // The delivery platform only enriches the real order data when it is switched on (D-089)
    public Boolean platformEnabled = false;
    // Mock telemetry records stand in for the platform, and win over it (D-096)
    public Boolean mockTelemetryEnabled = false;
    // Timing (D-100). The promise is the data's own on-time line; the rest are team assumptions [$]
    public Decimal promisedDeliveryMinutes = 40;
    public Decimal delayGraceMinutes = 5;
    public Decimal minorDelayMaxMinutes = 15;
    public Decimal lostAfterMinutesLate = 60;
    public Decimal courierLostMinutes = 75;
    public Decimal minorDelayPct = 0.15;
    public Decimal severeDelayPct = 0.50;
    public List<String> sensitiveKeywords = new List<String>{
      'assault',
      'assaulted',
      'attack',
      'attacked',
      'hit me',
      'punched',
      'threat',
      'threats',
      'threatened',
      'weapon',
      'gun',
      'knife',
      'unsafe',
      'harassed',
      'harassment',
      'injured',
      'injury',
      'police',
      'lawyer',
      'attorney',
      'sue',
      'suing',
      'lawsuit',
      'legal action',
      'take you to court'
    };
  }

  @TestVisible
  private static Settings settingsOverride;

  /**
   * Reads the Default record of CARES_Stolen_Delayed_Policy__mdt. Blank fields
   * keep the built-in value so a half-filled record never loosens a limit to 0.
   */
  public static Settings loadSettings() {
    if (settingsOverride != null) {
      return settingsOverride;
    }
    Settings s = new Settings();
    CARES_Stolen_Delayed_Policy__mdt r = CARES_Stolen_Delayed_Policy__mdt.getInstance(
      'Default'
    );
    if (r == null) {
      return s;
    }
    s.gpsMatchMaxMeters = pick(r.GPS_Match_Max_Meters__c, s.gpsMatchMaxMeters);
    s.gpsMismatchMinMeters = pick(
      r.GPS_Mismatch_Min_Meters__c,
      s.gpsMismatchMinMeters
    );
    s.minDriverWaitSeconds = pick(
      r.Min_Driver_Wait_Seconds__c,
      s.minDriverWaitSeconds
    );
    s.minDriverContactAttempts = pick(
      r.Min_Driver_Contact_Attempts__c,
      s.minDriverContactAttempts
    );
    s.highTrustMaxClaimRate = pickPercent(
      r.High_Trust_Max_Claim_Rate__c,
      s.highTrustMaxClaimRate
    );
    s.lowTrustMinClaimRate = pickPercent(
      r.Low_Trust_Min_Claim_Rate__c,
      s.lowTrustMinClaimRate
    );
    s.highTrustMinOrders = pick(
      r.High_Trust_Min_Orders__c,
      s.highTrustMinOrders
    );
    s.excellentDriverMaxNonDeliveryRate = pickPercent(
      r.Excellent_Driver_Max_NonDelivery__c,
      s.excellentDriverMaxNonDeliveryRate
    );
    s.excellentDriverMinDeliveries = pick(
      r.Excellent_Driver_Min_Deliveries__c,
      s.excellentDriverMinDeliveries
    );
    s.escalationAmountUsd = pick(
      r.Escalation_Amount_USD__c,
      s.escalationAmountUsd
    );
    s.platformEnabled = r.Platform_Enabled__c == true;
    s.mockTelemetryEnabled = r.Mock_Telemetry_Enabled__c == true;
    s.promisedDeliveryMinutes = pick(r.Promised_Delivery_Minutes__c, s.promisedDeliveryMinutes);
    s.delayGraceMinutes = pick(r.Delay_Grace_Minutes__c, s.delayGraceMinutes);
    s.minorDelayMaxMinutes = pick(r.Minor_Delay_Max_Minutes__c, s.minorDelayMaxMinutes);
    s.lostAfterMinutesLate = pick(r.Lost_After_Minutes_Late__c, s.lostAfterMinutesLate);
    s.courierLostMinutes = pick(r.Courier_Lost_Minutes__c, s.courierLostMinutes);
    s.minorDelayPct = pickPercent(r.Minor_Delay_Pct__c, s.minorDelayPct);
    s.severeDelayPct = pickPercent(r.Severe_Delay_Pct__c, s.severeDelayPct);
    if (String.isNotBlank(r.Sensitive_Keywords__c)) {
      s.sensitiveKeywords = new List<String>();
      for (String k : r.Sensitive_Keywords__c.split('[,\\n]')) {
        if (String.isNotBlank(k)) {
          s.sensitiveKeywords.add(k.trim());
        }
      }
    }
    return s;
  }

  /**
   * Full evaluation: local checks first (no query), then the real order and the
   * customer's claims (D-089, D-090), then, when it is switched on, the mock
   * telemetry records (D-096) or the delivery platform for what the order data
   * lacks, then the matrix.
   */
  public static Outcome evaluate(
    String contactId,
    String orderId,
    String customerReport
  ) {
    // The hand-off's re-check has no claim: UNSURE gives the same full-refund decisions
    return evaluate(contactId, orderId, customerReport, CLAIM_UNSURE);
  }

  public static Outcome evaluate(
    String contactId,
    String orderId,
    String customerReport,
    String claimType
  ) {
    Settings s = loadSettings();
    String cleanOrderId = orderId == null ? '' : orderId.trim();
    // The escalation case needs the order the customer named, even when no check ran (G-098)
    String namedOrder = ORDER_ID_FORMAT.matcher(cleanOrderId).matches() ? cleanOrderId : null;
    if (containsSensitiveKeyword(customerReport, s)) {
      return withOrderId(new Outcome(ESCALATE, 'SENSITIVE_TOPIC'), namedOrder);
    }
    if (String.isBlank(contactId)) {
      return withOrderId(new Outcome(ESCALATE, 'NO_VERIFIED_CONTACT'), namedOrder);
    }
    if (namedOrder == null) {
      return new Outcome(ORDER_NOT_FOUND, 'INVALID_ORDER_ID');
    }
    CARES_StolenDelayedOrderSource.Result src = CARES_StolenDelayedOrderSource.load(
      contactId,
      cleanOrderId
    );
    if (src.telemetry == null) {
      return withOrderId(new Outcome(src.decision, src.reasonCode), namedOrder);
    }
    CARES_StolenDelayedTelemetry t = src.telemetry;
    t.claimType = claimFrom(claimType, customerReport);
    if (s.mockTelemetryEnabled) {
      // No row for the order leaves what the platform would add unknown (D-096)
      enrich(t, CARES_StolenDelayedMockTelemetry.forOrder(src.orderId));
    } else if (s.platformEnabled) {
      try {
        enrich(
          t,
          new CARES_StolenDelayedPlatformClient()
            .getDeliveryContext(src.orderId, contactId)
        );
      } catch (CARES_StolenDelayedPlatformClient.PlatformException e) {
        // The real order still decides; what the platform would add stays unknown
      }
    }
    Outcome d = decide(t, s);
    d.orderId = src.orderId;
    return d;
  }

  @TestVisible
  private static Outcome decide(CARES_StolenDelayedTelemetry t, Settings s) {
    if (t == null) {
      return new Outcome(ESCALATE, 'DATA_UNAVAILABLE');
    }
    if (t.orderFound != true || t.customerMatches != true) {
      return new Outcome(ORDER_NOT_FOUND, 'ORDER_NOT_FOUND');
    }
    // No rule in the matrix fits a canceled order: a person decides (D-091)
    if (t.orderStatus == CARES_StolenDelayedOrderSource.CANCELED) {
      return withOrder(new Outcome(ESCALATE, 'ORDER_CANCELED'), t);
    }
    if (
      t.fraudPatternDetected == true ||
      t.deviceDuplicationDetected == true ||
      t.addressDuplicationDetected == true
    ) {
      return withOrder(new Outcome(ESCALATE, 'FRAUD_SIGNAL'), t);
    }
    if (t.priorClaimOnOrder == true) {
      return withOrder(new Outcome(ESCALATE, 'DUPLICATE_CLAIM'), t);
    }
    Decimal usd = toUsd(t.orderTotal, t.currencyIsoCode);
    if (usd == null) {
      return withOrder(new Outcome(ESCALATE, 'AMOUNT_UNVERIFIED'), t);
    }
    if (usd > s.escalationAmountUsd) {
      return withOrder(new Outcome(ESCALATE, 'HIGH_VALUE'), t);
    }
    // Timing first (D-100): late, on time and lost are told apart from the order's own times
    CARES_StolenDelayedTiming.Result timing = CARES_StolenDelayedTiming.classify(t, s, System.now());
    Boolean delivered = t.orderStatus == CARES_StolenDelayedOrderSource.DELIVERED;
    Boolean lostInTransit = !delivered && timing.timing == CARES_StolenDelayedTiming.LIKELY_LOST;
    if (!delivered && !lostInTransit) {
      if (timing.timing == CARES_StolenDelayedTiming.NOT_LATE_YET) {
        return withTiming(withOrder(new Outcome(NOT_LATE_YET, 'WITHIN_ESTIMATE'), t), timing, t);
      }
      if (timing.isDelay()) {
        return delay(t, s, timing);
      }
      // No order time to measure against: the standard way, as before D-100
      return withTiming(withOrder(new Outcome(STANDARD_PATH, 'NOT_MARKED_DELIVERED'), t), timing, t);
    }
    if (delivered && t.claimType == CLAIM_LATE) {
      if (timing.timing == CARES_StolenDelayedTiming.ON_TIME) {
        return withTiming(withOrder(new Outcome(DELIVERED_ON_TIME, 'DELIVERED_WITHIN_PROMISE'), t), timing, t);
      }
      if (timing.isDelay()) {
        return delay(t, s, timing);
      }
      return withTiming(withOrder(new Outcome(STANDARD_PATH, 'DELIVERY_TIME_UNKNOWN'), t), timing, t);
    }
    if (delivered && t.hasPhotoEvidence()) {
      return withOrder(new Outcome(STANDARD_PATH, 'PHOTO_EVIDENCE'), t);
    }
    if (lostInTransit) {
      return withTiming(lostOrder(t, s), timing, t);
    }

    String trust = customerTrust(t, s);
    String gps = gpsResult(t, s);
    Boolean excellent = driverExcellent(t, s);
    Boolean diligent = driverDiligent(t, s);

    Outcome d;
    if (trust == TRUST_LOW) {
      d = new Outcome(MANUAL_REVIEW, 'LOW_TRUST_CUSTOMER');
    } else if (trust == TRUST_HIGH && excellent && gps == GPS_MATCH) {
      d = new Outcome(LOSS_ABSORPTION, 'HIGH_TRUST_CONFLICT');
      d.driverCompensation = DRIVER_PAY_IN_FULL;
      d.restaurantReimbursement = RESTAURANT_REIMBURSE;
    } else if (trust == TRUST_HIGH) {
      d = new Outcome(FULL_REFUND, 'HIGH_TRUST_CUSTOMER');
      d.driverCompensation = driverCompensation(gps, diligent);
      d.restaurantReimbursement = RESTAURANT_NO_CHANGE;
    } else {
      d = new Outcome(MANUAL_REVIEW, 'TRUST_NOT_ESTABLISHED');
    }
    d.customerTrust = trust;
    d.gpsResult = gps;
    d.driverExcellent = excellent;
    d.driverDiligent = diligent;
    return withOrder(d, t);
  }

  // A late order: Refund offers the delay value, capped by the tier's Delayed policy row (D-100)
  private static Outcome delay(
    CARES_StolenDelayedTelemetry t,
    Settings s,
    CARES_StolenDelayedTiming.Result timing
  ) {
    Boolean minor = timing.timing == CARES_StolenDelayedTiming.DELAYED_MINOR;
    Outcome d = withOrder(new Outcome(DELAY, minor ? 'MINOR_DELAY' : 'SEVERE_DELAY'), t);
    d.delaySeverity = minor ? SEVERITY_MINOR : SEVERITY_SEVERE;
    Decimal total = t.orderTotal == null ? 0 : t.orderTotal;
    d.delayValue = (total * (minor ? s.minorDelayPct : s.severeDelayPct)).setScale(2);
    return withTiming(d, timing, t);
  }

  // Not delivered and far past any normal time: treated like an order that never arrived (POL-P09)
  private static Outcome lostOrder(CARES_StolenDelayedTelemetry t, Settings s) {
    String trust = customerTrust(t, s);
    Outcome d;
    if (trust == TRUST_LOW) {
      d = new Outcome(MANUAL_REVIEW, 'LOW_TRUST_CUSTOMER');
    } else if (trust == TRUST_HIGH) {
      d = new Outcome(FULL_REFUND, 'LOST_IN_TRANSIT');
      // No delivered position to judge the driver by: a person decides
      d.driverCompensation = DRIVER_HOLD_FOR_REVIEW;
      d.restaurantReimbursement = RESTAURANT_NO_CHANGE;
    } else {
      d = new Outcome(MANUAL_REVIEW, 'TRUST_NOT_ESTABLISHED');
    }
    d.customerTrust = trust;
    return withOrder(d, t);
  }

  private static Outcome withTiming(
    Outcome d,
    CARES_StolenDelayedTiming.Result timing,
    CARES_StolenDelayedTelemetry t
  ) {
    d.timing = timing.timing;
    d.stage = timing.stage;
    d.minutesLate = timing.minutesLate;
    d.minutesUntilExpected = timing.minutesUntilExpected;
    d.deliveryMinutes = t.deliveryMinutes;
    return d;
  }

  // The model can leave the claim type empty (G-126). Then the customer's own words decide: a plain "it came
  // late", with nothing that says it never came, is LATE, so a late delivery is never paid as a lost one.
  // Anything else stays UNSURE, as before
  private static final Pattern LATE_WORDS = Pattern.compile(
    '\\b(late|delay(ed)?|took (so |too |very )?long|waited|waiting|slow|forever|ages)\\b'
  );
  private static final Pattern NOT_RECEIVED_WORDS = Pattern.compile(
    '\\b(never|not|didn\'t|hasn\'t|haven\'t|wasn\'t|isn\'t|missing|stolen|nothing)\\b'
  );

  @TestVisible
  private static String claimFrom(String claimType, String customerReport) {
    if (String.isNotBlank(claimType)) {
      return normalizeClaim(claimType);
    }
    String report = customerReport == null ? '' : customerReport.toLowerCase();
    return LATE_WORDS.matcher(report).find() && !NOT_RECEIVED_WORDS.matcher(report).find()
      ? CLAIM_LATE
      : CLAIM_UNSURE;
  }

  @TestVisible
  private static String normalizeClaim(String claimType) {
    String c = claimType == null ? '' : claimType.trim().toUpperCase();
    return c == CLAIM_NOT_RECEIVED || c == CLAIM_LATE ? c : CLAIM_UNSURE;
  }

  @TestVisible
  private static String customerTrust(
    CARES_StolenDelayedTelemetry t,
    Settings s
  ) {
    if (t.customerClaimRate == null) {
      return TRUST_UNKNOWN;
    }
    if (t.customerClaimRate >= s.lowTrustMinClaimRate) {
      return TRUST_LOW;
    }
    // A low rate over very few orders is not a track record yet.
    if (
      t.customerClaimRate <= s.highTrustMaxClaimRate &&
      t.customerOrderCount != null &&
      t.customerOrderCount >= s.highTrustMinOrders
    ) {
      return TRUST_HIGH;
    }
    return TRUST_MEDIUM;
  }

  @TestVisible
  private static String gpsResult(CARES_StolenDelayedTelemetry t, Settings s) {
    // With coordinates, the trip geofence decides: inside = match, outside = mismatch (D-097)
    if (t.hasGeofenceCoordinates()) {
      return insideTripGeofence(t, s) ? GPS_MATCH : GPS_MISMATCH;
    }
    // Without them, the older distance-from-drop-off rule (platform data)
    if (t.driverDistanceMeters == null) {
      return GPS_UNKNOWN;
    }
    if (t.driverDistanceMeters <= s.gpsMatchMaxMeters) {
      return GPS_MATCH;
    }
    if (t.driverDistanceMeters > s.gpsMismatchMinMeters) {
      return GPS_MISMATCH;
    }
    return GPS_AMBIGUOUS;
  }

  /**
   * Trip geofence (D-097): a circle centered on the midpoint of the trip from the
   * restaurant to the drop-off, with radius = half the trip distance plus the GPS
   * tolerance (GPS_Match_Max_Meters__c). Restaurant and drop-off sit on the circle
   * without the tolerance, so it keeps a driver at the door, or a few meters past it,
   * inside. True when the driver was inside when the order was marked delivered.
   */
  @TestVisible
  private static Boolean insideTripGeofence(CARES_StolenDelayedTelemetry t, Settings s) {
    Location restaurant = Location.newInstance(t.restaurantLatitude, t.restaurantLongitude);
    Location dropoff = Location.newInstance(t.dropoffLatitude, t.dropoffLongitude);
    Location driver = Location.newInstance(t.driverLatitude, t.driverLongitude);
    return meters(midpoint(restaurant, dropoff), driver) <= geofenceRadiusMeters(restaurant, dropoff, s);
  }

  @TestVisible
  private static Decimal geofenceRadiusMeters(Location restaurant, Location dropoff, Settings s) {
    return meters(restaurant, dropoff) / 2 + s.gpsMatchMaxMeters;
  }

  // Great-circle midpoint of two points
  @TestVisible
  private static Location midpoint(Location a, Location b) {
    Double lat1 = a.getLatitude() * Math.PI / 180;
    Double lon1 = a.getLongitude() * Math.PI / 180;
    Double lat2 = b.getLatitude() * Math.PI / 180;
    Double lon2 = b.getLongitude() * Math.PI / 180;
    Double x = Math.cos(lat2) * Math.cos(lon2 - lon1);
    Double y = Math.cos(lat2) * Math.sin(lon2 - lon1);
    Double lat = Math.atan2(
      Math.sin(lat1) + Math.sin(lat2),
      Math.sqrt((Math.cos(lat1) + x) * (Math.cos(lat1) + x) + y * y)
    );
    Double lon = lon1 + Math.atan2(y, Math.cos(lat1) + x);
    return Location.newInstance(lat * 180 / Math.PI, lon * 180 / Math.PI);
  }

  private static Decimal meters(Location a, Location b) {
    return Location.getDistance(a, b, 'km') * 1000;
  }

  @TestVisible
  private static Boolean driverExcellent(
    CARES_StolenDelayedTelemetry t,
    Settings s
  ) {
    return t.driverNonDeliveryRate != null &&
      t.driverDeliveryCount != null &&
      t.driverNonDeliveryRate <= s.excellentDriverMaxNonDeliveryRate &&
      t.driverDeliveryCount >= s.excellentDriverMinDeliveries;
  }

  // The driver waited long enough or tried to reach the customer.
  @TestVisible
  private static Boolean driverDiligent(
    CARES_StolenDelayedTelemetry t,
    Settings s
  ) {
    Integer attempts = t.contactAttempts();
    return (t.driverWaitSeconds != null &&
      t.driverWaitSeconds >= s.minDriverWaitSeconds) ||
      (attempts != null &&
      attempts >= s.minDriverContactAttempts);
  }

  private static String driverCompensation(String gps, Boolean diligent) {
    if (gps == GPS_MISMATCH) {
      return DRIVER_WITHHOLD;
    }
    if (gps == GPS_UNKNOWN) {
      return DRIVER_HOLD_FOR_REVIEW;
    }
    if (gps == GPS_AMBIGUOUS && !diligent) {
      return DRIVER_WITHHOLD;
    }
    return DRIVER_PAY_IN_FULL;
  }

  @TestVisible
  private static Boolean containsSensitiveKeyword(String text, Settings s) {
    if (String.isBlank(text) || s.sensitiveKeywords.isEmpty()) {
      return false;
    }
    List<String> quoted = new List<String>();
    for (String k : s.sensitiveKeywords) {
      quoted.add(Pattern.quote(k.toLowerCase()));
    }
    // Word boundaries, so "sue" does not match "issue".
    Pattern p = Pattern.compile('\\b(?:' + String.join(quoted, '|') + ')\\b');
    return p.matcher(text.toLowerCase()).find();
  }

  /**
   * Converts an amount to USD with the org's active currency rates. Returns null
   * when the currency is blank or has no rate, so the caller escalates.
   */
  @TestVisible
  private static Decimal toUsd(Decimal amount, String isoCode) {
    if (amount == null || String.isBlank(isoCode)) {
      return null;
    }
    String code = isoCode.trim().toUpperCase();
    if (code == 'USD') {
      return amount;
    }
    Map<String, Decimal> rates = loadConversionRates();
    if (!rates.containsKey(code) || !rates.containsKey('USD')) {
      return null;
    }
    return amount / rates.get(code) * rates.get('USD');
  }

  private static Map<String, Decimal> loadConversionRates() {
    if (conversionRates != null) {
      return conversionRates;
    }
    conversionRates = new Map<String, Decimal>();
    try {
      // CurrencyType only exists in multi-currency orgs, so query it dynamically.
      for (
        SObject r : Database.query(
          'SELECT IsoCode, ConversionRate FROM CurrencyType WHERE IsActive = true'
        )
      ) {
        conversionRates.put(
          ((String) r.get('IsoCode')).toUpperCase(),
          (Decimal) r.get('ConversionRate')
        );
      }
    } catch (QueryException e) {
      // Single-currency org: only USD amounts can be verified.
    }
    return conversionRates;
  }

  private static Outcome withOrder(Outcome d, CARES_StolenDelayedTelemetry t) {
    d.orderTotal = t.orderTotal;
    d.currencyIsoCode = t.currencyIsoCode;
    d.redispatchEligible = t.redispatchEligible == true;
    return d;
  }

  // Copies only what the order data lacks; the order facts and the customer's trust stay from CARES's data
  @TestVisible
  private static void enrich(
    CARES_StolenDelayedTelemetry t,
    CARES_StolenDelayedTelemetry platform
  ) {
    if (
      platform == null ||
      platform.orderFound != true ||
      platform.customerMatches != true
    ) {
      return;
    }
    t.redispatchEligible = platform.redispatchEligible;
    t.customerPhotoProvided = platform.customerPhotoProvided;
    t.driverPhotoProvided = platform.driverPhotoProvided;
    t.driverDistanceMeters = platform.driverDistanceMeters;
    t.restaurantLatitude = platform.restaurantLatitude;
    t.restaurantLongitude = platform.restaurantLongitude;
    t.dropoffLatitude = platform.dropoffLatitude;
    t.dropoffLongitude = platform.dropoffLongitude;
    t.driverLatitude = platform.driverLatitude;
    t.driverLongitude = platform.driverLongitude;
    t.minutesSinceOrder = platform.minutesSinceOrder;
    t.driverWaitSeconds = platform.driverWaitSeconds;
    t.driverCallsToCustomer = platform.driverCallsToCustomer;
    t.driverChatsToCustomer = platform.driverChatsToCustomer;
    t.driverNonDeliveryRate = platform.driverNonDeliveryRate;
    t.driverDeliveryCount = platform.driverDeliveryCount;
    t.fraudPatternDetected = platform.fraudPatternDetected;
    t.deviceDuplicationDetected = platform.deviceDuplicationDetected;
    t.addressDuplicationDetected = platform.addressDuplicationDetected;
  }

  private static Outcome withOrderId(Outcome d, String orderId) {
    d.orderId = orderId;
    return d;
  }

  private static Decimal pick(Decimal value, Decimal fallback) {
    return value == null ? fallback : value;
  }

  private static Decimal pickPercent(Decimal percent, Decimal fallback) {
    return percent == null ? fallback : percent / 100;
  }
}
