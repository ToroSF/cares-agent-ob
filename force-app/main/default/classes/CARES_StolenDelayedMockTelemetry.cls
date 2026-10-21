/**
 * Stolen & Delayed Orders: mock delivery telemetry stored in Salesforce (D-096).
 * Stands in for the delivery platform while it does not exist. One
 * CARES_Delivery_Telemetry__c row per order gives the driver's GPS distance when the
 * order was marked delivered (or the restaurant, drop-off and driver locations for the
 * trip geofence, D-097), wait time, calls and chats, driver history, fraud flags
 * and re-dispatch eligibility. Re-dispatch requests and trust events are written as
 * records instead of being sent out. There are no photo fields on purpose, so photo
 * evidence stays unknown.
 */
public with sharing class CARES_StolenDelayedMockTelemetry {
  /**
   * The mock telemetry for one order, or null when the order has no row (or the row
   * can't be read), which leaves everything the platform would add unknown.
   */
  public static CARES_StolenDelayedTelemetry forOrder(String orderId) {
    if (String.isBlank(orderId)) {
      return null;
    }
    List<CARES_Delivery_Telemetry__c> rows;
    try {
      rows = [
        SELECT
          Driver_Distance_Meters__c,
          Driver_Wait_Seconds__c,
          Driver_Calls__c,
          Driver_Chats__c,
          Driver_NonDelivery_Rate__c,
          Driver_Delivery_Count__c,
          Fraud_Pattern__c,
          Device_Duplication__c,
          Address_Duplication__c,
          Redispatch_Eligible__c,
          Restaurant_Location__Latitude__s,
          Restaurant_Location__Longitude__s,
          Dropoff_Location__Latitude__s,
          Dropoff_Location__Longitude__s,
          Driver_Location__Latitude__s,
          Driver_Location__Longitude__s
        FROM CARES_Delivery_Telemetry__c
        WHERE Order_ID__c = :orderId
        WITH USER_MODE
        LIMIT 1
      ];
    } catch (QueryException e) {
      // Missing access looks like "no data", so say it in the log (G-084 lesson)
      System.debug(LoggingLevel.ERROR, 'CARES mock telemetry not readable: ' + e.getMessage());
      return null;
    }
    if (rows.isEmpty()) {
      return null;
    }
    CARES_Delivery_Telemetry__c r = rows[0];
    CARES_StolenDelayedTelemetry t = new CARES_StolenDelayedTelemetry();
    // The real order already proved both; enrich() only copies when they are true
    t.orderFound = true;
    t.customerMatches = true;
    t.driverDistanceMeters = r.Driver_Distance_Meters__c;
    // The three points of the trip geofence (D-097)
    t.restaurantLatitude = r.Restaurant_Location__Latitude__s;
    t.restaurantLongitude = r.Restaurant_Location__Longitude__s;
    t.dropoffLatitude = r.Dropoff_Location__Latitude__s;
    t.dropoffLongitude = r.Dropoff_Location__Longitude__s;
    t.driverLatitude = r.Driver_Location__Latitude__s;
    t.driverLongitude = r.Driver_Location__Longitude__s;
    t.driverWaitSeconds = toInteger(r.Driver_Wait_Seconds__c);
    t.driverCallsToCustomer = toInteger(r.Driver_Calls__c);
    t.driverChatsToCustomer = toInteger(r.Driver_Chats__c);
    // Percent field: 0.2 means 0.2%, the policy uses 0..1
    t.driverNonDeliveryRate = r.Driver_NonDelivery_Rate__c == null ? null : r.Driver_NonDelivery_Rate__c / 100;
    t.driverDeliveryCount = toInteger(r.Driver_Delivery_Count__c);
    t.fraudPatternDetected = r.Fraud_Pattern__c;
    t.deviceDuplicationDetected = r.Device_Duplication__c;
    t.addressDuplicationDetected = r.Address_Duplication__c;
    t.redispatchEligible = r.Redispatch_Eligible__c;
    return t;
  }

  /**
   * Records a re-dispatch request and returns its reference (the record Name). One
   * request per order: asking again returns the same reference.
   */
  public static String requestRedispatch(String orderId, String contactId) {
    try {
      List<CARES_Redispatch__c> existing = [
        SELECT Name
        FROM CARES_Redispatch__c
        WHERE Order_ID__c = :orderId
        WITH USER_MODE
        LIMIT 1
      ];
      if (!existing.isEmpty()) {
        return existing[0].Name;
      }
      CARES_Redispatch__c rd = new CARES_Redispatch__c(
        Order_ID__c = orderId,
        Contact__c = toId(contactId),
        Status__c = 'Requested'
      );
      Database.insert(rd, AccessLevel.USER_MODE);
      return [SELECT Name FROM CARES_Redispatch__c WHERE Id = :rd.Id WITH USER_MODE].Name;
    } catch (Exception e) {
      // Same failure the platform call raises, so the hand-off reports FAILED
      throw new CARES_StolenDelayedPlatformClient.PlatformException('Re-dispatch request not saved: ' + e.getMessage());
    }
  }

  /**
   * Writes the customer and driver trust events for one claim. Keyed like the platform
   * call's Idempotency-Key, so running it twice adds nothing. Failures are logged, as
   * for the platform call.
   */
  public static void recordTrustEvents(
    String orderId,
    String contactId,
    String customerEvent,
    String driverEvent
  ) {
    String driverId = null;
    try {
      List<CARES_Delivery_Telemetry__c> rows = [
        SELECT Driver_ID__c
        FROM CARES_Delivery_Telemetry__c
        WHERE Order_ID__c = :orderId
        WITH USER_MODE
        LIMIT 1
      ];
      driverId = rows.isEmpty() ? null : rows[0].Driver_ID__c;
    } catch (QueryException e) {
      System.debug(LoggingLevel.ERROR, 'CARES mock telemetry not readable: ' + e.getMessage());
    }
    List<CARES_Trust_Event__c> events = new List<CARES_Trust_Event__c>{
      event(CARES_StolenDelayedTrustScoreJob.CUSTOMER, customerEvent, orderId, contactId, null),
      event(CARES_StolenDelayedTrustScoreJob.DRIVER, driverEvent, orderId, contactId, driverId)
    };
    List<Database.UpsertResult> results = Database.upsert(
      events,
      CARES_Trust_Event__c.Event_Key__c,
      false,
      AccessLevel.USER_MODE
    );
    for (Database.UpsertResult res : results) {
      if (!res.isSuccess()) {
        // No retry yet (see the subagent doc, gaps). Never surfaces to the customer.
        System.debug(LoggingLevel.ERROR, 'CARES trust event not saved: ' + res.getErrors());
      }
    }
  }

  private static CARES_Trust_Event__c event(
    String subjectType,
    String eventType,
    String orderId,
    String contactId,
    String driverId
  ) {
    return new CARES_Trust_Event__c(
      Subject_Type__c = subjectType,
      Event_Type__c = eventType,
      Order_ID__c = orderId,
      Contact__c = toId(contactId),
      Driver_ID__c = driverId,
      Event_Key__c = 'CARES-TRUST-' + subjectType + '-' + eventType + '-' + orderId
    );
  }

  private static Integer toInteger(Decimal value) {
    return value == null ? null : value.intValue();
  }

  private static Id toId(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Id.valueOf(value);
    } catch (StringException e) {
      return null;
    }
  }
}
