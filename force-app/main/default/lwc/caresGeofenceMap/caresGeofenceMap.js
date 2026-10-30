import { LightningElement, api, wire } from "lwc";
import getGeofence from "@salesforce/apex/CARES_GeofenceMapController.getGeofence";
import getGeofenceByOrder from "@salesforce/apex/CARES_GeofenceMapController.getGeofenceByOrder";

// Stolen & Delayed: the trip geofence of one order (D-097), drawn in Pronto's delivery-card style (D-105).
// Every number comes from CARES_GeofenceMapController, which uses the policy's own math; this file only
// places the points on screen.

const WIDTH = 640;
const HEIGHT = 380;
const PAD = 56;
// Meters per degree, close enough for a few kilometers around the center
const M_PER_DEG_LAT = 110574;
const M_PER_DEG_LNG = 111320;
const GRID_COLUMNS = [60, 170, 290, 410, 530];
const GRID_ROWS = [50, 120, 270, 330];

export function formatDistance(meters) {
  if (meters === null || meters === undefined) {
    return "—";
  }
  return meters < 1000
    ? `${Math.round(meters)} m`
    : `${(meters / 1000).toFixed(1)} km`;
}

// Local equirectangular projection around the center, scaled to fit the circle and the three points
export function project(view) {
  const lat0 = view.center.latitude;
  const lng0 = view.center.longitude;
  const cos = Math.cos((lat0 * Math.PI) / 180);
  const toMeters = (p) => ({
    x: (p.longitude - lng0) * cos * M_PER_DEG_LNG,
    y: (p.latitude - lat0) * M_PER_DEG_LAT
  });
  const pts = {
    restaurant: toMeters(view.restaurant),
    dropoff: toMeters(view.dropoff),
    driver: toMeters(view.driver)
  };
  const r = view.radiusMeters;
  const xs = [-r, r, pts.restaurant.x, pts.dropoff.x, pts.driver.x];
  const ys = [-r, r, pts.restaurant.y, pts.dropoff.y, pts.driver.y];
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  const scale = Math.min(
    (WIDTH - 2 * PAD) / (maxX - minX || 1),
    (HEIGHT - 2 * PAD) / (maxY - minY || 1)
  );
  const offsetX = (WIDTH - (maxX - minX) * scale) / 2;
  const offsetY = (HEIGHT - (maxY - minY) * scale) / 2;
  // North is up: screen y grows downwards
  const toScreen = (p) => ({
    x: offsetX + (p.x - minX) * scale,
    y: offsetY + (maxY - p.y) * scale
  });
  return {
    center: toScreen({ x: 0, y: 0 }),
    radius: r * scale,
    restaurant: toScreen(pts.restaurant),
    dropoff: toScreen(pts.dropoff),
    driver: toScreen(pts.driver)
  };
}

// Splits a straight segment where it crosses the circle, so the part outside can take the result color
export function splitByCircle(a, b, center, radius) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const fx = a.x - center.x;
  const fy = a.y - center.y;
  const qa = dx * dx + dy * dy;
  const qb = 2 * (fx * dx + fy * dy);
  const qc = fx * fx + fy * fy - radius * radius;
  const cuts = [0, 1];
  const disc = qb * qb - 4 * qa * qc;
  if (qa > 0 && disc > 0) {
    [(-qb - Math.sqrt(disc)) / (2 * qa), (-qb + Math.sqrt(disc)) / (2 * qa)]
      .filter((t) => t > 0 && t < 1)
      .forEach((t) => cuts.push(t));
  }
  cuts.sort((x, y) => x - y);
  const pieces = [];
  for (let i = 0; i < cuts.length - 1; i++) {
    const t0 = cuts[i];
    const t1 = cuts[i + 1];
    if (t1 - t0 < 1e-6) {
      continue;
    }
    const mid = {
      x: a.x + dx * ((t0 + t1) / 2),
      y: a.y + dy * ((t0 + t1) / 2)
    };
    const inside = Math.hypot(mid.x - center.x, mid.y - center.y) <= radius;
    pieces.push({
      x1: a.x + dx * t0,
      y1: a.y + dy * t0,
      x2: a.x + dx * t1,
      y2: a.y + dy * t1,
      inside
    });
  }
  return pieces;
}

