public with sharing class CARES_Refund_FindOrder {
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
            label='Order ID'
            description='Pronto order id (PR-...), the platform id the other actions use (D-038)'
        )
        public String orderId;
        @InvocableVariable(
            label='Order Summary'
            description='Order number, order date, restaurant and total'
        )
        public String orderSummary;
        @InvocableVariable(
            label='Line Items'
            description='Item names and prices on the order'
        )
        public String lineItems;
        @InvocableVariable(
            label='Order Total'
            description='Order total; the refund must not exceed it'
        )
        public Decimal orderTotal;
        @InvocableVariable(
            label='Found'
            description='Whether a matching order was found'
        )
        public Boolean found;
        @InvocableVariable(
            label='Not Found Reason'
            description='NOT_FOUND, NOT_DELIVERED, NOT_A_PRONTO_ORDER_NUMBER, NO_ACCOUNT_LINK or DATA_UNAVAILABLE; blank when found'
        )
        public String notFoundReason;
    }
    @InvocableMethod(
        label='CARES Refund Find Order'
        description='Finds a delivered order of this customer by order number, or their most recent delivered order'
    )
    public static List<Result> execute(List<Request> requests) {
        // Real orders from Data Cloud (D-071), only the customer's own and only delivered ones:
        // a missing item or a quality problem can only be on an order that arrived
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            CARES_OrderData.Lookup lookup = CARES_OrderData.find(req.contactId, req.orderNumber, true);
            Result r = new Result();
            r.found = lookup.found;
            r.notFoundReason = lookup.reason;
            r.orderId = lookup.found ? lookup.order.orderId : '';
            r.orderSummary = lookup.found ? CARES_OrderData.summary(lookup.order) : '';
            r.lineItems = lookup.found ? CARES_OrderData.lineItems(lookup.order) : '';
            r.orderTotal = lookup.found && lookup.order.total != null ? lookup.order.total.setScale(2) : 0;
            results.add(r);
        }
        return results;
    }
}
