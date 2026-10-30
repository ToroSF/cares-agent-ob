import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import view from "@salesforce/apex/CARES_DeliveryMapLink.view";
import { toView } from "c/caresGeofenceRenderer";

// Stolen & Delayed: the delivery map page of the Experience site (/delivery-map?t=..., D-107). The agent sends
// the signed link for an approved claim; Apex checks the signature and the expiry before it returns the card.
export default class CaresDeliveryMapPage extends LightningElement {
  card;
  loading = true;
  invalid = false;
  token;
  started = false;
  // The customer can switch to Google Maps here, as in CARES Admin (G-136: mock data only today)
  allowRealMap = true;

  @wire(CurrentPageReference)
  pageRef(ref) {
    const t = (ref && ref.state && ref.state.t) || null;
    if (!this.started || t !== this.token) {
      this.started = true;
      this.token = t;
      this.load();
    }
  }

  async load() {
    this.loading = true;
    this.invalid = false;
    this.card = undefined;
    if (!this.token) {
      this.invalid = true;
      this.loading = false;
      return;
    }
    try {
      const data = await view({ token: this.token });
      this.card = toView(data) || undefined;
      this.invalid = !this.card;
    } catch {
      this.invalid = true;
    } finally {
      this.loading = false;
    }
  }
}
