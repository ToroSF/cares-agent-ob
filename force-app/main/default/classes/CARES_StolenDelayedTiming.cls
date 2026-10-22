/**
 * Stolen & Delayed Orders: is the order on time, late (minor or severe) or likely lost?
 * Pure function over the order's own times (D-100). Pronto's promise comes from the data:
 * On_Time_Delivery__c is true exactly when Delivery_Time_Min__c <= 40 (908 of 908
 * delivered orders on 2026-10-22).
 *
 *   Delivered:   minutes late = delivery minutes - promise
 *                <= 0 ON_TIME, <= minor max DELAYED_MINOR, else DELAYED_SEVERE
 *   In progress: expected = the estimate, or order time + promise; late = now - expected
 *                <= grace NOT_LATE_YET, <= minor max DELAYED_MINOR, <= lost limit DELAYED_SEVERE,
 *                else LIKELY_LOST; also LIKELY_LOST when picked up longer ago than the courier limit
 *
 * "Now" is the demo clock when the mock telemetry row sets Minutes_Since_Order__c (the data
 * is from 2024-2025, so real time makes every open order look a year late), else real time.
 */
public with sharing class CARES_StolenDelayedTiming {
  public static final String ON_TIME = 'ON_TIME';
  public static final String NOT_LATE_YET = 'NOT_LATE_YET';
  public static final String DELAYED_MINOR = 'DELAYED_MINOR';
  public static final String DELAYED_SEVERE = 'DELAYED_SEVERE';
  public static final String LIKELY_LOST = 'LIKELY_LOST';
  public static final String UNKNOWN = 'UNKNOWN';

  public static final String STAGE_KITCHEN = 'KITCHEN';
  public static final String STAGE_COURIER = 'COURIER';
  public static final String STAGE_DELIVERED = 'DELIVERED';

  public class Result {
    public String timing = UNKNOWN;
    public String stage = '';
    // Minutes past the expected time, never below 0
    public Integer minutesLate = 0;
    // Minutes until the expected time, for an order that is not late yet
    public Integer minutesUntilExpected = 0;
    public Datetime expectedAt;

    public Boolean isDelay() {
      return timing == DELAYED_MINOR || timing == DELAYED_SEVERE;
    }
  }

  public static Result classify(
    CARES_StolenDelayedTelemetry t,
    CARES_StolenDelayedPolicy.Settings s,
    Datetime realNow
  ) {
    Result r = new Result();
    if (t == null || t.orderCreatedAt == null) {
      return r;
    }
    Integer promise = s.promisedDeliveryMinutes.intValue();
    if (t.orderStatus == CARES_StolenDelayedOrderSource.DELIVERED) {
      r.stage = STAGE_DELIVERED;
      r.expectedAt = t.orderCreatedAt.addMinutes(promise);
      Decimal took = t.deliveryMinutes;
      if (took == null && t.deliveredAt != null) {
        took = minutesBetween(t.orderCreatedAt, t.deliveredAt);
      }
      if (took == null) {
        return r;
      }
      Integer late = took.intValue() - promise;
      r.minutesLate = Math.max(late, 0);
      r.timing = late <= 0 ? ON_TIME : (late <= s.minorDelayMaxMinutes ? DELAYED_MINOR : DELAYED_SEVERE);
      return r;
    }

    Datetime now = t.minutesSinceOrder != null
      ? t.orderCreatedAt.addMinutes(t.minutesSinceOrder)
      : realNow;
    r.stage = t.pickedUpAt != null ? STAGE_COURIER : STAGE_KITCHEN;
    r.expectedAt = t.estimatedDeliveryAt != null
      ? t.estimatedDeliveryAt
      : t.orderCreatedAt.addMinutes(promise);
    Integer late = minutesBetween(r.expectedAt, now).intValue();
    r.minutesLate = Math.max(late, 0);
    r.minutesUntilExpected = Math.max(-late, 0);

    // With the courier far longer than any trip in the data, the order is likely lost
    Boolean courierTooLong =
      t.pickedUpAt != null &&
      minutesBetween(t.pickedUpAt, now) > s.courierLostMinutes;
    if (courierTooLong || late > s.lostAfterMinutesLate) {
      r.timing = LIKELY_LOST;
    } else if (late <= s.delayGraceMinutes) {
      r.timing = NOT_LATE_YET;
    } else if (late <= s.minorDelayMaxMinutes) {
      r.timing = DELAYED_MINOR;
    } else {
      r.timing = DELAYED_SEVERE;
    }
    return r;
  }

  private static Decimal minutesBetween(Datetime fromTime, Datetime toTime) {
    return Decimal.valueOf(toTime.getTime() - fromTime.getTime()).divide(60000, 0, System.RoundingMode.FLOOR);
  }
}
