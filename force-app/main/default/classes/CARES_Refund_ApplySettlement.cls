public with sharing class CARES_Refund_ApplySettlement {
    public class Request {
        @InvocableVariable(
            label='Order ID'
            description='Order the customer resolution was issued for'
            required=true
        )
        public String orderId;
        @InvocableVariable(
            label='Driver Compensation'
            description='PAY_IN_FULL, WITHHOLD_DELIVERY_PAY or HOLD_FOR_REVIEW, from Stolen & Delayed Orders'
        )
        public String driverCompensation;
        @InvocableVariable(
            label='Restaurant Reimbursement'
            description='REIMBURSE or NO_CHANGE, from Stolen & Delayed Orders'
        )
        public String restaurantReimbursement;
        @InvocableVariable(
            label='Loss Absorption'
            description='True when Pronto absorbs the loss: pay the driver and reimburse the restaurant'
        )
        public Boolean lossAbsorption;
    }
    public class Result {
        @InvocableVariable(
            label='Success'
            description='Whether the driver and restaurant settlement was applied'
        )
        public Boolean success;
    }
    @InvocableMethod(
        label='CARES Refund Apply Settlement'
        description='Applies the driver pay and restaurant reimbursement recommendations after a customer resolution is issued'
    )
    public static List<Result> execute(List<Request> requests) {
        // Stub — report success without calling any payout endpoint
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.success = true;
            results.add(r);
        }
        return results;
    }
}
