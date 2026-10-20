public with sharing class CARES_Refund_LogOrderIssue {
    private static final Set<String> ITEM_TYPES = new Set<String>{ 'Wrong_Missing_Items', 'Quality_Issue' };
    private static final Set<String> DELIVERY_TYPES = new Set<String>{ 'Stolen', 'Delayed' };

    public class Request {
        @InvocableVariable(
            label='Order ID'
            description='Delivery platform order id, the same id Stolen & Delayed Orders uses'
            required=true
        )
        public String orderId;
        @InvocableVariable(
            label='Issue Type'
            description='Wrong_Missing_Items or Quality_Issue; Stolen or Delayed only on the Stolen & Delayed standard path'
            required=true
        )
        public String issueType;
        @InvocableVariable(
            label='Issue Description'
            description='The customer description of what went wrong'
            required=true
        )
        public String issueDescription;
        @InvocableVariable(
            label='Affected Items'
            description='Names of the order items that were wrong, missing, or bad quality; blank for Stolen or Delayed'
        )
        public String affectedItems;
        @InvocableVariable(
            label='Delivery Path'
            description='STANDARD when the order came from the Stolen & Delayed standard path, otherwise blank'
        )
        public String deliveryPath;
    }
    public class Result {
        @InvocableVariable(
            label='Order Outcome'
            description='Validated outcome category; blank when not accepted'
        )
        public String orderOutcome;
        @InvocableVariable(
            label='Affected Value'
            description='Total price of the matched affected items'
        )
        public Decimal affectedValue;
        @InvocableVariable(
            label='Accepted'
            description='Whether the issue type and affected items were accepted'
        )
        public Boolean accepted;
    }
    @InvocableMethod(
        label='CARES Refund Log Order Issue'
        description='Records a customer-reported wrong/missing item or quality issue and values the affected items'
    )
    public static List<Result> execute(List<Request> requests) {
        // Stub — validate the outcome category, return a fixed affected value for item issues
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            Boolean deliveryIssue = req.deliveryPath == 'STANDARD' && DELIVERY_TYPES.contains(req.issueType);
            Boolean itemIssue = ITEM_TYPES.contains(req.issueType) && String.isNotBlank(req.affectedItems);
            r.accepted = deliveryIssue || itemIssue;
            r.orderOutcome = r.accepted ? req.issueType : '';
            r.affectedValue = itemIssue ? 12.00 : 0;
            results.add(r);
        }
        return results;
    }
}
