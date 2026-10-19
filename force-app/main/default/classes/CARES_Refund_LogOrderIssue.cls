public with sharing class CARES_Refund_LogOrderIssue {
    private static final Set<String> ALLOWED_TYPES = new Set<String>{ 'Wrong_Missing_Items', 'Quality_Issue' };

    public class Request {
        @InvocableVariable(
            label='Order ID'
            description='Internal order identifier'
            required=true
        )
        public String orderId;
        @InvocableVariable(
            label='Issue Type'
            description='Wrong_Missing_Items or Quality_Issue'
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
            description='Names of the order items that were wrong, missing, or bad quality'
            required=true
        )
        public String affectedItems;
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
        // Stub — validate the outcome category, return a fixed affected value
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.accepted = ALLOWED_TYPES.contains(req.issueType) && String.isNotBlank(req.affectedItems);
            r.orderOutcome = r.accepted ? req.issueType : '';
            r.affectedValue = r.accepted ? 12.00 : 0;
            results.add(r);
        }
        return results;
    }
}
