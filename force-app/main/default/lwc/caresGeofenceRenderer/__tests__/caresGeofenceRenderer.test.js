import { createElement } from "lwc";
import CaresGeofenceRenderer, { toView } from "c/caresGeofenceRenderer";

// The flat GeofenceView that CARES_StolenDelayedGeofenceCard returns to the agent
const FLAT = {
  orderId: "PR-240101-TEST001",
  orderTotal: 41.7,
  currencyIsoCode: "USD",
  gpsResult: "MISMATCH",
  hasCoordinates: true,
  restaurantLatitude: 40.7416,
  restaurantLongitude: -73.99,
  dropoffLatitude: 40.75,
  dropoffLongitude: -73.985,
  driverLatitude: 40.76,
  driverLongitude: -73.97,
  centerLatitude: 40.7458,
  centerLongitude: -73.9875,
  radiusMeters: 562.3,
  tripMeters: 1024.6,
  toleranceMeters: 50,
  driverToCenterMeters: 2160.4,
  driverToDropoffMeters: 1650.2
};

function mount(value) {
  const el = createElement("c-cares-geofence-renderer", {
    is: CaresGeofenceRenderer
  });
  el.value = value;
  document.body.appendChild(el);
  return el;
}

describe("c-cares-geofence-renderer", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the card to the customer from the action output", () => {
    const card = mount(FLAT).shadowRoot.querySelector("c-cares-geofence-card");
    expect(card.audience).toBe("customer");
    expect(card.view.driver).toEqual({ latitude: 40.76, longitude: -73.97 });
    expect(card.view.gpsResult).toBe("MISMATCH");
  });

  it("accepts the output wrapped in its name", () => {
    expect(toView({ deliveryMap: FLAT }).center).toEqual({
      latitude: 40.7458,
      longitude: -73.9875
    });
  });

  it("shows nothing without the three locations", () => {
    expect(
      mount({ ...FLAT, hasCoordinates: false }).shadowRoot.querySelector(
        "c-cares-geofence-card"
      )
    ).toBeNull();
    expect(toView(null)).toBeNull();
  });
});
