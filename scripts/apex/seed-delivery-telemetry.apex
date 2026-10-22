// Seed MOCK delivery telemetry for the Stolen & Delayed demo cases (D-096). Mock data, not a live feed.
// Run after CARES_Delivery_Telemetry__c is deployed:
//   sf apex run --file scripts/apex/seed-delivery-telemetry.apex --target-org <team org>
// Starts with DRY_RUN = true: it prints what it would write and changes nothing. Set it to false to write.
// Safe to run again: rows are matched by Order_ID__c and updated.
// Mock telemetry is only read when CARES_Stolen_Delayed_Policy__mdt.Default.Mock_Telemetry_Enabled__c is on.
//
// Each profile sits on one delivered order of a high-trust test customer (5-6 orders, no claim) from
// scripts/testing/fixtures.json, so a claim on that order shows the profile's outcome. Totals are under
// the 100 USD escalation amount. Once Refund pays a claim, the same order is a duplicate claim: use
// another customer, or pick a new order number here.
//
// The person who runs it needs the CARES_Delivery_Mock_Admin permission set: anonymous Apex checks
// field access when it compiles.

Boolean DRY_RUN = true;

// The same mock trip for every demo order (D-097): a 1,025 m trip, so the geofence is a circle of
// 512 m + 50 m tolerance around its midpoint. Only the driver's position changes per profile.
Decimal RESTAURANT_LAT = 40.741600, RESTAURANT_LON = -73.990000;
Decimal DROPOFF_LAT = 40.750000, DROPOFF_LON = -73.985000;

// Driver point => [latitude, longitude]
Map<String, List<Decimal>> DRIVER_POINTS = new Map<String, List<Decimal>>{
    'AT_DOOR' => new List<Decimal>{ 40.749918, -73.985049 }, // 10 m before the door: inside
    'NEAR_RESTAURANT' => new List<Decimal>{ 40.741846, -73.989854 }, // 30 m from the restaurant: inside (G-111)
    'FAR_AWAY' => new List<Decimal>{ 40.760000, -73.970000 } // 2.2 km from the center: outside
};

// Profile => [driver point, wait s, calls, chats, driver non-delivery %, driver deliveries, fraud, device dup, address dup, re-dispatch]
Map<String, List<Object>> PROFILES = new Map<String, List<Object>>{
    // Inside the geofence, excellent driver: high-trust customer gets loss absorption
    'LOSS_ABSORPTION' => new List<Object>{ 'AT_DOOR', 240, 1, 0, 0.2, 900, false, false, false, false },
    // Outside the geofence: full refund, driver pay withheld
    'GPS_MISMATCH' => new List<Object>{ 'FAR_AWAY', 0, 0, 0, 0.5, 300, false, false, false, false },
    // Inside at the restaurant end of the trip, excellent driver: still loss absorption (known consequence, G-111)
    'INSIDE_NEAR_RESTAURANT' => new List<Object>{ 'NEAR_RESTAURANT', 0, 0, 0, 0.2, 900, false, false, false, false },
    // Inside, but the driver's record is not excellent (4%): full refund, driver paid
    'AVERAGE_DRIVER' => new List<Object>{ 'AT_DOOR', 240, 1, 0, 4.0, 300, false, false, false, false },
    // Fraud and duplication flags: a person reviews
    'FRAUD' => new List<Object>{ 'AT_DOOR', 240, 1, 0, 0.2, 900, true, false, false, false },
    'DEVICE_DUP' => new List<Object>{ 'AT_DOOR', 240, 1, 0, 0.2, 900, false, true, false, false },
    'ADDRESS_DUP' => new List<Object>{ 'AT_DOOR', 240, 1, 0, 0.2, 900, false, false, true, false },
    // Like LOSS_ABSORPTION, and the order can be sent again
    'REDISPATCH' => new List<Object>{ 'AT_DOOR', 240, 1, 0, 0.2, 900, false, false, false, true }
};

// Order number => profile. Fixture in brackets.
Map<String, String> ORDERS = new Map<String, String>{
    'PR-240826-YLNU39N' => 'LOSS_ABSORPTION', // P-MARTA-BASSINDALE
    'PR-240829-5WE179W' => 'GPS_MISMATCH', // P-ROZANNE-DEVEREUX
    'PR-240826-AL2NKVM' => 'INSIDE_NEAR_RESTAURANT', // P-PEYTON-BATRICK
    'PR-240827-L9KMKYL' => 'AVERAGE_DRIVER', // P-DORE-BRIANT
    'PR-240827-HQ2DT25' => 'FRAUD', // P-BRUCE-CLEMENDOT
    'PR-240822-GY8RVKV' => 'DEVICE_DUP', // P-BEATRIX-SHOOTER
    'PR-240828-ZO28CZ7' => 'ADDRESS_DUP', // P-PENNY-DANFORTH
    'PR-240816-CSQI55B' => 'REDISPATCH' // P-HUMFRID-JENDRUSCH
};

