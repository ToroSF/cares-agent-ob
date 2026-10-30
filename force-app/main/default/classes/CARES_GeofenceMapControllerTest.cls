@IsTest
private class CARES_GeofenceMapControllerTest {
  private static final String ORDER_ID = 'PR-241018-GEOMAP1';

  // Same trip as CARES_StolenDelayedMockTelemetryTest: 1,025 m, so radius = 512 m + 50 m tolerance
  private static final Decimal RESTAURANT_LAT = 40.741600,
    RESTAURANT_LON = -73.990000;
  private static final Decimal DROPOFF_LAT = 40.750000,
    DROPOFF_LON = -73.985000;
  private static final Decimal AT_DOOR_LAT = 40.749918,
    AT_DOOR_LON = -73.985049; // 10 m before the door
  private static final Decimal NEAR_RESTAURANT_LAT = 40.741846,
    NEAR_RESTAURANT_LON = -73.989854; // 30 m from the restaurant
  private static final Decimal FAR_AWAY_LAT = 40.760000,
    FAR_AWAY_LON = -73.970000; // 2.2 km from the center

  private static CARES_Delivery_Telemetry__c telemetry(
    Decimal driverLat,
    Decimal driverLon
  ) {
    CARES_Delivery_Telemetry__c t = new CARES_Delivery_Telemetry__c(
      Order_ID__c = ORDER_ID,
      Driver_ID__c = 'DRV-TEST-1',
      Scenario__c = 'TEST',
      Restaurant_Location__Latitude__s = RESTAURANT_LAT,
      Restaurant_Location__Longitude__s = RESTAURANT_LON,
      Dropoff_Location__Latitude__s = DROPOFF_LAT,
      Dropoff_Location__Longitude__s = DROPOFF_LON,
      Driver_Location__Latitude__s = driverLat,
      Driver_Location__Longitude__s = driverLon
    );
    Database.insert(t, AccessLevel.SYSTEM_MODE);
    return t;
  }

  // The admin who opens the record in CARES Admin
  private static User admin() {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    User u = new User(
      Alias = 'geomap',
      Email = 'geo.map@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Geo Map',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'geo.map.' + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'CARES_Delivery_Mock_Admin'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );
    return u;
  }

  private static CARES_GeofenceMapController.View view(Id telemetryId) {
    CARES_GeofenceMapController.View v;
    System.runAs(admin()) {
      v = CARES_GeofenceMapController.getGeofence(telemetryId);
    }
    return v;
  }

