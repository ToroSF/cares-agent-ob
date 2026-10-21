/**
 * Stolen & Delayed Orders: delivery context for one order, as returned by the
 * delivery platform. Any value the platform does not send stays null, and the
 * policy treats null as "unknown", never as the favourable value.
 */
public with sharing class CARES_StolenDelayedTelemetry {
  // Order
  public Boolean orderFound;
  public Boolean customerMatches; // the order belongs to the verified contact
  public String orderStatus; // DELIVERED, IN_TRANSIT, CANCELLED, ...
  public Decimal orderTotal;
  public String currencyIsoCode;
  public Boolean priorClaimOnOrder;
  public Boolean redispatchEligible;

  // Visual evidence
  public Boolean customerPhotoProvided;
  public Boolean driverPhotoProvided;

  // Passive telemetry at the moment the order was marked delivered
  public Decimal driverDistanceMeters;
  public Integer driverWaitSeconds;
  public Integer driverCallsToCustomer;
  public Integer driverChatsToCustomer;

  // Trip geofence (D-097): restaurant, drop-off, and the driver when the order was marked delivered
  public Decimal restaurantLatitude;
  public Decimal restaurantLongitude;
  public Decimal dropoffLatitude;
  public Decimal dropoffLongitude;
  public Decimal driverLatitude;
  public Decimal driverLongitude;

  // History
  public Decimal customerClaimRate; // 0..1
  public Integer customerOrderCount;
  public Decimal driverNonDeliveryRate; // 0..1
  public Integer driverDeliveryCount;

  // Fraud signals
  public Boolean fraudPatternDetected;
  public Boolean deviceDuplicationDetected;
  public Boolean addressDuplicationDetected;

  public Boolean hasPhotoEvidence() {
    return customerPhotoProvided == true || driverPhotoProvided == true;
  }

  public Boolean hasGeofenceCoordinates() {
    return restaurantLatitude != null &&
      restaurantLongitude != null &&
      dropoffLatitude != null &&
      dropoffLongitude != null &&
      driverLatitude != null &&
      driverLongitude != null;
  }

  public Integer contactAttempts() {
    if (driverCallsToCustomer == null && driverChatsToCustomer == null) {
      return null;
    }
    return (driverCallsToCustomer == null ? 0 : driverCallsToCustomer) +
      (driverChatsToCustomer == null ? 0 : driverChatsToCustomer);
  }

  public static CARES_StolenDelayedTelemetry parse(String body) {
    return (CARES_StolenDelayedTelemetry) JSON.deserialize(
      body,
      CARES_StolenDelayedTelemetry.class
    );
  }
}
