/**
 * Unit tests for the five Refund invocable actions (stubs, D-020).
 * They pin the rules the agent relies on (D-019, D-030, D-036) and the fixed
 * stub values the baseline batch assumes in Tier L (personas.md). When a stub
 * is replaced by real logic, update the stub-value tests in the same PR.
 */
@IsTest
private class CARES_Refund_ActionsTest {
    private static final String CONTACT_ID = '003000000000001';
    private static final String ORDER_ID = 'STUB-ORDER-1042';

    private static CARES_Refund_LogOrderIssue.Result logIssue(String issueType, String affectedItems, String deliveryPath) {
        CARES_Refund_LogOrderIssue.Request req = new CARES_Refund_LogOrderIssue.Request();
        req.orderId = ORDER_ID;
        req.issueType = issueType;
        req.issueDescription = 'Customer description';
        req.affectedItems = affectedItems;
        req.deliveryPath = deliveryPath;
        return CARES_Refund_LogOrderIssue.execute(new List<CARES_Refund_LogOrderIssue.Request>{ req })[0];
    }

    private static CARES_Refund_CalculateOffer.Result offer(Decimal approvedFullAmount, Decimal orderTotalCap, String orderCurrency) {
        CARES_Refund_CalculateOffer.Request req = new CARES_Refund_CalculateOffer.Request();
        req.contactId = CONTACT_ID;
        req.orderId = ORDER_ID;
        req.orderOutcome = 'Wrong_Missing_Items';
        req.riskStatus = 'UNKNOWN';
        req.affectedValue = 12.00;
        req.approvedFullAmount = approvedFullAmount;
        req.orderTotalCap = orderTotalCap;
        req.orderCurrency = orderCurrency;
        return CARES_Refund_CalculateOffer.execute(new List<CARES_Refund_CalculateOffer.Request>{ req })[0];
    }

    // find_order

    @IsTest
    static void findOrderReturnsTheStubOrder() {
        CARES_Refund_FindOrder.Request req = new CARES_Refund_FindOrder.Request();
        req.contactId = CONTACT_ID;
        req.orderNumber = '';
        CARES_Refund_FindOrder.Result r = CARES_Refund_FindOrder.execute(new List<CARES_Refund_FindOrder.Request>{ req })[0];
        System.assertEquals(true, r.found);
        System.assertEquals(ORDER_ID, r.orderId);
        System.assert(r.lineItems.contains('Large Fries $5.50'), 'Line items are what B-RF-02 names');
    }

    // log_order_issue: path rules (D-030)

    @IsTest
    static void itemIssuesNeedAffectedItems() {
        CARES_Refund_LogOrderIssue.Result wrong = logIssue('Wrong_Missing_Items', 'Cheeseburger', '');
        System.assertEquals(true, wrong.accepted);
        System.assertEquals('Wrong_Missing_Items', wrong.orderOutcome);
        System.assertEquals(12.00, wrong.affectedValue);

        CARES_Refund_LogOrderIssue.Result quality = logIssue('Quality_Issue', 'Large Fries', '');
        System.assertEquals('Quality_Issue', quality.orderOutcome);

        CARES_Refund_LogOrderIssue.Result noItems = logIssue('Wrong_Missing_Items', '', '');
        System.assertEquals(false, noItems.accepted);
        System.assertEquals('', noItems.orderOutcome, 'A rejected issue must not set an outcome');
        System.assertEquals(0, noItems.affectedValue);
    }

    @IsTest
    static void stolenAndDelayedAreRejectedOnTheDirectPath() {
        for (String issueType : new List<String>{ 'Stolen', 'Delayed' }) {
            CARES_Refund_LogOrderIssue.Result r = logIssue(issueType, '', '');
            System.assertEquals(false, r.accepted, issueType + ' must be rejected without the STANDARD path');
            System.assertEquals('', r.orderOutcome);
        }
    }

    @IsTest
    static void stolenAndDelayedAreAcceptedOnTheStandardPath() {
        for (String issueType : new List<String>{ 'Stolen', 'Delayed' }) {
            CARES_Refund_LogOrderIssue.Result r = logIssue(issueType, '', 'STANDARD');
            System.assertEquals(true, r.accepted);
            System.assertEquals(issueType, r.orderOutcome);
            System.assertEquals(0, r.affectedValue, 'Whole-order outcomes carry no item value');
        }
    }

