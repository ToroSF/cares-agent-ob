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
            description='Delivery platform order id, the same id Stolen & Delayed Orders uses'
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
        @InvocableVariable(
            label='Approved Full Amount'
            description='Full order value already approved by Stolen & Delayed Orders; 0 when not approved'
        )
        public Decimal approvedFullAmount;
        @InvocableVariable(
            label='Order Total Cap'
            description='Order total the refund must not exceed; 0 when unknown'
        )
        public Decimal orderTotalCap;
        @InvocableVariable(
            label='Order Currency'
            description='ISO currency code of the order from Stolen & Delayed Orders; blank when unknown'
        )
        public String orderCurrency;
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
        // Stub — fixed 15.00 offer (or the approved full amount), capped at the order total, 20% credit bonus, order currency or USD
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            Decimal refund = req.approvedFullAmount != null && req.approvedFullAmount > 0 ? req.approvedFullAmount : 15.00;
            if (req.orderTotalCap != null && req.orderTotalCap > 0 && refund > req.orderTotalCap) {
                refund = req.orderTotalCap;
            }
            r.eligible = true;
            r.ineligibleReason = '';
            r.refundAmount = refund.setScale(2);
            r.creditAmount = (refund * 1.20).setScale(2);
            r.currencyCode = String.isBlank(req.orderCurrency) ? 'USD' : req.orderCurrency;
            r.tierName = 'Gold';
            results.add(r);
        }
        return results;
    }
}