// Timing demo (D-100): orders still on their way, with the demo clock "the customer writes N minutes after
// ordering" (the data is from 2024-2025, so real time makes every open order look a year late). No driver data:
// timing alone decides. Expected classes were checked against each order's estimate and pickup time on 2026-10-22.
// Order number => [profile, minutes since order]. Customer in brackets (contacts with 5+ orders, no refund).
Map<String, List<Object>> TIMING_ORDERS = new Map<String, List<Object>>{
    'PR-240614-8T45OO8' => new List<Object>{ 'NOT_LATE_YET', 20 }, // Preparing, estimate +41 min (Wadsworth Power)
    'PR-240806-Q35G73D' => new List<Object>{ 'DELAY_MINOR', 55 }, // Out for Delivery, estimate +44: 11 late (Shelby Trathen)
    'PR-240714-QGYZQBQ' => new List<Object>{ 'DELAY_SEVERE', 70 }, // Preparing, estimate +30: 40 late (Leeann Lieber)
    'PR-240615-89IDJP1' => new List<Object>{ 'LOST_IN_TRANSIT', 160 } // Picked up at +22: courier 138 min (Cora St. Quintin)
};

List<CARES_Delivery_Telemetry__c> rows = new List<CARES_Delivery_Telemetry__c>();
Integer n = 0;
for (String orderId : ORDERS.keySet()) {
    String profile = ORDERS.get(orderId);
    List<Object> v = PROFILES.get(profile);
    n++;
    List<Decimal> driver = DRIVER_POINTS.get((String) v[0]);
    rows.add(
        new CARES_Delivery_Telemetry__c(
            Order_ID__c = orderId,
            Scenario__c = profile,
            Driver_ID__c = 'DRV-MOCK-' + String.valueOf(n).leftPad(3, '0'),
            Restaurant_Location__Latitude__s = RESTAURANT_LAT,
            Restaurant_Location__Longitude__s = RESTAURANT_LON,
            Dropoff_Location__Latitude__s = DROPOFF_LAT,
            Dropoff_Location__Longitude__s = DROPOFF_LON,
            Driver_Location__Latitude__s = driver[0],
            Driver_Location__Longitude__s = driver[1],
            // The trip geofence decides; the older distance field stays blank (D-097)
            Driver_Distance_Meters__c = null,
            Driver_Wait_Seconds__c = (Integer) v[1],
            Driver_Calls__c = (Integer) v[2],
            Driver_Chats__c = (Integer) v[3],
            Driver_NonDelivery_Rate__c = (Decimal) v[4],
            Driver_Delivery_Count__c = (Integer) v[5],
            Fraud_Pattern__c = (Boolean) v[6],
            Device_Duplication__c = (Boolean) v[7],
            Address_Duplication__c = (Boolean) v[8],
            Redispatch_Eligible__c = (Boolean) v[9]
        )
    );
    System.debug(LoggingLevel.WARN, orderId + ' => ' + profile + ' ' + v);
}

for (String orderId : TIMING_ORDERS.keySet()) {
    List<Object> v = TIMING_ORDERS.get(orderId);
    rows.add(
        new CARES_Delivery_Telemetry__c(
            Order_ID__c = orderId,
            Scenario__c = (String) v[0],
            Minutes_Since_Order__c = (Integer) v[1]
        )
    );
    System.debug(LoggingLevel.WARN, orderId + ' => ' + v[0] + ' (customer writes ' + v[1] + ' min after ordering)');
}

if (DRY_RUN) {
    System.debug(LoggingLevel.WARN, 'DRY_RUN: ' + rows.size() + ' rows not written. Set DRY_RUN = false to write.');
} else {
    List<Database.UpsertResult> results = Database.upsert(rows, CARES_Delivery_Telemetry__c.Order_ID__c, false);
    Integer created = 0, updated = 0, failed = 0;
    for (Integer i = 0; i < results.size(); i++) {
        if (!results[i].isSuccess()) {
            failed++;
            System.debug(LoggingLevel.ERROR, 'Not saved: ' + rows[i].Order_ID__c + ' ' + results[i].getErrors());
        } else if (results[i].isCreated()) {
            created++;
        } else {
            updated++;
        }
    }
    System.debug(LoggingLevel.WARN, 'Created: ' + created + ', updated: ' + updated + ', failed: ' + failed);
}
