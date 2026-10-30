import { createElement } from "lwc";
import CaresDeliveryMapPage from "c/caresDeliveryMapPage";
import { CurrentPageReference } from "lightning/navigation";
import view from "@salesforce/apex/CARES_DeliveryMapLink.view";

jest.mock(
  "@salesforce/apex/CARES_DeliveryMapLink.view",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const FLAT = {
  orderId: "PR-240101-TEST001",
  orderTotal: 18.1,
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

// Apex promise, then the re-render
const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

function mount() {
  const el = createElement("c-cares-delivery-map-page", {
    is: CaresDeliveryMapPage
  });
  document.body.appendChild(el);
  return el;
}

describe("c-cares-delivery-map-page", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the card for a valid link", async () => {
    view.mockResolvedValue(FLAT);
    const el = mount();
    CurrentPageReference.emit({ state: { t: "abc.def" } });
    await flush();
    expect(view).toHaveBeenCalledWith({ token: "abc.def" });
    const card = el.shadowRoot.querySelector("c-cares-geofence-card");
    expect(card.audience).toBe("customer");
    expect(card.view.gpsResult).toBe("MISMATCH");
    expect(card.allowRealMap).toBe(true);
    expect(el.shadowRoot.querySelector(".message")).toBeNull();
  });

  it("says the link expired or isn't valid when Apex returns nothing", async () => {
    view.mockResolvedValue(null);
    const el = mount();
    CurrentPageReference.emit({ state: { t: "abc.bad" } });
    await flush();
    expect(el.shadowRoot.querySelector("c-cares-geofence-card")).toBeNull();
    expect(el.shadowRoot.querySelector(".message").textContent).toContain(
      "expired or isn't valid"
    );
  });

  it("says so without calling Apex when there is no link", async () => {
    const el = mount();
    CurrentPageReference.emit({ state: {} });
    await flush();
    expect(view).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector(".message")).not.toBeNull();
  });
});
