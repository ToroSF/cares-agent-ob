import { LightningElement, api, wire } from "lwc";
import getGeofence from "@salesforce/apex/CARES_GeofenceMapController.getGeofence";
import getGeofenceByOrder from "@salesforce/apex/CARES_GeofenceMapController.getGeofenceByOrder";

// Stolen & Delayed: the geofence view on a telemetry record in CARES Admin (D-105). Loads the data from
// CARES_GeofenceMapController, which uses the policy's own math; caresGeofenceCard draws it.
export default class CaresGeofenceMap extends LightningElement {
  @api recordId;
  view;
  error;
  loading = false;
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

  get notFound() {
    return this.view && !this.view.found;
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
}
