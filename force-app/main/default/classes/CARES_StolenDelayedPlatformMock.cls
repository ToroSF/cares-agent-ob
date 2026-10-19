/**
 * Test double for the delivery platform. Responses are matched on method and the
 * start of the path after /v1, and every request is kept for assertions.
 */
@IsTest
public class CARES_StolenDelayedPlatformMock implements HttpCalloutMock {
  private final Map<String, HttpResponse> responses = new Map<String, HttpResponse>();
  public final List<HttpRequest> requests = new List<HttpRequest>();

  public CARES_StolenDelayedPlatformMock respondWith(
    String method,
    String pathPrefix,
    Integer statusCode,
    String body
  ) {
    HttpResponse res = new HttpResponse();
    res.setStatusCode(statusCode);
    res.setBody(body == null ? '' : body);
    responses.put(method + ' ' + pathPrefix, res);
    return this;
  }

  public HttpResponse respond(HttpRequest req) {
    requests.add(req);
    String path = req.getEndpoint().substringAfter('/v1');
    for (String key : responses.keySet()) {
      String method = key.substringBefore(' ');
      String prefix = key.substringAfter(' ');
      if (req.getMethod() == method && path.startsWith(prefix)) {
        return responses.get(key);
      }
    }
    HttpResponse missing = new HttpResponse();
    missing.setStatusCode(500);
    return missing;
  }

  public Integer count(String method, String pathFragment) {
    Integer n = 0;
    for (HttpRequest req : requests) {
      if (
        req.getMethod() == method && req.getEndpoint().contains(pathFragment)
      ) {
        n++;
      }
    }
    return n;
  }

  /** Telemetry for an approved loss absorption case; tests change one field at a time. */
  public static Map<String, Object> goodContext() {
    return new Map<String, Object>{
      'orderFound' => true,
      'customerMatches' => true,
      'orderStatus' => 'DELIVERED',
      'orderTotal' => 42.50,
      'currencyIsoCode' => 'USD',
      'priorClaimOnOrder' => false,
      'redispatchEligible' => true,
      'customerPhotoProvided' => false,
      'driverPhotoProvided' => false,
      'driverDistanceMeters' => 20,
      'driverWaitSeconds' => 240,
      'driverCallsToCustomer' => 1,
      'driverChatsToCustomer' => 1,
      'customerClaimRate' => 0.0,
      'customerOrderCount' => 40,
      'driverNonDeliveryRate' => 0.002,
      'driverDeliveryCount' => 900,
      'fraudPatternDetected' => false,
      'deviceDuplicationDetected' => false,
      'addressDuplicationDetected' => false
    };
  }
}
