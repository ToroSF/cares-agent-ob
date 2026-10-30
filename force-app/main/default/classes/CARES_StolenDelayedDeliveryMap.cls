/**
 * Stolen & Delayed Orders: read-only agent action that returns the delivery map card of an approved
 * claim, shown to the customer in the chat (Custom Lightning Type c__caresDeliveryMapView, D-106, G-137).
 *
 * The card is shown only when it backs a decision in the customer's favour: the order is re-checked
 * with the policy (which also proves it is this customer's order) and must come out FULL_REFUND or
 * LOSS_ABSORPTION, with the three locations known. Manual review, escalation (fraud, high value,
 * low trust) and orders without locations get no card, so the check is not shown to a claim that
 * is still open (R-18). The numbers come from CARES_GeofenceMapController.build, the same as the
 * CARES Admin view (D-105). Writes nothing and moves no money.
 */
public with sharing class CARES_StolenDelayedDeliveryMap {
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
    public CARES_GeofenceCardView deliveryMap;

    @InvocableVariable(
      label='Map Url'
      description='Signed link to the delivery map page, valid for a short time; blank when no card or no link.'
    )
    public String mapUrl;
  }

  @InvocableMethod(
    label='Show Delivery Map'
    description='Read-only. Returns the delivery map card of an approved Stolen & Delayed claim.'
  )
  public static List<Result> show(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request r : requests) {
      results.add(card(r));
    }
    return results;
  }

  private static Result card(Request r) {
    Result res = new Result();
    if (r == null || String.isBlank(r.contactId) || String.isBlank(r.orderId)) {
      return res;
    }
    // Same re-check as the hand-off: a different order, another customer's order, or a decision that
    // is no longer approved gets nothing
    CARES_StolenDelayedPolicy.Outcome d = CARES_StolenDelayedPolicy.evaluate(
      r.contactId,
      r.orderId,
      ''
    );
    if (
      d.decision != CARES_StolenDelayedPolicy.FULL_REFUND &&
      d.decision != CARES_StolenDelayedPolicy.LOSS_ABSORPTION
    ) {
      return res;
    }
    CARES_GeofenceMapController.View v = CARES_GeofenceMapController.build(
      d.orderId,
      null
    );
    if (v.found != true || v.hasCoordinates != true) {
      return res;
    }
    // The real order's total, as the policy read it
    CARES_GeofenceCardView g = CARES_GeofenceCardView.fromView(
      v,
      d.orderId,
      d.orderTotal,
      d.currencyIsoCode
    );
    res.deliveryMap = g;
    // The page that shows the card outside the chat, with a signed 30-minute link (D-107)
    res.mapUrl = CARES_DeliveryMapLink.issue(
      d.orderId,
      r.contactId,
      d.orderTotal,
      d.currencyIsoCode
    );
    res.success = true;
    return res;
  }
}