  @IsTest
  static void driverAtTheDoorIsInsideTheGeofence() {
    CARES_GeofenceMapController.mockTotal = 41.70;
    CARES_GeofenceMapController.View v = view(
      telemetry(AT_DOOR_LAT, AT_DOOR_LON).Id
    );
    Assert.isTrue(v.found);
    Assert.isTrue(v.hasCoordinates);
    Assert.areEqual(ORDER_ID, v.orderId);
    Assert.areEqual(41.70, v.orderTotal);
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MATCH, v.gpsResult);
    Assert.isTrue(
      Math.abs(v.radiusMeters - 562.3) < 1,
      'Half of 1,024.6 m plus 50 m, got ' + v.radiusMeters
    );
    Assert.areEqual(50, v.toleranceMeters);
    Assert.isTrue(
      v.driverToDropoffMeters < 15,
      String.valueOf(v.driverToDropoffMeters)
    );
    Assert.isTrue(
      Math.abs(v.center.latitude - 40.745800) < 0.00001,
      String.valueOf(v.center.latitude)
    );
  }

  @IsTest
  static void driverFarAwayIsAMismatch() {
    CARES_GeofenceMapController.View v = view(
      telemetry(FAR_AWAY_LAT, FAR_AWAY_LON).Id
    );
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MISMATCH, v.gpsResult);
    Assert.isTrue(v.driverToCenterMeters > v.radiusMeters);
    Assert.isTrue(
      Math.abs(v.driverToCenterMeters - 2160) < 50,
      '2.2 km from the center, got ' + v.driverToCenterMeters
    );
  }

  @IsTest
  static void driverNearTheRestaurantIsInside() {
    // Known consequence of a trip-centered geofence (G-111): the view shows it as it is
    CARES_GeofenceMapController.View v = view(
      telemetry(NEAR_RESTAURANT_LAT, NEAR_RESTAURANT_LON).Id
    );
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MATCH, v.gpsResult);
    Assert.isTrue(
      v.driverToDropoffMeters > 900,
      String.valueOf(v.driverToDropoffMeters)
    );
  }

  @IsTest
  static void viewAgreesWithThePolicyDecision() {
    // The map and the decision share one calculation
    for (
      List<Decimal> driver : new List<List<Decimal>>{
        new List<Decimal>{ AT_DOOR_LAT, AT_DOOR_LON },
        new List<Decimal>{ NEAR_RESTAURANT_LAT, NEAR_RESTAURANT_LON },
        new List<Decimal>{ FAR_AWAY_LAT, FAR_AWAY_LON }
      }
    ) {
      CARES_StolenDelayedTelemetry t = new CARES_StolenDelayedTelemetry();
      t.restaurantLatitude = RESTAURANT_LAT;
      t.restaurantLongitude = RESTAURANT_LON;
      t.dropoffLatitude = DROPOFF_LAT;
      t.dropoffLongitude = DROPOFF_LON;
      t.driverLatitude = driver[0];
      t.driverLongitude = driver[1];
      CARES_StolenDelayedPolicy.Settings s = new CARES_StolenDelayedPolicy.Settings();
      Boolean inside = CARES_StolenDelayedPolicy.geofence(t, s).inside;
      Assert.areEqual(
        inside
          ? CARES_StolenDelayedPolicy.GPS_MATCH
          : CARES_StolenDelayedPolicy.GPS_MISMATCH,
        CARES_StolenDelayedPolicy.gpsResult(t, s)
      );
    }
  }

  @IsTest
  static void withoutTheDriverLocationTheDistanceRuleApplies() {
    CARES_Delivery_Telemetry__c t = telemetry(null, null);
    t.Driver_Distance_Meters__c = 450;
    Database.update(t, AccessLevel.SYSTEM_MODE);
    CARES_GeofenceMapController.View v = view(t.Id);
    Assert.isTrue(v.found);
    Assert.isFalse(v.hasCoordinates);
    Assert.isNull(v.radiusMeters);
    Assert.areEqual(450, v.driverDistanceMeters);
    Assert.areEqual(CARES_StolenDelayedPolicy.GPS_MISMATCH, v.gpsResult);
    Assert.isNull(
      CARES_StolenDelayedPolicy.geofence(
        new CARES_StolenDelayedTelemetry(),
        new CARES_StolenDelayedPolicy.Settings()
      )
    );
  }

  @IsTest
  static void unknownRecordOrOrderReturnsNotFound() {
    CARES_Delivery_Telemetry__c t = telemetry(AT_DOOR_LAT, AT_DOOR_LON);
    Id deletedId = t.Id;
    Database.delete(t, AccessLevel.SYSTEM_MODE);
    Assert.isFalse(view(deletedId).found);
    System.runAs(admin()) {
      Assert.isFalse(
        CARES_GeofenceMapController.getGeofenceByOrder('PR-000000-NOORDER')
          .found
      );
      Assert.isFalse(
        CARES_GeofenceMapController.getGeofenceByOrder('not an order').found
      );
      Assert.isFalse(
        CARES_GeofenceMapController.getGeofenceByOrder(null).found
      );
    }
  }

  @IsTest
  static void findsTheRowByOrderNumberAndShowsNoTotalWhenUnavailable() {
    telemetry(FAR_AWAY_LAT, FAR_AWAY_LON);
    CARES_GeofenceMapController.View v;
    System.runAs(admin()) {
      v = CARES_GeofenceMapController.getGeofenceByOrder(' pr-241018-geomap1 ');
    }
    Assert.isTrue(v.found);
    Assert.areEqual(ORDER_ID, v.orderId);
    Assert.isNull(
      v.orderTotal,
      'No total from Data Cloud: the header shows a dash'
    );
    Assert.areEqual('TEST', v.scenario);
  }
}
