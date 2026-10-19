/**
 * Stolen & Delayed Orders: calls to the delivery platform through the
 * CARES_Delivery_Platform Named Credential. Write calls send an Idempotency-Key
 * so a retry never re-dispatches or flags twice.
 *
 * No refund, credit or payout endpoint lives here on purpose: money is Refund's job.
 */
public with sharing class CARES_StolenDelayedPlatformClient {
  public class PlatformException extends Exception {
  }

  @TestVisible
  private static final String BASE = 'callout:CARES_Delivery_Platform/v1';
  private static final Integer TIMEOUT_MS = 10000;

  /**
   * Delivery context for one order. A 404 means the order does not exist for
   * this customer and is returned as orderFound = false, not as an error.
   */
  public CARES_StolenDelayedTelemetry getDeliveryContext(
    String orderId,
    String contactId
  ) {
    HttpRequest req = request(
      'GET',
      '/orders/' +
        encode(orderId) +
        '/delivery-context?customerRef=' +
        encode(contactId)
    );
    HttpResponse res = send(req);
    if (res.getStatusCode() == 404) {
      CARES_StolenDelayedTelemetry notFound = new CARES_StolenDelayedTelemetry();
      notFound.orderFound = false;
      return notFound;
    }
    expectSuccess(res);
    try {
      return CARES_StolenDelayedTelemetry.parse(res.getBody());
    } catch (JSONException e) {
      throw new PlatformException('Unreadable delivery context');
    }
  }

  /** Sends the order again. Returns the platform's re-dispatch reference. */
  public String redispatch(String orderId, String contactId) {
    HttpRequest req = request(
      'POST',
      '/orders/' + encode(orderId) + '/redispatch'
    );
    req.setHeader('Idempotency-Key', 'CARES-REDISPATCH-' + orderId);
    req.setBody(
      JSON.serialize(new Map<String, Object>{ 'customerRef' => contactId })
    );
    HttpResponse res = send(req);
    expectSuccess(res);
    try {
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        res.getBody()
      );
      return (String) body.get('redispatchId');
    } catch (Exception e) {
      throw new PlatformException('Unreadable re-dispatch response');
    }
  }

  /**
   * Records a trust event for the customer or the driver of the order. The
   * platform resolves the driver from the order, so no driver id is needed here.
   */
  public void recordTrustEvent(
    String subjectType,
    String orderId,
    String contactId,
    String eventType
  ) {
    HttpRequest req = request('POST', '/trust-events');
    req.setHeader(
      'Idempotency-Key',
      'CARES-TRUST-' + subjectType + '-' + eventType + '-' + orderId
    );
    req.setBody(
      JSON.serialize(
        new Map<String, Object>{
          'subjectType' => subjectType,
          'orderId' => orderId,
          'customerRef' => contactId,
          'eventType' => eventType,
          'source' => 'CARES_STOLEN_DELAYED'
        }
      )
    );
    expectSuccess(send(req));
  }

  private static HttpRequest request(String method, String path) {
    HttpRequest req = new HttpRequest();
    req.setMethod(method);
    req.setEndpoint(BASE + path);
    req.setHeader('Content-Type', 'application/json');
    req.setTimeout(TIMEOUT_MS);
    return req;
  }

  private static HttpResponse send(HttpRequest req) {
    try {
      return new Http().send(req);
    } catch (CalloutException e) {
      throw new PlatformException('Delivery platform unreachable');
    }
  }

  private static void expectSuccess(HttpResponse res) {
    Integer code = res.getStatusCode();
    if (code < 200 || code > 299) {
      throw new PlatformException('Delivery platform returned ' + code);
    }
  }

  private static String encode(String value) {
    return EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8');
  }
}
