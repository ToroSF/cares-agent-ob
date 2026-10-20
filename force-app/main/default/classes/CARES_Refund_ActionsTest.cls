/**
 * Unit tests for the five Refund invocable actions. find_order and the order
 * VALUE inputs to calculate_refund_offer are still stubs (G-004: no real Order
 * object in this org). calculate_refund_offer's policy/limit lookup and
 * issue_resolution's audit-trail insert are real sObjects/SOQL/DML (D-024).
 * They pin the rules the agent relies on (D-019, D-030, D-036) and the explicit
 * stub line-item list the baseline batch assumes in Tier L (personas.md). When a
 * stub is replaced by real logic, update the stub-value tests in the same PR.
 *
 * STATIC REVIEW ONLY IN THIS PASS: these tests have not been run against an org
 * (no org available in this worktree). They are reviewed by eye for @IsTest
 * correctness, assertion shape and DML paths, not executed.
 */
@IsTest
private class CARES_Refund_ActionsTest {
    private static final String ORDER_ID = 'STUB-ORDER-1042';

    private static Account makeAccount() {
        Account a = new Account(Name = 'CARES Test Account');
        insert a;
        return a;
    }

    private static Contact makeContact(Account a) {
        Contact c = new Contact(LastName = 'CARES Test', AccountId = a.Id);
        insert c;
        return c;
    }

    private static Contact makeContact() {
        return makeContact(makeAccount());
    }

    private static CARES_Tier__c makeTier(String name, Decimal rank, Boolean active) {
        CARES_Tier__c t = new CARES_Tier__c(Name = name, Rank__c = rank, Active__c = active);
        insert t;
        return t;
    }

    private static CARES_Refund_Policy__c makePolicy(
        CARES_Tier__c tier,
        String outcome,
        Decimal maxRefund,
        Decimal cleanHistoryMaxRefund,
        Decimal bonusPct,
        Boolean active
    ) {
        CARES_Refund_Policy__c p = new CARES_Refund_Policy__c(
            Tier__c = tier.Id,
            Order_Outcome__c = outcome,
            Max_Refund__c = maxRefund,
            Clean_History_Max_Refund__c = cleanHistoryMaxRefund,
            Store_Credit_Bonus_Pct__c = bonusPct,
            Active__c = active
        );
        insert p;
        return p;
    }

