public with sharing class CARES_Refund_IssueResolution {
    public class Request {
        @InvocableVariable(
            label='Contact ID'
            description='Customer Contact ID from the messaging channel, never from the chat'
            required=true
        )
        public String contactId;
        @InvocableVariable(
            label='Order ID'
            description='Internal order identifier'
            required=true
        )
        public String orderId;
        @InvocableVariable(
            label='Resolution Type'
            description='Refund or Store_Credit'
            required=true
        )
        public String resolutionType;
        @InvocableVariable(
            label='Refund Amount'
            description='Refund amount from the calculated offer'
            required=true
        )
        public Decimal refundAmount;
        @InvocableVariable(
            label='Credit Amount'
            description='Store credit amount from the calculated offer'
            required=true
        )
        public Decimal creditAmount;
    }
    public class Result {
        @InvocableVariable(
            label='Success'
            description='Whether the resolution was issued'
        )
        public Boolean success;
        @InvocableVariable(
            label='Reference Number'
            description='Resolution reference to give the customer'
        )
        public String referenceNumber;
        @InvocableVariable(
            label='Message'
            description='Customer-facing confirmation of what was issued'
        )
        public String message;
    }
    @InvocableMethod(
        label='CARES Refund Issue Resolution'
        description='Issues the confirmed refund (to the original payment method) or store credit for an order'
    )
    public static List<Result> execute(List<Request> requests) {
        // Stub — report success without writing any records
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.success = true;
            r.referenceNumber = 'CARES-STUB-0001';
            r.message = req.resolutionType == 'Store_Credit'
                ? 'Store credit of $' + req.creditAmount.setScale(2) + ' has been added to your account.'
                : 'Refund of $' + req.refundAmount.setScale(2) + ' to your original payment method in 3-5 business days.';
            results.add(r);
        }
        return results;
    }
}
