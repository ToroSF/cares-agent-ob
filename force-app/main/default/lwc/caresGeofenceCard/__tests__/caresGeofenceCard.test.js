import { createElement } from "lwc";
import CaresGeofenceCard, {
  formatDistance,
  project,
  splitByCircle
} from "c/caresGeofenceCard";

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

function mount(view, audience) {
  const el = createElement("c-cares-geofence-card", { is: CaresGeofenceCard });
  el.view = view;
  if (audience) {
    el.audience = audience;
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

  it("draws the geofence, the three points and the pill in the delivery-card style", () => {
    const root = mount(MISMATCH).shadowRoot;
    expect(root.querySelector(".eyebrow").textContent).toBe(
      "Pronto · Delivery details"
    );
    expect(root.querySelector(".order-line").textContent).toBe(
      "Order PR-240101-TEST001 · $41.70"
    );
    expect(root.querySelector("circle.geofence")).not.toBeNull();
    expect(root.querySelectorAll("circle.stop")).toHaveLength(2);
    const labels = [...root.querySelectorAll(".stop-label")].map((t) =>
      t.textContent.trim()
    );
    expect(labels).toEqual(["Restaurant", "Drop-off"]);
    expect(root.querySelector(".pill-text").textContent.trim()).toBe(
      "GPS mismatch · 2.2 km"
    );
    expect(root.querySelector("desc").textContent).toContain("decorative");
  });

  it("uses pink for a mismatch and green for a match", async () => {
    const el = mount(MISMATCH);
    expect(el.shadowRoot.querySelector(".driver-dot").classList).toContain(
      "mismatch"
    );
    expect(el.shadowRoot.querySelector(".route-outside").classList).toContain(
      "mismatch"
    );
    el.view = MATCH;
    await flush();
    expect(el.shadowRoot.querySelector(".driver-dot").classList).toContain(
      "match"
    );
    expect(el.shadowRoot.querySelector(".pill-text").textContent.trim()).toBe(
      "GPS match · 502 m"
    );
  });

  it("shows the measurements, the G-111 note and the real-map switch to the team", async () => {
    const el = mount(MISMATCH);
    const root = el.shadowRoot;
    expect(root.querySelector(".facts").textContent).toContain("GPS_MISMATCH");
    expect(root.querySelector(".note").textContent).toContain("G-111");
    root.querySelector(".actions lightning-button").click();
    await flush();
    expect(root.querySelector("svg")).toBeNull();
    const map = root.querySelector("lightning-map");
    expect(map.mapMarkers[0]).toMatchObject({ type: "Circle", radius: 562.3 });
    expect(map.mapMarkers).toHaveLength(4);
  });

  it("hides the team-only parts from a customer", () => {
    const root = mount(MISMATCH, "customer").shadowRoot;
    expect(root.querySelector("circle.geofence")).not.toBeNull();
    expect(root.querySelector(".pill-text").textContent.trim()).toBe(
      "GPS mismatch · 2.2 km"
    );
    expect(root.querySelector(".facts")).toBeNull();
    expect(root.querySelector(".note")).toBeNull();
    expect(root.querySelector(".actions")).toBeNull();
    expect(root.querySelector("lightning-map")).toBeNull();
  });

  it("explains the distance rule when the row has no locations", () => {
    const root = mount({
      found: true,
      orderId: "PR-240101-TEST002",
      hasCoordinates: false,
      gpsResult: "MISMATCH",
      driverDistanceMeters: 450
    }).shadowRoot;
    expect(root.querySelector("svg")).toBeNull();
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

describe("geometry helpers", () => {
  it("formats meters and kilometers", () => {
    expect(formatDistance(30.4)).toBe("30 m");
    expect(formatDistance(2160)).toBe("2.2 km");
    expect(formatDistance(null)).toBe("—");
  });

  it("keeps north up and the circle inside the card", () => {
    const s = project(MISMATCH);
    expect(s.dropoff.y).toBeLessThan(s.restaurant.y);
    expect(s.center.x - s.radius).toBeGreaterThanOrEqual(0);
    expect(s.center.y + s.radius).toBeLessThanOrEqual(380);
  });

  it("splits a segment where it leaves the circle", () => {
    const pieces = splitByCircle(
      { x: 0, y: 0 },
      { x: 20, y: 0 },
      { x: 0, y: 0 },
      10
    );
    expect(pieces).toHaveLength(2);
    expect(pieces[0]).toMatchObject({ inside: true, x2: 10 });
    expect(pieces[1]).toMatchObject({ inside: false, x1: 10 });
  });
});