    @IsTest
    static void unknownIssueTypesAreRejected() {
        System.assertEquals(false, logIssue('Store_Credit', 'Cheeseburger', '').accepted);
        System.assertEquals(false, logIssue('stolen', '', 'STANDARD').accepted, 'Values are case-sensitive literals');
        System.assertEquals(false, logIssue('', 'Cheeseburger', '').accepted);
    }

    @IsTest
    static void stubAcceptsAnyNamedItem() {
        // Known stub limit (G-023): items are not matched against the order, so B-RF-08 ("sushi") is accepted in Tier L
        System.assertEquals(true, logIssue('Wrong_Missing_Items', 'Sushi', '').accepted);
    }

    // calculate_refund_offer (D-021, D-029, D-036)

    @IsTest
    static void defaultOfferIsFifteenWithTwentyPercentCredit() {
        CARES_Refund_CalculateOffer.Result r = offer(0, 0, '');
        System.assertEquals(true, r.eligible);
        System.assertEquals(15.00, r.refundAmount);
        System.assertEquals(18.00, r.creditAmount);
        System.assertEquals('USD', r.currencyCode, 'Blank order currency falls back to USD');
    }

    @IsTest
    static void approvedFullAmountReplacesTheDefault() {
        CARES_Refund_CalculateOffer.Result r = offer(25.00, 25.00, 'EUR');
        System.assertEquals(25.00, r.refundAmount);
        System.assertEquals(30.00, r.creditAmount, 'READY path credit is total + bonus (D-029)');
        System.assertEquals('EUR', r.currencyCode, 'Order currency is echoed (D-036)');
    }

    @IsTest
    static void refundNeverExceedsTheOrderTotalCap() {
        System.assertEquals(10.00, offer(0, 10.00, '').refundAmount);
        System.assertEquals(12.00, offer(0, 10.00, '').creditAmount);
        System.assertEquals(20.00, offer(40.00, 20.00, '').refundAmount, 'Cap also applies to an approved amount');
    }

    @IsTest
    static void nullAmountsAreTreatedAsNotSet() {
        CARES_Refund_CalculateOffer.Result r = offer(null, null, null);
        System.assertEquals(15.00, r.refundAmount);
        System.assertEquals('USD', r.currencyCode);
    }

    @IsTest
    static void offerHandlesABatchInOrder() {
        CARES_Refund_CalculateOffer.Request a = new CARES_Refund_CalculateOffer.Request();
        a.orderTotalCap = 5.00;
        CARES_Refund_CalculateOffer.Request b = new CARES_Refund_CalculateOffer.Request();
        b.approvedFullAmount = 30.00;
        List<CARES_Refund_CalculateOffer.Result> rs = CARES_Refund_CalculateOffer.execute(
            new List<CARES_Refund_CalculateOffer.Request>{ a, b }
        );
        System.assertEquals(2, rs.size());
        System.assertEquals(5.00, rs[0].refundAmount);
        System.assertEquals(30.00, rs[1].refundAmount);
    }

    // issue_resolution

    @IsTest
    static void issueReportsSuccessWithTheChosenType() {
        CARES_Refund_IssueResolution.Request req = new CARES_Refund_IssueResolution.Request();
        req.contactId = CONTACT_ID;
        req.orderId = ORDER_ID;
        req.resolutionType = 'Store_Credit';
        req.refundAmount = 15.00;
        req.creditAmount = 18.00;
        CARES_Refund_IssueResolution.Result credit = CARES_Refund_IssueResolution.execute(new List<CARES_Refund_IssueResolution.Request>{ req })[0];
        System.assertEquals(true, credit.success);
        System.assert(String.isNotBlank(credit.referenceNumber));
        System.assert(credit.message.contains('18.00'), 'Credit message shows the credit amount');

        req.resolutionType = 'Refund';
        CARES_Refund_IssueResolution.Result refund = CARES_Refund_IssueResolution.execute(new List<CARES_Refund_IssueResolution.Request>{ req })[0];
        System.assert(refund.message.contains('15.00'), 'Refund message shows the refund amount');
        System.assert(refund.message.contains('original payment method'), 'Refunds go to the original payment method only');
    }

    // apply_settlement

    @IsTest
    static void settlementStubReportsSuccess() {
        CARES_Refund_ApplySettlement.Request req = new CARES_Refund_ApplySettlement.Request();
        req.orderId = ORDER_ID;
        req.driverCompensation = 'PAY_IN_FULL';
        req.restaurantReimbursement = 'REIMBURSE';
        req.lossAbsorption = true;
        System.assertEquals(true, CARES_Refund_ApplySettlement.execute(new List<CARES_Refund_ApplySettlement.Request>{ req })[0].success);
    }
}