    private static User refundUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            Alias = 'refndt',
            Email = 'refund.test@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Refund Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'refund.test.' + System.currentTimeMillis() + '@example.com'
        );
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'CARES_Refund_Access' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    private static CARES_Refund_LogOrderIssue.Result logIssue(String issueType, String affectedItems, String deliveryPath) {
        CARES_Refund_LogOrderIssue.Request req = new CARES_Refund_LogOrderIssue.Request();
        req.orderId = ORDER_ID;
        req.issueType = issueType;
        req.issueDescription = 'Customer description';
        req.affectedItems = affectedItems;
        req.deliveryPath = deliveryPath;
        return CARES_Refund_LogOrderIssue.execute(new List<CARES_Refund_LogOrderIssue.Request>{ req })[0];
    }

    private static CARES_Refund_CalculateOffer.Result offer(
        String contactId,
        String orderOutcome,
        String riskStatus,
        Decimal affectedValue,
        Decimal approvedFullAmount,
        Decimal orderTotalCap,
        String orderCurrency
    ) {
        CARES_Refund_CalculateOffer.Request req = new CARES_Refund_CalculateOffer.Request();
        req.contactId = contactId;
        req.orderId = ORDER_ID;
        req.orderOutcome = orderOutcome;
        req.riskStatus = riskStatus;
        req.affectedValue = affectedValue;
        req.approvedFullAmount = approvedFullAmount;
        req.orderTotalCap = orderTotalCap;
        req.orderCurrency = orderCurrency;
        return CARES_Refund_CalculateOffer.execute(new List<CARES_Refund_CalculateOffer.Request>{ req })[0];
    }

    private static CARES_Refund_IssueResolution.Result issue(
        String contactId,
        String orderId,
        String resolutionType,
        Decimal refundAmount,
        Decimal creditAmount
    ) {
        CARES_Refund_IssueResolution.Request req = new CARES_Refund_IssueResolution.Request();
        req.contactId = contactId;
        req.orderId = orderId;
        req.resolutionType = resolutionType;
        req.refundAmount = refundAmount;
        req.creditAmount = creditAmount;
        return CARES_Refund_IssueResolution.execute(new List<CARES_Refund_IssueResolution.Request>{ req })[0];
    }

    // find_order (stub, G-004)

    @IsTest
    static void findOrderReturnsTheStubOrderWithExplicitLineItems() {
        CARES_Refund_FindOrder.Request req = new CARES_Refund_FindOrder.Request();
        req.contactId = '003000000000001';
        req.orderNumber = '';
        CARES_Refund_FindOrder.Result r = CARES_Refund_FindOrder.execute(new List<CARES_Refund_FindOrder.Request>{ req })[0];
        System.assertEquals(true, r.found);
        System.assertEquals(ORDER_ID, r.orderId);
        System.assert(r.lineItems.contains('Large Fries $5.50'), 'Line items are what B-RF-02 names');
        System.assertEquals(4, CARES_Refund_FindOrder.STUB_LINE_ITEM_NAMES.size(), 'Explicit, defined line-item list (G-023)');
    }

    // log_order_issue: path rules (D-030) and item validation (G-023)

    @IsTest
    static void itemIssuesOnListedItemsAreAcceptedAtTheRealPrice() {
        CARES_Refund_LogOrderIssue.Result wrong = logIssue('Wrong_Missing_Items', 'Cheeseburger', '');
        System.assertEquals(true, wrong.accepted);
        System.assertEquals('Wrong_Missing_Items', wrong.orderOutcome);
        System.assertEquals(14.00, wrong.affectedValue, 'Priced from the explicit line-item list, not a flat 12.00');

        CARES_Refund_LogOrderIssue.Result quality = logIssue('Quality_Issue', 'Large Fries', '');
        System.assertEquals('Quality_Issue', quality.orderOutcome);
        System.assertEquals(5.50, quality.affectedValue);

        CARES_Refund_LogOrderIssue.Result noItems = logIssue('Wrong_Missing_Items', '', '');
        System.assertEquals(false, noItems.accepted);
        System.assertEquals('', noItems.orderOutcome, 'A rejected issue must not set an outcome');
        System.assertEquals(0, noItems.affectedValue);
    }

    @IsTest
    static void itemNotOnTheOrderIsRejectedNotValuedAtTwelve() {
        // Closes the known issue in G-023: an unlisted item must be rejected, not accepted at 12.00
        CARES_Refund_LogOrderIssue.Result r = logIssue('Wrong_Missing_Items', 'Sushi', '');
        System.assertEquals(false, r.accepted, 'Sushi is not on the stub order');
        System.assertEquals('', r.orderOutcome);
        System.assertEquals(0, r.affectedValue);
    }

    @IsTest
    static void multipleListedItemsSumTheirRealPrices() {
        CARES_Refund_LogOrderIssue.Result r = logIssue('Wrong_Missing_Items', 'Cheeseburger, Lemonade', '');
        System.assertEquals(true, r.accepted);
        System.assertEquals(21.00, r.affectedValue, '14.00 Cheeseburger + 7.00 Lemonade');
    }

    @IsTest
    static void oneUnlistedItemInAMultiItemListRejectsTheWholeRequest() {
        CARES_Refund_LogOrderIssue.Result r = logIssue('Wrong_Missing_Items', 'Cheeseburger, Sushi', '');
        System.assertEquals(false, r.accepted, 'A mix of real and fake items must not be partially accepted');
        System.assertEquals(0, r.affectedValue);
    }

    @IsTest
    static void itemNameMatchingIsCaseInsensitive() {
        CARES_Refund_LogOrderIssue.Result r = logIssue('Quality_Issue', 'cheeseburger', '');
        System.assertEquals(true, r.accepted);
        System.assertEquals(14.00, r.affectedValue);
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

    // calculate_refund_offer: real Tier + Policy lookup (D-024, D-025, D-029)

    @IsTest
    static void directPathUsesTheContactsTierPolicyAndStandardLimit() {
        CARES_Tier__c bronze = makeTier('Bronze', 1, true);
        CARES_Tier__c gold = makeTier('Gold', 3, true);
        makePolicy(bronze, 'Wrong_Missing_Items', 10.00, 20.00, 10, true);
        makePolicy(gold, 'Wrong_Missing_Items', 50.00, 75.00, 25, true);
        Contact c = makeContact();
        c.CARES_Tier__c = gold.Id;
        update c;

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 14.00, 0, 0, '');
        System.assertEquals(true, r.eligible);
        System.assertEquals(14.00, r.refundAmount, 'Affected value is below the 50.00 standard ceiling');
        System.assertEquals(17.50, r.creditAmount, '14.00 + 25% bonus');
        System.assertEquals('Gold', r.tierName);
        System.assertEquals('USD', r.currencyCode, 'Blank order currency falls back to USD');
    }

    @IsTest
    static void standardLimitAppliesWhenAffectedValueExceedsIt() {
        CARES_Tier__c tier = makeTier('Silver', 2, true);
        makePolicy(tier, 'Quality_Issue', 10.00, 20.00, 15, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        update c;

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Quality_Issue', 'NOT_CLEAN', 35.00, 0, 0, '');
        System.assertEquals(10.00, r.refundAmount, 'Standard ceiling caps a high affected value');
    }

    @IsTest
    static void cleanRiskStatusUnlocksTheHigherLimit() {
        CARES_Tier__c tier = makeTier('Silver', 2, true);
        makePolicy(tier, 'Quality_Issue', 10.00, 20.00, 15, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        update c;

        CARES_Refund_CalculateOffer.Result clean = offer(c.Id, 'Quality_Issue', 'CLEAN', 35.00, 0, 0, '');
        System.assertEquals(20.00, clean.refundAmount, 'CLEAN unlocks the clean-history ceiling (D-025)');

        CARES_Refund_CalculateOffer.Result unknown = offer(c.Id, 'Quality_Issue', 'UNKNOWN', 35.00, 0, 0, '');
        System.assertEquals(10.00, unknown.refundAmount, 'UNKNOWN never gets the clean-history ceiling (D-025)');
    }

    @IsTest
    static void blankTierFallsBackToTheLowestActiveTier() {
        makeTier('Bronze', 1, true);
        CARES_Tier__c bronzeLowest = [SELECT Id, Name FROM CARES_Tier__c WHERE Name = 'Bronze' LIMIT 1];
        makeTier('Platinum', 10, true);
        makePolicy(bronzeLowest, 'Wrong_Missing_Items', 8.00, 12.00, 10, true);
        Contact c = makeContact();
        // CARES_Tier__c left blank on purpose

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 5.00, 0, 0, '');
        System.assertEquals('Bronze', r.tierName, 'Blank tier resolves to the lowest active tier');
        System.assertEquals(5.00, r.refundAmount);
    }

    @IsTest
    static void inactiveTierOnTheContactFallsBackToTheLowestActiveTier() {
        CARES_Tier__c bronze = makeTier('Bronze', 1, true);
        CARES_Tier__c oldTier = makeTier('Retired', 99, false);
        makePolicy(bronze, 'Wrong_Missing_Items', 9.00, 11.00, 10, true);
        Contact c = makeContact();
        c.CARES_Tier__c = oldTier.Id;
        update c;

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 5.00, 0, 0, '');
        System.assertEquals('Bronze', r.tierName, 'An inactive tier on the Contact is ignored');
    }

    @IsTest
    static void noActiveTierMakesTheOfferIneligible() {
        Contact c = makeContact();
        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 5.00, 0, 0, '');
        System.assertEquals(false, r.eligible, 'No active CARES_Tier__c row at all means no tier can be resolved');
        System.assert(String.isNotBlank(r.ineligibleReason));
        System.assertEquals(0, r.refundAmount);
        System.assertEquals(0, r.creditAmount);
    }

    @IsTest
    static void noMatchingPolicyRowMakesTheOfferIneligible() {
        CARES_Tier__c tier = makeTier('Gold', 3, true);
        makePolicy(tier, 'Quality_Issue', 50.00, 75.00, 25, true);
        // No policy row for Wrong_Missing_Items on this tier
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        update c;

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 5.00, 0, 0, '');
        System.assertEquals(false, r.eligible);
        System.assert(String.isNotBlank(r.ineligibleReason));
    }

    @IsTest
    static void inactivePolicyRowIsIgnored() {
        CARES_Tier__c tier = makeTier('Gold', 3, true);
        makePolicy(tier, 'Wrong_Missing_Items', 50.00, 75.00, 25, false);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        update c;

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 5.00, 0, 0, '');
        System.assertEquals(false, r.eligible, 'An inactive policy row must not be matched');
    }

    @IsTest
    static void readyPathUsesTheApprovedFullAmountNotThePolicy() {
        CARES_Tier__c tier = makeTier('Bronze', 1, true);
        makePolicy(tier, 'Stolen', 5.00, 5.00, 10, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        update c;

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Stolen', 'UNKNOWN', 0, 25.00, 25.00, 'EUR');
        System.assertEquals(25.00, r.refundAmount, 'READY path bypasses the small policy ceiling (D-021/D-028)');
        System.assertEquals(30.00, r.creditAmount, 'READY path credit is total + default bonus (D-029)');
        System.assertEquals('EUR', r.currencyCode, 'Order currency is echoed (D-036)');
    }

    @IsTest
    static void refundNeverExceedsTheOrderTotalCap() {
        CARES_Tier__c tier = makeTier('Gold', 3, true);
        makePolicy(tier, 'Wrong_Missing_Items', 50.00, 75.00, 20, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        update c;

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 40.00, 0, 10.00, '');
        System.assertEquals(10.00, r.refundAmount, 'Order total cap applies even under the policy ceiling');
        System.assertEquals(12.00, r.creditAmount);

        CARES_Refund_CalculateOffer.Result ready = offer(c.Id, 'Stolen', 'UNKNOWN', 0, 40.00, 20.00, '');
        System.assertEquals(20.00, ready.refundAmount, 'Cap also applies to an approved amount');
    }

    @IsTest
    static void offerHandlesABatchInOrder() {
        CARES_Tier__c tier = makeTier('Gold', 3, true);
        makePolicy(tier, 'Wrong_Missing_Items', 50.00, 75.00, 20, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        update c;

        CARES_Refund_CalculateOffer.Request a = new CARES_Refund_CalculateOffer.Request();
        a.contactId = c.Id;
        a.orderOutcome = 'Wrong_Missing_Items';
        a.riskStatus = 'NOT_CLEAN';
        a.affectedValue = 5.00;
        a.orderTotalCap = 5.00;
        CARES_Refund_CalculateOffer.Request b = new CARES_Refund_CalculateOffer.Request();
        b.contactId = c.Id;
        b.orderOutcome = 'Stolen';
        b.riskStatus = 'UNKNOWN';
        b.approvedFullAmount = 30.00;
        List<CARES_Refund_CalculateOffer.Result> rs = CARES_Refund_CalculateOffer.execute(
            new List<CARES_Refund_CalculateOffer.Request>{ a, b }
        );
        System.assertEquals(2, rs.size());
        System.assertEquals(5.00, rs[0].refundAmount);
        System.assertEquals(30.00, rs[1].refundAmount);
    }

    // issue_resolution: real audit row + one-per-order (D-024)

    @IsTest
    static void issueInsertsAResolutionRowAndReportsSuccess() {
        Contact c = makeContact();
        CARES_Refund_IssueResolution.Result r;
        System.runAs(refundUser()) {
            r = issue(c.Id, ORDER_ID, 'Store_Credit', 15.00, 18.00);
        }
        System.assertEquals(true, r.success, 'Issue failed: ' + r.message);
        System.assert(String.isNotBlank(r.referenceNumber));
        System.assert(r.message.contains('18.00'), 'Credit message shows the credit amount');

        CARES_Resolution__c saved = [
            SELECT Contact__c, Order_Id__c, Resolution_Type__c, Amount__c, Status__c
            FROM CARES_Resolution__c
            WHERE Order_Id__c = :ORDER_ID
        ];
        System.assertEquals(c.Id, saved.Contact__c);
        System.assertEquals('Store_Credit', saved.Resolution_Type__c);
        System.assertEquals(18.00, saved.Amount__c, 'Store credit amount is the credit amount, not the refund amount');
        System.assertEquals('Issued', saved.Status__c);
    }

    @IsTest
    static void refundMessageAndAmountUseTheRefundAmountNotCredit() {
        Contact c = makeContact();
        CARES_Refund_IssueResolution.Result r;
        System.runAs(refundUser()) {
            r = issue(c.Id, ORDER_ID, 'Refund', 15.00, 18.00);
        }
        System.assert(r.message.contains('15.00'), 'Refund message shows the refund amount');
        System.assert(r.message.contains('original payment method'), 'Refunds go to the original payment method only');
        CARES_Resolution__c saved = [SELECT Amount__c FROM CARES_Resolution__c WHERE Order_Id__c = :ORDER_ID];
        System.assertEquals(15.00, saved.Amount__c);
    }

    @IsTest
    static void secondResolutionOnTheSameOrderIsRejectedCleanlyNotWithADmlException() {
        Contact c = makeContact();
        System.runAs(refundUser()) {
            CARES_Refund_IssueResolution.Result first = issue(c.Id, ORDER_ID, 'Refund', 15.00, 18.00);
            System.assertEquals(true, first.success);

            CARES_Refund_IssueResolution.Result second;
            try {
                second = issue(c.Id, ORDER_ID, 'Refund', 15.00, 18.00);
            } catch (Exception e) {
                System.assert(false, 'A duplicate order must return a clean failure, not throw: ' + e.getMessage());
            }
            System.assertEquals(false, second.success, 'One resolution per order (D-024)');
            System.assert(String.isNotBlank(second.message));
        }
        System.assertEquals(1, [SELECT COUNT() FROM CARES_Resolution__c WHERE Order_Id__c = :ORDER_ID]);
    }

    @IsTest
    static void twoDifferentOrdersCanEachGetOneResolution() {
        Contact c = makeContact();
        System.runAs(refundUser()) {
            CARES_Refund_IssueResolution.Result first = issue(c.Id, ORDER_ID, 'Refund', 15.00, 18.00);
            CARES_Refund_IssueResolution.Result secondOrder = issue(c.Id, 'STUB-ORDER-2099', 'Refund', 10.00, 12.00);
            System.assertEquals(true, first.success);
            System.assertEquals(true, secondOrder.success);
        }
        System.assertEquals(2, [SELECT COUNT() FROM CARES_Resolution__c]);
    }

    @IsTest
    static void unknownContactIsAnErrorNotAnInsert() {
        Contact c = makeContact();
        Id goneId = c.Id;
        delete c;
        CARES_Refund_IssueResolution.Result r = issue(goneId, ORDER_ID, 'Refund', 15.00, 18.00);
        System.assertEquals(false, r.success);
        System.assertEquals(0, [SELECT COUNT() FROM CARES_Resolution__c]);
    }

    @IsTest
    static void malformedContactIdFailsGracefully() {
        CARES_Refund_IssueResolution.Result r;
        try {
            r = issue('not-an-id', ORDER_ID, 'Refund', 15.00, 18.00);
        } catch (Exception e) {
            System.assert(false, 'A malformed contact id must not throw: ' + e.getMessage());
        }
        System.assertEquals(false, r.success);
    }

    @IsTest
    static void duplicateOrdersInOneBatchOnlyInsertOne() {
        Contact c = makeContact();
        CARES_Refund_IssueResolution.Request a = new CARES_Refund_IssueResolution.Request();
        a.contactId = c.Id;
        a.orderId = ORDER_ID;
        a.resolutionType = 'Refund';
        a.refundAmount = 15.00;
        a.creditAmount = 18.00;
        CARES_Refund_IssueResolution.Request b = new CARES_Refund_IssueResolution.Request();
        b.contactId = c.Id;
        b.orderId = ORDER_ID;
        b.resolutionType = 'Refund';
        b.refundAmount = 15.00;
        b.creditAmount = 18.00;

        List<CARES_Refund_IssueResolution.Result> rs;
        System.runAs(refundUser()) {
            rs = CARES_Refund_IssueResolution.execute(new List<CARES_Refund_IssueResolution.Request>{ a, b });
        }
        System.assertEquals(2, rs.size());
        System.assertEquals(true, rs[0].success);
        System.assertEquals(false, rs[1].success, 'Second request in the same batch for the same order must not also insert');
        System.assertEquals(1, [SELECT COUNT() FROM CARES_Resolution__c WHERE Order_Id__c = :ORDER_ID]);
    }

    // apply_settlement (still a stub; out of scope for this build)

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
