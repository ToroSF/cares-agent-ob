/**
 * DEPRECATED (G-137): kept only for agent v14, whose Lightning type c__caresGeofenceView points at the
 * inner class below. The chat never draws an inner-class type, so v15 uses CARES_StolenDelayedDeliveryMap
 * and c__caresDeliveryMapView instead. Delete this class and c__caresGeofenceView once v14 is retired.
 *
 * Read-only agent action that returns the geofence card of an approved claim (D-106).
 *
 * The card is shown only when it backs a decision in the customer's favour: the order is re-checked
 * with the policy (which also proves it is this customer's order) and must come out FULL_REFUND or
 * LOSS_ABSORPTION, with the three locations known. Manual review, escalation (fraud, high value,
 * low trust) and orders without locations get no card, so the check is not shown to a claim that
 * is still open (R-17). The numbers come from CARES_GeofenceMapController.build, the same as the
 * CARES Admin view (D-105). Writes nothing and moves no money.
 */
public with sharing class CARES_StolenDelayedGeofenceCard {
  @JsonAccess(serializable='always' deserializable='always')
  public class GeofenceView {
    @AuraEnabled
    @InvocableVariable
    public String orderId;
    @AuraEnabled
    @InvocableVariable
    public Decimal orderTotal;
    @AuraEnabled
    @InvocableVariable
    public String currencyIsoCode;
    // MATCH or MISMATCH (the trip geofence never returns AMBIGUOUS)
    @AuraEnabled
    @InvocableVariable
    public String gpsResult;
    @AuraEnabled
    @InvocableVariable
    public Boolean hasCoordinates = false;
    @AuraEnabled
    @InvocableVariable
    public Decimal restaurantLatitude;
    @AuraEnabled
    @InvocableVariable
    public Decimal restaurantLongitude;
    @AuraEnabled
    @InvocableVariable
    public Decimal dropoffLatitude;
    @AuraEnabled
    @InvocableVariable
    public Decimal dropoffLongitude;
    @AuraEnabled
    @InvocableVariable
    public Decimal driverLatitude;
    @AuraEnabled
    @InvocableVariable
    public Decimal driverLongitude;
    @AuraEnabled
    @InvocableVariable
    public Decimal centerLatitude;
    @AuraEnabled
    @InvocableVariable
    public Decimal centerLongitude;
    @AuraEnabled
    @InvocableVariable
    public Decimal radiusMeters;
    @AuraEnabled
    @InvocableVariable
    public Decimal tripMeters;
    @AuraEnabled
    @InvocableVariable
    public Decimal toleranceMeters;
    @AuraEnabled
    @InvocableVariable
    public Decimal driverToCenterMeters;
    @AuraEnabled
    @InvocableVariable
    public Decimal driverToDropoffMeters;
  }

  public class Request {
    @InvocableVariable(
      label='Contact Id'
      description='The customer contact id, from the channel or the email lookup. Never typed by the model.'
      required=true
    )
    public String contactId;

    @InvocableVariable(
      label='Order Id'
      description='Order id returned by the evaluate action.'
      required=true
    )
    public String orderId;
  }

  public class Result {
    @InvocableVariable(
      label='Success'
      description='True only when a card was built for an approved claim.'
    )
    public Boolean success = false;

    @InvocableVariable(
      label='Delivery Map'
      description='The geofence card to display to the customer.'
    )
    public GeofenceView deliveryMap;
  }

  @InvocableMethod(
    label='Show Delivery Map (v14)'
    description='Read-only. Returns the delivery map card of an approved Stolen & Delayed claim.'
  )
  public static List<Result> show(List<Request> requests) {
    List<CARES_StolenDelayedDeliveryMap.Request> asked = new List<CARES_StolenDelayedDeliveryMap.Request>();
    for (Request r : requests) {
      CARES_StolenDelayedDeliveryMap.Request n = new CARES_StolenDelayedDeliveryMap.Request();
      n.contactId = r == null ? null : r.contactId;
      n.orderId = r == null ? null : r.orderId;
      asked.add(n);
    }
    List<Result> results = new List<Result>();
    for (
      CARES_StolenDelayedDeliveryMap.Result n : CARES_StolenDelayedDeliveryMap.show(
        asked
      )
    ) {
      Result res = new Result();
      res.success = n.success;
      // Same fields, so the shape copies across
      res.deliveryMap = n.deliveryMap == null
        ? null
        : (GeofenceView) JSON.deserialize(
            JSON.serialize(n.deliveryMap),
            GeofenceView.class
          );
      results.add(res);
    }
    return results;
  }
}
