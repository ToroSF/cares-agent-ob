import { createElement } from "lwc";
import CaresDeliveryMapRenderer from "c/caresDeliveryMapRenderer";

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

describe("c-cares-delivery-map-renderer", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the card to the customer from the action output", () => {
    const el = createElement("c-cares-delivery-map-renderer", {
      is: CaresDeliveryMapRenderer
    });
    el.value = FLAT;
    document.body.appendChild(el);
    const card = el.shadowRoot.querySelector("c-cares-geofence-card");
    expect(card.audience).toBe("customer");
    expect(card.view.gpsResult).toBe("MISMATCH");
  });

  it("shows nothing without the three locations", () => {
    const el = createElement("c-cares-delivery-map-renderer", {
      is: CaresDeliveryMapRenderer
    });
    el.value = { ...FLAT, hasCoordinates: false };
    document.body.appendChild(el);
    expect(el.shadowRoot.querySelector("c-cares-geofence-card")).toBeNull();
  });
});
