import { LightningElement, api } from "lwc";

// Stolen & Delayed: the geofence card in the agent chat (Custom Lightning Type c__caresGeofenceView, D-106).
// The action CARES_StolenDelayedGeofenceCard sends a flat GeofenceView; this turns it into the shape
// caresGeofenceCard draws. It calls no Apex, so the chat's guest user needs no class access.

function point(lat, lng) {
  if (lat === null || lat === undefined || lng === null || lng === undefined) {
    return null;
  }
  return { latitude: lat, longitude: lng };
}

export function toView(value) {
  // The runtime may wrap the output in the action's output name
  const v = value && value.deliveryMap ? value.deliveryMap : value;
  if (!v || !v.hasCoordinates) {
    return null;
  }
  return {
    found: true,
    hasCoordinates: true,
    orderId: v.orderId,
    orderTotal: v.orderTotal,
    currencyIsoCode: v.currencyIsoCode,
    gpsResult: v.gpsResult,
    restaurant: point(v.restaurantLatitude, v.restaurantLongitude),
    dropoff: point(v.dropoffLatitude, v.dropoffLongitude),
    driver: point(v.driverLatitude, v.driverLongitude),
    center: point(v.centerLatitude, v.centerLongitude),
    radiusMeters: v.radiusMeters,
    tripMeters: v.tripMeters,
    toleranceMeters: v.toleranceMeters,
    driverToCenterMeters: v.driverToCenterMeters,
    driverToDropoffMeters: v.driverToDropoffMeters
  };
}

export default class CaresGeofenceRenderer extends LightningElement {
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
