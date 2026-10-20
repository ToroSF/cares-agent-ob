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
            description='Delivery platform order id, the same id Stolen & Delayed Orders uses'
        )
        public String orderId;
        @InvocableVariable(
            label='Order Summary'
            description='Order number, delivery date and total'
        )
        public String orderSummary;
        @InvocableVariable(
            label='Line Items'
            description='Item names and prices on the order'
        )
        public String lineItems;
        @InvocableVariable(
            label='Found'
            description='Whether a matching order was found'
        )
        public Boolean found;
    }
    @InvocableMethod(
        label='CARES Refund Find Order'
        description='Finds a customer order by order number, or their most recent order'
    )
    public static List<Result> execute(List<Request> requests) {
        // Stub — return a fixed fake order
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.orderId = 'STUB-ORDER-1042';
            r.orderSummary = 'Order #1042, delivered Oct 18, $38.50';
            r.lineItems = 'Cheeseburger $14.00; Large Fries $5.50; Chicken Salad $12.00; Lemonade $7.00';
            r.found = true;
            results.add(r);
        }
        return results;
    }
}
