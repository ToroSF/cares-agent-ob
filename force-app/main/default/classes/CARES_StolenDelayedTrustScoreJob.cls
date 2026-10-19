/**
 * Stolen & Delayed Orders: flags the claim on both profiles in the background so
 * the conversation does not wait on it. Each event is sent on its own; one
 * failing does not stop the other.
 */
public with sharing class CARES_StolenDelayedTrustScoreJob implements Queueable, Database.AllowsCallouts {
  public static final String CUSTOMER = 'CUSTOMER';
  public static final String DRIVER = 'DRIVER';

  public static final String CUSTOMER_REFUNDED_NO_EVIDENCE = 'CLAIM_APPROVED_NO_EVIDENCE';
  public static final String CUSTOMER_LOSS_ABSORBED = 'CLAIM_LOSS_ABSORBED';
  public static final String DRIVER_NON_DELIVERY_SUSPECTED = 'NON_DELIVERY_SUSPECTED';
  public static final String DRIVER_NO_FAULT = 'CLAIM_RECORDED_NO_FAULT';

  private final String orderId;
  private final String contactId;
  @TestVisible
  private final String customerEvent;
  @TestVisible
  private final String driverEvent;

  public CARES_StolenDelayedTrustScoreJob(
    String orderId,
    String contactId,
    CARES_StolenDelayedPolicy.Outcome d
  ) {
    this.orderId = orderId;
    this.contactId = contactId;
    this.customerEvent = d.decision == CARES_StolenDelayedPolicy.LOSS_ABSORPTION
      ? CUSTOMER_LOSS_ABSORBED
      : CUSTOMER_REFUNDED_NO_EVIDENCE;
    this.driverEvent = d.driverCompensation ==
      CARES_StolenDelayedPolicy.DRIVER_WITHHOLD
      ? DRIVER_NON_DELIVERY_SUSPECTED
      : DRIVER_NO_FAULT;
  }

  public void execute(QueueableContext context) {
    CARES_StolenDelayedPlatformClient client = new CARES_StolenDelayedPlatformClient();
    send(client, CUSTOMER, customerEvent);
    send(client, DRIVER, driverEvent);
  }

  private void send(
    CARES_StolenDelayedPlatformClient client,
    String subjectType,
    String eventType
  ) {
    try {
      client.recordTrustEvent(subjectType, orderId, contactId, eventType);
    } catch (CARES_StolenDelayedPlatformClient.PlatformException e) {
      // No retry yet (see the subagent doc, gaps). Never surfaces to the customer.
      System.debug(
        LoggingLevel.ERROR,
        'CARES trust event failed: ' + subjectType + ' ' + e.getMessage()
      );
    }
  }
}
