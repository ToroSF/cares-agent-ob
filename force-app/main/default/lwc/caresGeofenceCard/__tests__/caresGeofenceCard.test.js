import { createElement } from "lwc";
import CaresGeofenceCard, { formatDistance } from "c/caresGeofenceCard";

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
const MATCH = {
  ...MISMATCH,
  scenario: "LOSS_ABSORPTION",
  gpsResult: "MATCH",
  driver: { latitude: 40.749918, longitude: -73.985049 },
  driverToCenterMeters: 502.1,
  driverToDropoffMeters: 10.4
};

function mount(view, audience, allowRealMap) {
  const el = createElement("c-cares-geofence-card", { is: CaresGeofenceCard });
  el.view = view;
  if (audience) {
    el.audience = audience;
  }
  if (allowRealMap) {
    el.allowRealMap = true;
  }
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();

describe("c-cares-geofence-card", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("always shows the real map with the circle and the three points, and the result above it", () => {
    const root = mount(MISMATCH).shadowRoot;
    expect(root.querySelector(".eyebrow").textContent).toBe(
      "Pronto · Delivery details"
    );
    expect(root.querySelector(".order-line").textContent).toBe(
      "Order PR-240101-TEST001 · $41.70"
    );
    expect(root.querySelector("svg")).toBeNull();
    const markers = root.querySelector("lightning-map").mapMarkers;
    expect(markers).toHaveLength(4);
    expect(markers[0]).toMatchObject({ type: "Circle", radius: 562.3 });
    expect(markers.slice(1).map((m) => m.title)).toEqual([
      "Restaurant",
      "Drop-off",
      "Driver when marked delivered"
    ]);
    const band = root.querySelector(".result-band");
    expect(band.classList).toContain("mismatch");
    expect(band.textContent).toBe(
      "GPS mismatch · the driver marked the order delivered 2.2 km from the centre of the trip"
    );
    expect(root.querySelector(".actions")).toBeNull();
  });

  it("colours the result band green for a match", async () => {
    const el = mount(MATCH);
    await flush();
    const band = el.shadowRoot.querySelector(".result-band");
    expect(band.classList).toContain("match");
    expect(band.textContent).toContain("GPS match");
    expect(band.textContent).toContain("502 m");
  });

  it("shows the measurements and the G-111 note to the team", () => {
    const root = mount(MISMATCH).shadowRoot;
    expect(root.querySelector(".facts").textContent).toContain("GPS_MISMATCH");
    expect(root.querySelector(".note").textContent).toContain("G-111");
  });

  it("shows a customer the real map only where the page allows it, without the team-only parts", () => {
    const allowed = mount(MISMATCH, "customer", true).shadowRoot;
    expect(allowed.querySelector("lightning-map")).not.toBeNull();
    expect(allowed.querySelector(".result-band")).not.toBeNull();
    expect(allowed.querySelector(".facts")).toBeNull();
    expect(allowed.querySelector(".note")).toBeNull();
    const notAllowed = mount(MISMATCH, "customer").shadowRoot;
    expect(notAllowed.querySelector("lightning-map")).toBeNull();
  });

  it("explains the distance rule when the row has no locations", () => {
    const root = mount({
      found: true,
      orderId: "PR-240101-TEST002",
      hasCoordinates: false,
      gpsResult: "MISMATCH",
      driverDistanceMeters: 450
    }).shadowRoot;
    expect(root.querySelector("lightning-map")).toBeNull();
    expect(root.querySelector(".message").textContent).toContain(
      "450 m from the drop-off → GPS mismatch"
    );
  });

  it("says a person decides when the row has no driver location at all", () => {
    const root = mount({
      found: true,
      orderId: "PR-240101-TEST003",
      hasCoordinates: false,
      gpsResult: "UNKNOWN",
      driverDistanceMeters: null
    }).shadowRoot;
    expect(root.querySelector(".message").textContent).toContain(
      "GPS is unknown, so a person decides the driver pay"
    );
  });

  it("shows a dash when the total is unavailable", () => {
    const root = mount({ ...MISMATCH, orderTotal: null }).shadowRoot;
    expect(root.querySelector(".order-line").textContent).toBe(
      "Order PR-240101-TEST001 · —"
    );
  });
});

describe("formatDistance", () => {
  it("formats meters and kilometers", () => {
    expect(formatDistance(30.4)).toBe("30 m");
    expect(formatDistance(2160)).toBe("2.2 km");
    expect(formatDistance(null)).toBe("—");
  });
});
