import { createElement } from "lwc";
import CaresGeofenceMap from "c/caresGeofenceMap";
import getGeofence from "@salesforce/apex/CARES_GeofenceMapController.getGeofence";
import getGeofenceByOrder from "@salesforce/apex/CARES_GeofenceMapController.getGeofenceByOrder";

jest.mock(
  "@salesforce/apex/CARES_GeofenceMapController.getGeofence",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CARES_GeofenceMapController.getGeofenceByOrder",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

// The seed's GPS_MISMATCH shape: a 1,025 m trip and a driver 2.2 km from the center
const MISMATCH = {
  found: true,
  orderId: "PR-240101-TEST001",
  orderTotal: 41.7,
  currencyIsoCode: "USD",
  scenario: "GPS_MISMATCH",
  gpsResult: "MISMATCH",
  hasCoordinates: true,
  restaurant: { latitude: 40.7416, longitude: -73.99 },
  dropoff: { latitude: 40.75, longitude: -73.985 },
  driver: { latitude: 40.76, longitude: -73.97 },
  center: { latitude: 40.7458, longitude: -73.9875 },
  radiusMeters: 562.3,
  tripMeters: 1024.6,
  toleranceMeters: 50,
  driverToCenterMeters: 2160.4,
  driverToDropoffMeters: 1650.2,
  driverDistanceMeters: null
};

function mount(recordId) {
  const el = createElement("c-cares-geofence-map", { is: CaresGeofenceMap });
  if (recordId) {
    el.recordId = recordId;
  }
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();
const card = (el) => el.shadowRoot.querySelector("c-cares-geofence-card");

describe("c-cares-geofence-map", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("passes the record's geofence to the card, for the team", async () => {
    const el = mount("a00000000000001AAA");
    getGeofence.emit(MISMATCH);
    await flush();
    expect(card(el).view).toEqual(MISMATCH);
    expect(card(el).audience).toBe("admin");
    expect(el.shadowRoot.querySelector("lightning-input")).toBeNull();
  });

  it("says so when the record has no telemetry", async () => {
    const el = mount("a00000000000001AAA");
    getGeofence.emit({ found: false });
    await flush();
    expect(el.shadowRoot.querySelector(".message").textContent).toContain(
      "No delivery telemetry"
    );
  });

  it("looks an order up by number when the page has no record", async () => {
    getGeofenceByOrder.mockResolvedValue(MISMATCH);
    const el = mount(null);
    await flush();
    const input = el.shadowRoot.querySelector("lightning-input");
    input.value = "PR-240101-TEST001";
    input.dispatchEvent(new CustomEvent("change"));
    el.shadowRoot.querySelector(".search lightning-button").click();
    await flush();
    await flush();
    expect(getGeofenceByOrder).toHaveBeenCalledWith({
      orderId: "PR-240101-TEST001"
    });
    expect(card(el).view).toEqual(MISMATCH);
  });
});
