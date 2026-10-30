import { LightningElement, api } from "lwc";
import { toView } from "c/caresGeofenceRenderer";

// Stolen & Delayed: the delivery map card in the agent chat (Custom Lightning Type c__caresDeliveryMapView,
// D-106). Replaces caresGeofenceRenderer, whose type points at an inner Apex class the chat never draws (G-137).
// Same conversion, same card; it calls no Apex.
export default class CaresDeliveryMapRenderer extends LightningElement {
  _value;

  @api
  get value() {
    return this._value;
  }

  set value(val) {
    this._value = val;
  }

  get view() {
    return toView(this._value);
  }
}
