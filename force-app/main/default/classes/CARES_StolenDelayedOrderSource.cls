/**
 * Stolen & Delayed Orders: builds the delivery context for one order from the real
 * orders (Order__dlm through CARES_OrderData, D-071) and CARES's own resolutions,
 * instead of the delivery platform (D-089). The customer's trust comes from real
 * counts: claims are their CARES_Resolution__c rows, orders are their non-canceled
 * orders (D-090). Fields the order data does not have (photos, GPS, driver, fraud,
 * re-dispatch) stay null, which the policy treats as unknown.
 */
public with sharing class CARES_StolenDelayedOrderSource {
  public static final String DELIVERED = 'DELIVERED';
  public static final String IN_TRANSIT = 'IN_TRANSIT';
  public static final String CANCELED = 'CANCELED';

  public class Result {
    // Null when the order could not be read; decision and reasonCode say why
    public CARES_StolenDelayedTelemetry telemetry;
    public String orderId;
    public String decision;
    public String reasonCode;
  }

  public static Result load(String contactId, String orderNumber) {
    Result res = new Result();
    CARES_OrderData.Lookup l = CARES_OrderData.find(contactId, orderNumber, false);
    if (!l.found) {
      return notRead(res, l.reason);
    }
    CARES_StolenDelayedTelemetry t = new CARES_StolenDelayedTelemetry();
    t.orderFound = true;
    // CARES_OrderData returns only the customer's own orders
    t.customerMatches = true;
    t.orderStatus = deliveryStatus(l.order.status);
    t.orderTotal = l.order.total;
    // Order__dlm has no currency column; same rule as D-082
    t.currencyIsoCode = UserInfo.getDefaultCurrency();
    try {
      t.priorClaimOnOrder =
        [
          SELECT COUNT()
          FROM CARES_Resolution__c
          WHERE Order_Id__c = :l.order.orderId
          WITH USER_MODE
        ] > 0;
      t.customerOrderCount = CARES_OrderData.nonCanceledOrderCount(contactId);
      t.customerClaimRate = claimRate(contactId, t.customerOrderCount);
    } catch (Exception e) {
      // A claim check that can't run must not look like a clean history
      res.decision = CARES_StolenDelayedPolicy.ESCALATE;
      res.reasonCode = 'DATA_UNAVAILABLE';
      return res;
    }
    res.telemetry = t;
    res.orderId = l.order.orderId;
    return res;
  }

  // Order__dlm status words -> the policy's delivery status
  @TestVisible
  private static String deliveryStatus(String status) {
    if (status == 'Delivered') {
      return DELIVERED;
    }
    if (status == 'Canceled') {
      return CANCELED;
    }
    return IN_TRANSIT;
  }

  // Claims per order, 0..1; null when there are no orders to judge by
  private static Decimal claimRate(String contactId, Integer orders) {
    Id cid = toId(contactId);
    if (cid == null || orders == null || orders == 0) {
      return null;
    }
    Integer claims = [
      SELECT COUNT()
      FROM CARES_Resolution__c
      WHERE Contact__c = :cid
      WITH USER_MODE
    ];
    return Decimal.valueOf(claims).divide(orders, 4);
  }

  private static Result notRead(Result res, String reason) {
    if (reason == CARES_OrderData.NO_ACCOUNT_LINK) {
      res.decision = CARES_StolenDelayedPolicy.ESCALATE;
      res.reasonCode = 'NO_ACCOUNT_LINK';
    } else if (reason == CARES_OrderData.DATA_UNAVAILABLE) {
      res.decision = CARES_StolenDelayedPolicy.ESCALATE;
      res.reasonCode = 'DATA_UNAVAILABLE';
    } else if (reason == CARES_OrderData.NOT_A_PRONTO_ORDER_NUMBER) {
      res.decision = CARES_StolenDelayedPolicy.ORDER_NOT_FOUND;
      res.reasonCode = 'INVALID_ORDER_ID';
    } else {
      res.decision = CARES_StolenDelayedPolicy.ORDER_NOT_FOUND;
      res.reasonCode = 'ORDER_NOT_FOUND';
    }
    return res;
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
