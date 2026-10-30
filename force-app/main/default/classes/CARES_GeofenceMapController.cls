/**
 * Stolen & Delayed Orders: read-only data for the geofence view (caresGeofenceMap, D-105).
 * Reads one mock telemetry row (D-096) and returns the trip geofence (D-097) with the same
 * math and the same GPS result the policy decides on, so the picture can never disagree
 * with the decision. Writes nothing and moves no money.
 */
public with sharing class CARES_GeofenceMapController {
  private static final Pattern ORDER_ID_FORMAT = Pattern.compile(
    'PR-[0-9]{6}-[A-Z0-9]{7}'
  );

  // Order total from Order__dlm in tests, where Data Cloud does not run
  @TestVisible
  private static Decimal mockTotal;

  public class Point {
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
  }

  public class View {
    @AuraEnabled
    public Boolean found = false;
    @AuraEnabled
    public String orderId;
    @AuraEnabled
    public Decimal orderTotal;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public String scenario;
    // MATCH, MISMATCH, AMBIGUOUS or UNKNOWN, from CARES_StolenDelayedPolicy.gpsResult
    @AuraEnabled
    public String gpsResult;
    @AuraEnabled
    public Boolean hasCoordinates = false;
    @AuraEnabled
    public Point restaurant;
    @AuraEnabled
    public Point dropoff;
    @AuraEnabled
    public Point driver;
    @AuraEnabled
    public Point center;
    @AuraEnabled
    public Decimal radiusMeters;
    @AuraEnabled
    public Decimal tripMeters;
    @AuraEnabled
    public Decimal toleranceMeters;
    @AuraEnabled
    public Decimal driverToCenterMeters;
    @AuraEnabled
    public Decimal driverToDropoffMeters;
    // Without the three locations: the older distance-from-drop-off rule
    @AuraEnabled
    public Decimal driverDistanceMeters;
  }

  @AuraEnabled(cacheable=true)
  public static View getGeofence(Id telemetryId) {
    List<CARES_Delivery_Telemetry__c> rows = [
      SELECT Order_ID__c, Scenario__c
      FROM CARES_Delivery_Telemetry__c
      WHERE Id = :telemetryId
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty()
      ? new View()
      : build(rows[0].Order_ID__c, rows[0].Scenario__c);
  }

  @AuraEnabled(cacheable=true)
  public static View getGeofenceByOrder(String orderId) {
    String clean = orderId == null ? '' : orderId.trim().toUpperCase();
    if (!ORDER_ID_FORMAT.matcher(clean).matches()) {
      return new View();
    }
    List<CARES_Delivery_Telemetry__c> rows = [
      SELECT Order_ID__c, Scenario__c
      FROM CARES_Delivery_Telemetry__c
      WHERE Order_ID__c = :clean
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty()
      ? new View()
      : build(rows[0].Order_ID__c, rows[0].Scenario__c);
  }

  // Also used by the chat card (CARES_StolenDelayedGeofenceCard, D-106), so both show the same numbers
  public static View build(String orderId, String scenario) {
    return build(orderId, scenario, AccessLevel.USER_MODE);
  }

  // SYSTEM_MODE only for the delivery map page, after its signed link is verified (CARES_DeliveryMapLink, D-107)
  public static View build(String orderId, String scenario, AccessLevel mode) {
    View v = new View();
    CARES_StolenDelayedTelemetry t = CARES_StolenDelayedMockTelemetry.forOrder(
      orderId,
      mode
    );
    if (t == null) {
      return v;
    }
    CARES_StolenDelayedPolicy.Settings s = CARES_StolenDelayedPolicy.loadSettings();
    v.found = true;
    v.orderId = orderId;
    v.scenario = scenario;
    v.orderTotal = mode == AccessLevel.SYSTEM_MODE ? null : orderTotal(orderId);
    // Order__dlm has no currency column; same rule as CARES_StolenDelayedOrderSource
    v.currencyIsoCode = UserInfo.getDefaultCurrency();
    v.gpsResult = CARES_StolenDelayedPolicy.gpsResult(t, s);
    v.driverDistanceMeters = t.driverDistanceMeters;
    CARES_StolenDelayedPolicy.Geofence g = CARES_StolenDelayedPolicy.geofence(
      t,
      s
    );
    if (g == null) {
      return v;
    }
    v.hasCoordinates = true;
    v.restaurant = point(t.restaurantLatitude, t.restaurantLongitude);
    v.dropoff = point(t.dropoffLatitude, t.dropoffLongitude);
    v.driver = point(t.driverLatitude, t.driverLongitude);
    v.center = point(g.centerLatitude, g.centerLongitude);
    v.radiusMeters = g.radiusMeters.setScale(1);
    v.tripMeters = g.tripMeters.setScale(1);
    v.toleranceMeters = g.toleranceMeters;
    v.driverToCenterMeters = g.driverToCenterMeters.setScale(1);
    v.driverToDropoffMeters = g.driverToDropoffMeters.setScale(1);
    return v;
  }

  private static Point point(Decimal latitude, Decimal longitude) {
    Point p = new Point();
    p.latitude = latitude;
    p.longitude = longitude;
    return p;
  }

  // The header shows the total; null (shown as "—") when Data Cloud can't be read
  private static Decimal orderTotal(String orderId) {
    if (Test.isRunningTest()) {
      return mockTotal;
    }
    if (!ORDER_ID_FORMAT.matcher(orderId).matches()) {
      return null;
    }
    try {
      ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
      // orderId matched ORDER_ID_FORMAT, so it holds no quote
      input.sql =
        'SELECT Total_Amount__c FROM Order__dlm WHERE Order_ID__c = \'' +
        orderId +
        '\' LIMIT 1';
      ConnectApi.CdpQueryOutputV2 output = ConnectApi.CdpQuery.queryAnsiSqlV2(
        input
      );
      if (output == null || output.data == null || output.data.isEmpty()) {
        return null;
      }
      Object value = output.data[0].rowData[0];
      return value == null ? null : Decimal.valueOf(String.valueOf(value));
    } catch (Exception e) {
      return null;
    }
  }
}
