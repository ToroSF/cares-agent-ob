/**
 * Stolen & Delayed Orders: the data of the delivery map card in the customer's chat (D-106). The Custom
 * Lightning Type c__caresGeofenceView points here. A Lightning type needs a top-level, global class
 * with @JsonAccess and @AuraEnabled fields: an inner class (CARES_StolenDelayedGeofenceCard.GeofenceView,
 * the first version) returns the data but the chat never draws it (G-137).
 */
@JsonAccess(serializable='always' deserializable='always')
global class CARES_GeofenceCardView {
  @AuraEnabled
  @InvocableVariable
  global String orderId;
  @AuraEnabled
  @InvocableVariable
  global Decimal orderTotal;
  @AuraEnabled
  @InvocableVariable
  global String currencyIsoCode;
  // MATCH or MISMATCH (the trip geofence never returns AMBIGUOUS)
  @AuraEnabled
  @InvocableVariable
  global String gpsResult;
  @AuraEnabled
  @InvocableVariable
  global Boolean hasCoordinates = false;
  @AuraEnabled
  @InvocableVariable
  global Decimal restaurantLatitude;
  @AuraEnabled
  @InvocableVariable
  global Decimal restaurantLongitude;
  @AuraEnabled
  @InvocableVariable
  global Decimal dropoffLatitude;
  @AuraEnabled
  @InvocableVariable
  global Decimal dropoffLongitude;
  @AuraEnabled
  @InvocableVariable
  global Decimal driverLatitude;
  @AuraEnabled
  @InvocableVariable
  global Decimal driverLongitude;
  @AuraEnabled
  @InvocableVariable
  global Decimal centerLatitude;
  @AuraEnabled
  @InvocableVariable
  global Decimal centerLongitude;
  @AuraEnabled
  @InvocableVariable
  global Decimal radiusMeters;
  @AuraEnabled
  @InvocableVariable
  global Decimal tripMeters;
  @AuraEnabled
  @InvocableVariable
  global Decimal toleranceMeters;
  @AuraEnabled
  @InvocableVariable
  global Decimal driverToCenterMeters;
  @AuraEnabled
  @InvocableVariable
  global Decimal driverToDropoffMeters;

  // The card for one order: the geofence view (CARES_GeofenceMapController.build) plus the order's total.
  // Shared by the chat action and the delivery map page (D-106, D-107)
  public static CARES_GeofenceCardView fromView(
    CARES_GeofenceMapController.View v,
    String orderId,
    Decimal orderTotal,
    String currencyIsoCode
  ) {
    CARES_GeofenceCardView g = new CARES_GeofenceCardView();
    g.orderId = orderId;
    g.orderTotal = orderTotal;
    g.currencyIsoCode = currencyIsoCode;
    g.gpsResult = v.gpsResult;
    g.hasCoordinates = true;
    g.restaurantLatitude = v.restaurant.latitude;
    g.restaurantLongitude = v.restaurant.longitude;
    g.dropoffLatitude = v.dropoff.latitude;
    g.dropoffLongitude = v.dropoff.longitude;
    g.driverLatitude = v.driver.latitude;
    g.driverLongitude = v.driver.longitude;
    g.centerLatitude = v.center.latitude;
    g.centerLongitude = v.center.longitude;
    g.radiusMeters = v.radiusMeters;
    g.tripMeters = v.tripMeters;
    g.toleranceMeters = v.toleranceMeters;
    g.driverToCenterMeters = v.driverToCenterMeters;
    g.driverToDropoffMeters = v.driverToDropoffMeters;
    return g;
  }
}
