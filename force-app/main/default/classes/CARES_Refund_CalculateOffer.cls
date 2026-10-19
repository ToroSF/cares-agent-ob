public with sharing class CARES_Refund_CalculateOffer {
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
            label='Order Outcome'
            description='Stolen, Delayed, Wrong_Missing_Items or Quality_Issue'
            required=true
        )
        public String orderOutcome;
        @InvocableVariable(
            label='Risk Status'
            description='CLEAN, NOT_CLEAN or UNKNOWN from Risk Detection; only CLEAN unlocks the higher limit'
            required=true
        )
        public String riskStatus;
        @InvocableVariable(
            label='Affected Value'
            description='Value of affected items; ignored for Stolen and Delayed'
        )
        public Decimal affectedValue;
    }
    public class Result {
        @InvocableVariable(
            label='Eligible'
            description='Whether a refund or credit can be offered'
        )
        public Boolean eligible;
        @InvocableVariable(
            label='Ineligible Reason'
            description='Customer-safe explanation when not eligible'
        )
        public String ineligibleReason;
        @InvocableVariable(
            label='Refund Amount'
            description='Fixed refund amount to the original payment method'
        )
        public Decimal refundAmount;
        @InvocableVariable(
            label='Credit Amount'
            description='Store credit amount including the bonus'
        )
        public Decimal creditAmount;
        @InvocableVariable(
            label='Currency Code'
            description='ISO currency code for the amounts'
        )
        public String currencyCode;
        @InvocableVariable(
            label='Tier Name'
            description='Customer tier used for the calculation'
        )
        public String tierName;
    }
    @InvocableMethod(
        label='CARES Refund Calculate Offer'
        description='Calculates the refund and store credit offer from tier, order outcome and risk status'
    )
    public static List<Result> execute(List<Request> requests) {
        // Stub — return a fixed eligible offer
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.eligible = true;
            r.ineligibleReason = '';
            r.refundAmount = 15.00;
            r.creditAmount = 18.00;
            r.currencyCode = 'USD';
            r.tierName = 'Gold';
            results.add(r);
        }
        return results;
    }
}
