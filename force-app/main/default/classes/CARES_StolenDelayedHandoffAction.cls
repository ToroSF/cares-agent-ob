/**
 * Stolen & Delayed Orders: agent action run once the customer has chosen a remedy
 * for an approved claim. It re-checks the decision against fresh data, then:
 *   - REFUND or WALLET_CREDIT: returns READY_FOR_REFUND with the context for
 *     Refund. No money is moved here.
 *   - REDISPATCH: sends the order again.
 * In both cases the trust events for the customer and the driver are queued.
 */
public with sharing class CARES_StolenDelayedHandoffAction {
  public static final String READY_FOR_REFUND = 'READY_FOR_REFUND';
  public static final String REDISPATCHED = 'REDISPATCHED';
  public static final String BLOCKED = 'BLOCKED';
  public static final String FAILED = 'FAILED';

  public static final String CHOICE_REFUND = 'REFUND';
  public static final String CHOICE_WALLET_CREDIT = 'WALLET_CREDIT';
  public static final String CHOICE_REDISPATCH = 'REDISPATCH';

  public class Request {
    @InvocableVariable(
      label='Contact Id'
      description='Contact id from the messaging channel, never from the chat'
      required=true
    )
    public String contactId;

    @InvocableVariable(label='Order Id' required=true)
    public String orderId;

    @InvocableVariable(
      label='Expected Decision'
      description='Decision returned by the evaluate action'
      required=true
    )
    public String expectedDecision;

    @InvocableVariable(
      label='Customer Choice'
      description='REFUND, WALLET_CREDIT or REDISPATCH'
      required=true
    )
    public String customerChoice;
  }

  public class Result {
    @InvocableVariable(
      description='READY_FOR_REFUND, REDISPATCHED, BLOCKED or FAILED'
    )
    public String handoffStatus;
    @InvocableVariable(
      description='Internal reason code. Never shown to the customer'
    )
    public String reasonCode;
    @InvocableVariable(description='Normalised customer choice')
    public String customerChoice;
    @InvocableVariable(
      description='Order total in the order currency, re-checked'
    )
    public Decimal orderTotal;
    @InvocableVariable(description='ISO currency code of the order')
    public String currencyIsoCode;
    @InvocableVariable(description='True for the loss absorption case')
    public Boolean lossAbsorption;
    @InvocableVariable(description='Driver pay recommendation for Refund')
    public String driverCompensation;
    @InvocableVariable(
      description='Restaurant reimbursement recommendation for Refund'
    )
    public String restaurantReimbursement;
    @InvocableVariable(
      description='Platform reference of the re-dispatch, if any'
    )
    public String redispatchReference;
  }

  @InvocableMethod(
    label='CARES Stolen & Delayed: Hand Off Approved Claim'
    description='Re-checks an approved claim. Prepares the context for Refund, or re-dispatches the order. Never issues a refund or credit.'
  )
  public static List<Result> handoff(List<Request> requests) {
    List<Result> results = new List<Result>();
    // Queue jobs only after every callout: a callout after enqueueJob fails.
    List<CARES_StolenDelayedTrustScoreJob> jobs = new List<CARES_StolenDelayedTrustScoreJob>();
    for (Request r : requests) {
      results.add(handoffOne(r, jobs));
    }
    for (CARES_StolenDelayedTrustScoreJob job : jobs) {
      System.enqueueJob(job);
    }
    return results;
  }

  private static Result handoffOne(
    Request r,
    List<CARES_StolenDelayedTrustScoreJob> jobs
  ) {
    Result res = new Result();
    res.customerChoice = r.customerChoice == null
      ? ''
      : r.customerChoice.trim().toUpperCase();
    res.orderTotal = 0;
    res.currencyIsoCode = '';
    res.lossAbsorption = false;
    res.driverCompensation = '';
    res.restaurantReimbursement = '';
    res.redispatchReference = '';

    if (
      res.customerChoice != CHOICE_REFUND &&
      res.customerChoice != CHOICE_WALLET_CREDIT &&
      res.customerChoice != CHOICE_REDISPATCH
    ) {
      return status(res, BLOCKED, 'INVALID_CHOICE');
    }
    if (
      r.expectedDecision != CARES_StolenDelayedPolicy.FULL_REFUND &&
      r.expectedDecision != CARES_StolenDelayedPolicy.LOSS_ABSORPTION
    ) {
      return status(res, BLOCKED, 'NOT_APPROVED');
    }

    // Re-check with fresh data. The report was already screened by evaluate.
    CARES_StolenDelayedPolicy.Outcome d = CARES_StolenDelayedPolicy.evaluate(
      r.contactId,
      r.orderId,
      null
    );
    if (d.decision != r.expectedDecision) {
      return status(res, BLOCKED, 'DECISION_CHANGED');
    }
    res.orderTotal = d.orderTotal == null ? 0 : d.orderTotal;
    res.currencyIsoCode = d.currencyIsoCode == null ? '' : d.currencyIsoCode;
    res.lossAbsorption =
      d.decision == CARES_StolenDelayedPolicy.LOSS_ABSORPTION;
    res.driverCompensation = d.driverCompensation;
    res.restaurantReimbursement = d.restaurantReimbursement;

    // Trust events go to the delivery platform or, with mock telemetry, to records, so they
    // are only queued when one of them is switched on (D-089, D-096, SD-G4)
    CARES_StolenDelayedPolicy.Settings settings = CARES_StolenDelayedPolicy.loadSettings();
    Boolean connected = settings.platformEnabled || settings.mockTelemetryEnabled;

    if (res.customerChoice == CHOICE_REDISPATCH) {
      if (!d.redispatchEligible) {
        return status(res, BLOCKED, 'REDISPATCH_NOT_ELIGIBLE');
      }
      try {
        res.redispatchReference = settings.mockTelemetryEnabled
          ? CARES_StolenDelayedMockTelemetry.requestRedispatch(d.orderId, r.contactId)
          : new CARES_StolenDelayedPlatformClient().redispatch(d.orderId, r.contactId);
      } catch (CARES_StolenDelayedPlatformClient.PlatformException e) {
        return status(res, FAILED, 'REDISPATCH_FAILED');
      }
      if (connected) {
        jobs.add(new CARES_StolenDelayedTrustScoreJob(d.orderId, r.contactId, d));
      }
      return status(res, REDISPATCHED, d.reasonCode);
    }

    if (connected) {
      jobs.add(new CARES_StolenDelayedTrustScoreJob(d.orderId, r.contactId, d));
    }
    return status(res, READY_FOR_REFUND, d.reasonCode);
  }

  private static Result status(
    Result res,
    String handoffStatus,
    String reason
  ) {
    res.handoffStatus = handoffStatus;
    res.reasonCode = reason;
    return res;
  }
}
