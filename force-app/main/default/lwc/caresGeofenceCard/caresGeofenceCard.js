import { LightningElement, api } from "lwc";

// Stolen & Delayed: the trip geofence card in Pronto's delivery-card style (D-105). Presentation only:
// it draws the view it is given. The admin page (caresGeofenceMap) and the agent chat
// (caresGeofenceRenderer, D-106) both use it, so the two never look different.
// audience = "customer" hides what is for the team only: the demo scenario, the G-111 note and the measurements.
// The card is always the real map (Google Maps, lightning-map) with a result band on top (D-108). The real map
// sends the coordinates to Google (G-136): the team always has it, a customer only where the page turns it on
// with allow-real-map (the delivery map page, D-107).

export function formatDistance(meters) {
  if (meters === null || meters === undefined) {
    return "—";
  }
  return meters < 1000
    ? `${Math.round(meters)} m`
    : `${(meters / 1000).toFixed(1)} km`;
}

export default class CaresGeofenceCard extends LightningElement {
  @api view;
  @api audience = "admin";
  @api allowRealMap = false;

  get isAdmin() {
    return this.audience !== "customer";
  }

  get hasView() {
    return this.view && this.view.found;
  }

  get hasGeofence() {
    return this.hasView && this.view.hasCoordinates;
  }

  get showDistanceRule() {
    return this.isAdmin && this.hasView && !this.view.hasCoordinates;
  }

  get canShowRealMap() {
    return (
      this.isAdmin || this.allowRealMap === true || this.allowRealMap === "true"
    );
  }

  get showMap() {
    return this.canShowRealMap && this.hasGeofence;
  }

  // The result of the check, in its colour, above the map (the map itself has no colours)
  get resultBandClass() {
    return `result-band ${this.resultClass}`;
  }

  get resultBandText() {
    return `${this.resultLabel} · the driver marked the order delivered ${formatDistance(
      this.view.driverToCenterMeters
    )} from the centre of the trip`;
  }

  get showAdminDetails() {
    return this.isAdmin && this.hasGeofence;
  }

  get isMatch() {
    return this.view && this.view.gpsResult === "MATCH";
  }

  get resultClass() {
    return this.isMatch ? "match" : "mismatch";
  }

  get orderLine() {
    const total =
      this.view.orderTotal === null || this.view.orderTotal === undefined
        ? "—"
        : new Intl.NumberFormat("en-US", {
            style: "currency",
            currency: this.view.currencyIsoCode || "USD"
          }).format(this.view.orderTotal);
    return `Order ${this.view.orderId} · ${total}`;
  }

  get resultLabel() {
    const word = {
      MATCH: "GPS match",
      MISMATCH: "GPS mismatch",
      AMBIGUOUS: "GPS ambiguous"
    }[this.view.gpsResult];
    return word || "GPS unknown";
  }

  // The distance the decision uses: the driver to the center, against the radius (D-097)
  get pillText() {
    return `${this.resultLabel} · ${formatDistance(this.view.driverToCenterMeters)}`;
  }

  get mapMarkers() {
    const v = this.view;
    const at = (p) => ({ Latitude: p.latitude, Longitude: p.longitude });
    return [
      {
        location: at(v.center),
        type: "Circle",
        radius: v.radiusMeters,
        strokeColor: "#EE6A2C",
        strokeOpacity: 0.9,
        strokeWeight: 2,
        fillColor: "#EE6A2C",
        fillOpacity: 0.12,
        title: "Trip geofence"
      },
      { location: at(v.restaurant), title: "Restaurant" },
      { location: at(v.dropoff), title: "Drop-off" },
      {
        location: at(v.driver),
        title: "Driver when marked delivered",
        description: this.pillText
      }
    ];
  }

  get facts() {
    const v = this.view;
    return [
      { key: "trip", label: "Trip", value: formatDistance(v.tripMeters) },
      {
        key: "radius",
        label: "Geofence radius",
        value: `${formatDistance(v.radiusMeters)} (half the trip + ${formatDistance(v.toleranceMeters)})`
      },
      {
        key: "center",
        label: "Driver to center",
        value: formatDistance(v.driverToCenterMeters)
      },
      {
        key: "dropoff",
        label: "Driver to drop-off",
        value: formatDistance(v.driverToDropoffMeters)
      },
      { key: "scenario", label: "Demo scenario", value: v.scenario || "—" }
    ];
  }

  get distanceRuleText() {
    if (
      this.view.driverDistanceMeters === null ||
      this.view.driverDistanceMeters === undefined
    ) {
      return "No driver location on this row (a timing demo): GPS is unknown, so a person decides the driver pay.";
    }
    return `No locations on this row: the distance rule decides (${formatDistance(
      this.view.driverDistanceMeters
    )} from the drop-off → ${this.resultLabel}).`;
  }
}
