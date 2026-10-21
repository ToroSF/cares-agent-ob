public with sharing class CARES_Order_GetStatus {
    public class Request {
        @InvocableVariable(
            label='Contact ID'
            description='Customer Contact ID from the messaging channel, never from the chat'
            required=true
        )
        public String contactId;
        @InvocableVariable(
            label='Order Number'
            description='Order number given by the customer; blank means most recent order'
        )
        public String orderNumber;
    }
    public class Result {
        @InvocableVariable(
            label='Found'
            description='Whether a matching order of this customer was found'
        )
        public Boolean found;
        @InvocableVariable(
            label='Order ID'
            description='Pronto order id (PR-...)'
        )
        public String orderId;
        @InvocableVariable(
            label='Status'
            description='Status in the Delivery FAQ words: Accepted, Picked Up, Delivered or Canceled'
        )
        public String status;
        @InvocableVariable(
            label='Status Summary'
            description='Customer-facing sentence with the order, restaurant, status and estimated or actual delivery time'
        )
        public String statusSummary;
        @InvocableVariable(
            label='Not Found Reason'
            description='NOT_FOUND, NOT_A_PRONTO_ORDER_NUMBER, NO_ACCOUNT_LINK or DATA_UNAVAILABLE; blank when found'
        )
        public String notFoundReason;
    }
    @InvocableMethod(
        label='CARES Order Get Status'
        description='Read-only: returns the real status and estimated delivery time of one of this customer\'s orders'
    )
    public static List<Result> execute(List<Request> requests) {
        // Read-only (D-075): status and times come from Data Cloud, only for the customer's own orders
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            CARES_OrderData.Lookup lookup = CARES_OrderData.find(req.contactId, req.orderNumber, false);
            Result r = new Result();
            r.found = lookup.found;
            r.notFoundReason = lookup.reason;
            r.orderId = lookup.found ? lookup.order.orderId : '';
            r.status = lookup.found ? CARES_OrderData.faqStatus(lookup.order.status) : '';
            r.statusSummary = lookup.found ? statusSummary(lookup.order) : '';
            results.add(r);
        }
        return results;
    }

    private static String statusSummary(CARES_OrderData.OrderRow o) {
        String order = 'Order ' + o.orderId + (String.isBlank(o.restaurant) ? '' : ' from ' + o.restaurant);
        String status = CARES_OrderData.faqStatus(o.status);
        // Times are stored in UTC and the customer's time zone is not known, so the zone is named
        switch on status {
            when 'Delivered' {
                return order + ' was delivered' + timeText(' on ', o.deliveredAt) + '.';
            }
            when 'Canceled' {
                return order + ' was canceled.';
            }
            when 'Picked Up' {
                return order + ' has been picked up by the driver and is on its way.' +
                    estimateText(o.estimatedDeliveryAt);
            }
            when 'Accepted' {
                return order + ' was accepted and the restaurant is preparing it.' + estimateText(o.estimatedDeliveryAt);
            }
            when else {
                return order + ' has the status ' + status + '.';
            }
        }
    }

    private static String estimateText(Datetime eta) {
        return eta == null ? '' : ' Estimated delivery: ' + eta.formatGmt('MMM d, yyyy h:mm a') + ' UTC. This is an estimate and can change.';
    }

    private static String timeText(String prefix, Datetime value) {
        return value == null ? '' : prefix + value.formatGmt('MMM d, yyyy h:mm a') + ' UTC';
    }
}
