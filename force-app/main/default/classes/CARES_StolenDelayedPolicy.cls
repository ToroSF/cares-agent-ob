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
 *   7. Not marked delivered, or a photo exists       -> STANDARD_PATH
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
   * Full evaluation: local checks first (no callout), then one read from the
   * delivery platform, then the matrix.
   */
  public static Outcome evaluate(
    String contactId,
    String orderId,
    String customerReport
  ) {
    Settings s = loadSettings();
    if (containsSensitiveKeyword(customerReport, s)) {
      return new Outcome(ESCALATE, 'SENSITIVE_TOPIC');
    }
    if (String.isBlank(contactId)) {
      return new Outcome(ESCALATE, 'NO_VERIFIED_CONTACT');
    }
    String cleanOrderId = orderId == null ? '' : orderId.trim();
    if (!ORDER_ID_FORMAT.matcher(cleanOrderId).matches()) {
      return new Outcome(ORDER_NOT_FOUND, 'INVALID_ORDER_ID');
    }
    CARES_StolenDelayedTelemetry t;
    try {
      t = new CARES_StolenDelayedPlatformClient()
        .getDeliveryContext(cleanOrderId, contactId);
    } catch (CARES_StolenDelayedPlatformClient.PlatformException e) {
      return new Outcome(ESCALATE, 'DATA_UNAVAILABLE');
    }
    Outcome d = decide(t, s);
    d.orderId = cleanOrderId;
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
    if (t.orderStatus != 'DELIVERED') {
      return withOrder(new Outcome(STANDARD_PATH, 'NOT_MARKED_DELIVERED'), t);
    }
    if (t.hasPhotoEvidence()) {
      return withOrder(new Outcome(STANDARD_PATH, 'PHOTO_EVIDENCE'), t);
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

  private static Decimal pick(Decimal value, Decimal fallback) {
    return value == null ? fallback : value;
  }

  private static Decimal pickPercent(Decimal percent, Decimal fallback) {
    return percent == null ? fallback : percent / 100;
  }
}
