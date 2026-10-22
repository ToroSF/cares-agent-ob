/**
 * Stolen & Delayed Orders: read-only agent action. Checks one order and returns
 * the decision and the context Refund needs. Moves no money and writes nothing.
 */
public with sharing class CARES_StolenDelayedEvaluateAction {
  public class Request {
    @InvocableVariable(
      label='Contact Id'
      description='Contact id from the messaging channel, never from the chat'
      required=true
    )
    public String contactId;

    @InvocableVariable(
      label='Order Id'
      description='Order number given by the customer'
      required=true
    )
    public String orderId;

    @InvocableVariable(
      label='Customer Report'
      description='What the customer said happened, in their own words'
    )
    public String customerReport;

    @InvocableVariable(
      label='Claim Type'
      description='What the customer says: NOT_RECEIVED (never arrived or not here), LATE (late or still waiting) or UNSURE'
    )
    public String claimType;
  }

  public class Result {
    @InvocableVariable(
      description='STANDARD_PATH, FULL_REFUND, LOSS_ABSORPTION, MANUAL_REVIEW, ESCALATE, ORDER_NOT_FOUND, DELAY, NOT_LATE_YET or DELIVERED_ON_TIME'
    )
    public String decision;
    @InvocableVariable(
      description='Internal reason code. Never shown to the customer'
    )
    public String reasonCode;
    @InvocableVariable(description='Order id as checked')
    public String orderId;
    @InvocableVariable(
      description='False only when the order was not found and may be retried'
    )
    public Boolean isFinal;
    @InvocableVariable(description='True when a person must take over')
    public Boolean needsPerson;
    @InvocableVariable(
      description='True when Refund may refund the full order value'
    )
    public Boolean fullRefundApproved;
    @InvocableVariable(description='Order total in the order currency')
    public Decimal orderTotal;
    @InvocableVariable(description='ISO currency code of the order')
    public String currencyIsoCode;
    @InvocableVariable(description='True when the order can be sent again')
    public Boolean redispatchEligible;
    @InvocableVariable(
      description='PAY_IN_FULL, WITHHOLD_DELIVERY_PAY, HOLD_FOR_REVIEW or blank'
    )
    public String driverCompensation;
    @InvocableVariable(description='REIMBURSE, NO_CHANGE or blank')
    public String restaurantReimbursement;
    @InvocableVariable(
      description='ON_TIME, NOT_LATE_YET, DELAYED_MINOR, DELAYED_SEVERE, LIKELY_LOST or UNKNOWN'
    )
    public String timing;
    @InvocableVariable(description='MINOR or SEVERE for a DELAY, else blank')
    public String delaySeverity;
    @InvocableVariable(
      description='DELAY only: the value Refund offers before its tier ceiling'
    )
    public Decimal delayValue;
    @InvocableVariable(description='Minutes past the expected time')
    public Decimal minutesLate;
    @InvocableVariable(
      description='NOT_LATE_YET only: minutes until the expected time'
    )
    public Decimal minutesUntilExpected;
    @InvocableVariable(description='Delivered orders: minutes the delivery took')
    public Decimal deliveryMinutes;
  }

  @InvocableMethod(
    label='CARES Stolen & Delayed: Evaluate Delivery Exception'
    description='Read-only. Checks the delivery evidence for the order. Returns the decision.'
  )
  public static List<Result> evaluate(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request r : requests) {
      results.add(
        toResult(
          CARES_StolenDelayedPolicy.evaluate(
            r.contactId,
            r.orderId,
            r.customerReport,
            r.claimType
          )
        )
      );
    }
    return results;
  }

  private static Result toResult(CARES_StolenDelayedPolicy.Outcome d) {
    Result r = new Result();
    r.decision = d.decision;
    r.reasonCode = d.reasonCode;
    r.orderId = d.orderId;
    r.isFinal = d.isFinal();
    r.needsPerson = d.needsPerson();
    r.fullRefundApproved = d.fullRefundApproved();
    r.orderTotal = d.orderTotal == null ? 0 : d.orderTotal;
    r.currencyIsoCode = d.currencyIsoCode == null ? '' : d.currencyIsoCode;
    r.redispatchEligible = d.redispatchEligible;
    r.driverCompensation = d.driverCompensation;
    r.restaurantReimbursement = d.restaurantReimbursement;
    r.timing = d.timing;
    r.delaySeverity = d.delaySeverity;
    r.delayValue = d.delayValue == null ? 0 : d.delayValue;
    r.minutesLate = d.minutesLate;
    r.minutesUntilExpected = d.minutesUntilExpected;
    r.deliveryMinutes = d.deliveryMinutes == null ? 0 : d.deliveryMinutes;
    return r;
  }
}