export default class CaresGeofenceMap extends LightningElement {
  @api recordId;
  view;
  error;
  loading = false;
  showRealMap = false;
  orderInput = "";

  @wire(getGeofence, { telemetryId: "$recordId" })
  wiredGeofence({ data, error }) {
    if (data) {
      this.view = data;
      this.error = undefined;
    } else if (error) {
      this.view = undefined;
      this.error = error;
    }
  }

  // App and Home pages have no record: look the order up by its number
  get needsOrderInput() {
    return !this.recordId;
  }

  handleOrderInput(event) {
    this.orderInput = event.target.value;
  }

  async handleSearch() {
    this.loading = true;
    try {
      this.view = await getGeofenceByOrder({ orderId: this.orderInput });
      this.error = undefined;
    } catch (e) {
      this.view = undefined;
      this.error = e;
    } finally {
      this.loading = false;
    }
  }

  toggleRealMap() {
    this.showRealMap = !this.showRealMap;
  }

  get notFound() {
    return this.view && !this.view.found;
  }

  get hasView() {
    return this.view && this.view.found;
  }

  get hasGeofence() {
    return this.hasView && this.view.hasCoordinates;
  }

  get showDistanceRule() {
    return this.hasView && !this.view.hasCoordinates;
  }

  get showSchematic() {
    return this.hasGeofence && !this.showRealMap;
  }

  get showMap() {
    return this.hasGeofence && this.showRealMap;
  }

  get toggleLabel() {
    return this.showRealMap ? "Show delivery card" : "Show on real map";
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

  get shape() {
    return project(this.view);
  }

  get viewBox() {
    return `0 0 ${WIDTH} ${HEIGHT}`;
  }

  get gridLines() {
    const vertical = GRID_COLUMNS.map((x) => ({
      key: `v${x}`,
      x1: x,
      y1: 10,
      x2: x,
      y2: HEIGHT - 10
    }));
    const horizontal = GRID_ROWS.map((y) => ({
      key: `h${y}`,
      x1: 0,
      y1: y,
      x2: WIDTH,
      y2: y
    }));
    return [...vertical, ...horizontal];
  }

  // An L-shaped route from the drop-off to where the driver marked the order delivered, like a street path
  get routeSegments() {
    const { dropoff, driver, center, radius } = this.shape;
    const corner = { x: dropoff.x, y: driver.y };
    const pieces = [
      ...splitByCircle(dropoff, corner, center, radius),
      ...splitByCircle(corner, driver, center, radius)
    ];
    return pieces.map((p, i) => ({
      ...p,
      key: `r${i}`,
      className: p.inside
        ? "route route-inside"
        : `route route-outside ${this.resultClass}`
    }));
  }

  get driverDotClass() {
    return `driver-dot ${this.resultClass}`;
  }

  get pill() {
    const { driver } = this.shape;
    const width = this.pillText.length * 9.5 + 32;
    const height = 40;
    // Above the driver, kept inside the card
    const x = Math.min(Math.max(driver.x - width / 2, 8), WIDTH - width - 8);
    const y = Math.max(driver.y - height - 26, 8);
    return {
      x,
      y,
      width,
      height,
      textX: x + width / 2,
      textY: y + height / 2 + 6
    };
  }

  get pillTextClass() {
    return `pill-text ${this.resultClass}`;
  }

  get restaurantLabelY() {
    return this.shape.restaurant.y + 30;
  }

  get dropoffLabelY() {
    return this.shape.dropoff.y + 30;
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

  get svgDescription() {
    return `${this.resultLabel}. The driver marked the order delivered ${formatDistance(
      this.view.driverToDropoffMeters
    )} from the drop-off, ${formatDistance(this.view.driverToCenterMeters)} from the center of a ${formatDistance(
      this.view.radiusMeters
    )} geofence. The street grid is decorative.`;
  }
}
