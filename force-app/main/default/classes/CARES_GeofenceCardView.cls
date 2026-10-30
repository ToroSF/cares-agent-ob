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
}
