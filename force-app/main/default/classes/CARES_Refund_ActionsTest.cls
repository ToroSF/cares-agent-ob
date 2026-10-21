/**
 * Unit tests for the five Refund invocable actions. find_order and log_order_issue
 * read real orders from Data Cloud (D-071); Data Cloud does not run in unit tests,
 * so they use CARES_OrderData.mockRows (one delivered order, four items, $38.50,
 * so each item is worth 9.62 and the last one 9.64, D-072). calculate_refund_offer's
 * policy/limit lookup and issue_resolution's audit-trail insert are real
 * sObjects/SOQL/DML (D-024). They pin the rules the agent relies on (D-019, D-030, D-036).
 *
 * First run in an org: check-only validation on 2026-10-21. Test data is written
 * in SYSTEM_MODE because the user running the tests has no access to the new
 * fields; the actions run as refundUser(), like the agent user does.
 */
@IsTest
private class CARES_Refund_ActionsTest {
    private static final String ORDER_ID = 'PR-241018-TEST001';
    private static final String APP_ID = 'PA-test-orders-1';

    // A delivered order of APP_ID, rowData in CARES_OrderData's column order
    private static void mockOrder() {
        CARES_OrderData.mockRows = new List<List<Object>>{
            new List<Object>{
                APP_ID, ORDER_ID, '2024-10-18 18:00:00.000 UTC', 'Delivered', 'Test Kitchen', '38.50',
                'Cheeseburger; 1x Large Fries; Chicken Salad; Lemonade', null, null, '2024-10-18 18:40:00.000 UTC'
            }
        };
    }

    private static Contact orderContact() {
        Contact c = new Contact(LastName = 'CARES Orders', Pronto_App_Account_Id__c = APP_ID);
        Database.insert(c, AccessLevel.SYSTEM_MODE);
        mockOrder();
        return c;
    }

    private static Id cachedOrderContactId;

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
        Database.insert(t, AccessLevel.SYSTEM_MODE);
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
        Database.insert(p, AccessLevel.SYSTEM_MODE);
        return p;
    }

    private static User cachedRefundUser;

    // One user per test: offer() can be called more than once, and usernames must be unique
    private static User refundUser() {
        if (cachedRefundUser != null) {
            return cachedRefundUser;
        }
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
        cachedRefundUser = u;
        return u;
    }

    private static CARES_Refund_LogOrderIssue.Result logIssue(String issueType, String affectedItems, String deliveryPath) {
        if (cachedOrderContactId == null) {
            cachedOrderContactId = orderContact().Id;
        }
        CARES_Refund_LogOrderIssue.Request req = new CARES_Refund_LogOrderIssue.Request();
        req.contactId = cachedOrderContactId;
        req.orderId = ORDER_ID;
        req.issueType = issueType;
        req.issueDescription = 'Customer description';
        req.affectedItems = affectedItems;
        req.deliveryPath = deliveryPath;
        return CARES_Refund_LogOrderIssue.execute(new List<CARES_Refund_LogOrderIssue.Request>{ req })[0];
    }

    // Order id the offer() helper uses; tests about another order set it first
    private static String offerOrderId = ORDER_ID;

    // Inserts a resolution row for an order, as the payout would (SYSTEM_MODE: test setup only)
    private static void resolve(Id contactId, String orderId, String status) {
        Database.insert(new CARES_Resolution__c(
            Contact__c = contactId, Order_Id__c = orderId, Resolution_Type__c = 'Refund',
            Amount__c = 10.00, Status__c = status
        ), AccessLevel.SYSTEM_MODE);
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
        req.orderId = offerOrderId;
        req.orderOutcome = orderOutcome;
        req.riskStatus = riskStatus;
        req.affectedValue = affectedValue;
        req.approvedFullAmount = approvedFullAmount;
        req.orderTotalCap = orderTotalCap;
        req.orderCurrency = orderCurrency;
        CARES_Refund_CalculateOffer.Result r;
        System.runAs(refundUser()) {
            r = CARES_Refund_CalculateOffer.execute(new List<CARES_Refund_CalculateOffer.Request>{ req })[0];
        }
        return r;
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

    // find_order (real orders, D-071)

    @IsTest
    static void findOrderReturnsTheCustomersDeliveredOrderWithPricedItems() {
        Contact c = orderContact();
        CARES_Refund_FindOrder.Request req = new CARES_Refund_FindOrder.Request();
        req.contactId = c.Id;
        req.orderNumber = '';
        CARES_Refund_FindOrder.Result r = CARES_Refund_FindOrder.execute(new List<CARES_Refund_FindOrder.Request>{ req })[0];
        System.assertEquals(true, r.found);
        System.assertEquals(ORDER_ID, r.orderId);
        System.assertEquals(38.50, r.orderTotal, 'The real total becomes the refund cap');
        System.assert(r.lineItems.contains('Large Fries $9.62'), 'Quantity prefix removed, price = total / items: ' + r.lineItems);
        System.assert(r.orderSummary.contains('Test Kitchen'), r.orderSummary);
        System.assertEquals('', r.notFoundReason);
    }

    @IsTest
    static void findOrderDoesNotReturnAnOrderOfAnotherCustomer() {
        Contact other = new Contact(LastName = 'Other', Pronto_App_Account_Id__c = 'PA-someone-else');
        Database.insert(other, AccessLevel.SYSTEM_MODE);
        mockOrder();
        CARES_Refund_FindOrder.Request req = new CARES_Refund_FindOrder.Request();
        req.contactId = other.Id;
        req.orderNumber = ORDER_ID;
        CARES_Refund_FindOrder.Result r = CARES_Refund_FindOrder.execute(new List<CARES_Refund_FindOrder.Request>{ req })[0];
        System.assertEquals(false, r.found);
        System.assertEquals('', r.orderId);
        System.assertEquals(0, r.orderTotal);
        System.assertEquals(CARES_OrderData.NOT_FOUND, r.notFoundReason);
    }

    // log_order_issue: path rules (D-030) and item validation (G-023)

    @IsTest
    static void itemIssuesOnListedItemsAreAcceptedAtTheRealPrice() {
        CARES_Refund_LogOrderIssue.Result wrong = logIssue('Wrong_Missing_Items', 'Cheeseburger', '');
        System.assertEquals(true, wrong.accepted);
        System.assertEquals('Wrong_Missing_Items', wrong.orderOutcome);
        System.assertEquals(9.62, wrong.affectedValue, 'Priced from the real order (total / items), not a flat 12.00');

        CARES_Refund_LogOrderIssue.Result quality = logIssue('Quality_Issue', 'Large Fries', '');
        System.assertEquals('Quality_Issue', quality.orderOutcome);
        System.assertEquals(9.62, quality.affectedValue, 'Matches the name without the 1x prefix');

        CARES_Refund_LogOrderIssue.Result noItems = logIssue('Wrong_Missing_Items', '', '');
        System.assertEquals(false, noItems.accepted);
        System.assertEquals('', noItems.orderOutcome, 'A rejected issue must not set an outcome');
        System.assertEquals(0, noItems.affectedValue);
    }

    @IsTest
    static void itemNotOnTheOrderIsRejectedNotValuedAtTwelve() {
        // Closes the known issue in G-023: an unlisted item must be rejected, not accepted at 12.00
        CARES_Refund_LogOrderIssue.Result r = logIssue('Wrong_Missing_Items', 'Sushi', '');
        System.assertEquals(false, r.accepted, 'Sushi is not on the order');
        System.assertEquals('', r.orderOutcome);
        System.assertEquals(0, r.affectedValue);
    }

    @IsTest
    static void multipleListedItemsSumTheirRealPrices() {
        CARES_Refund_LogOrderIssue.Result r = logIssue('Wrong_Missing_Items', 'Cheeseburger, Lemonade', '');
        System.assertEquals(true, r.accepted);
        System.assertEquals(19.26, r.affectedValue, '9.62 Cheeseburger + 9.64 Lemonade (the last item takes the rounding)');
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
        System.assertEquals(9.62, r.affectedValue);
    }

    @IsTest
    static void itemCopiedWithItsPriceStillMatches() {
        CARES_Refund_LogOrderIssue.Result r = logIssue('Wrong_Missing_Items', 'Lemonade $9.64', '');
        System.assertEquals(true, r.accepted);
        System.assertEquals(9.64, r.affectedValue, 'The value comes from the order, not from the copied text');
    }

    @IsTest
    static void itemIssueOnAnOrderThatIsNotTheCustomersIsRejected() {
        CARES_Refund_LogOrderIssue.Request req = new CARES_Refund_LogOrderIssue.Request();
        req.contactId = orderContact().Id;
        req.orderId = 'PR-241018-NOTMINE';
        req.issueType = 'Wrong_Missing_Items';
        req.issueDescription = 'Customer description';
        req.affectedItems = 'Cheeseburger';
        CARES_Refund_LogOrderIssue.Result r = CARES_Refund_LogOrderIssue.execute(new List<CARES_Refund_LogOrderIssue.Request>{ req })[0];
        System.assertEquals(false, r.accepted);
        System.assertEquals(0, r.affectedValue);
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
        Database.update(c, AccessLevel.SYSTEM_MODE);

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 14.00, 0, 0, '');
        System.assertEquals(true, r.eligible);
        System.assertEquals(14.00, r.refundAmount, 'Affected value is below the 50.00 standard ceiling');
        System.assertEquals(17.50, r.creditAmount, '14.00 + 25% bonus');
        System.assertEquals('Gold', r.tierName);
        System.assertEquals(UserInfo.getDefaultCurrency(), r.currencyCode, 'Blank order currency falls back to the org default, not a hardcoded USD');
    }

    @IsTest
    static void standardLimitAppliesWhenAffectedValueExceedsIt() {
        CARES_Tier__c tier = makeTier('Silver', 2, true);
        makePolicy(tier, 'Quality_Issue', 10.00, 20.00, 15, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        Database.update(c, AccessLevel.SYSTEM_MODE);

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Quality_Issue', 'NOT_CLEAN', 35.00, 0, 0, '');
        System.assertEquals(10.00, r.refundAmount, 'Standard ceiling caps a high affected value');
    }

    @IsTest
    static void cleanRiskStatusUnlocksTheHigherLimit() {
        CARES_Tier__c tier = makeTier('Silver', 2, true);
        makePolicy(tier, 'Quality_Issue', 10.00, 20.00, 15, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        Database.update(c, AccessLevel.SYSTEM_MODE);

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
        Database.update(c, AccessLevel.SYSTEM_MODE);

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
        Database.update(c, AccessLevel.SYSTEM_MODE);

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
        Database.update(c, AccessLevel.SYSTEM_MODE);

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 5.00, 0, 0, '');
        System.assertEquals(false, r.eligible, 'An inactive policy row must not be matched');
    }

    @IsTest
    static void readyPathUsesTheApprovedFullAmountNotThePolicy() {
        CARES_Tier__c tier = makeTier('Bronze', 1, true);
        makePolicy(tier, 'Stolen', 5.00, 5.00, 10, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        Database.update(c, AccessLevel.SYSTEM_MODE);

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Stolen', 'UNKNOWN', 0, 25.00, 25.00, 'EUR');
        System.assertEquals(25.00, r.refundAmount, 'READY path bypasses the small policy ceiling (D-021/D-028)');
        System.assertEquals(27.50, r.creditAmount, 'READY path credit is total + the tier row bonus, 10% here (D-029), not an invented 20%');
        System.assertEquals('EUR', r.currencyCode, 'Order currency is echoed (D-036)');
    }

    // G-091 (D-088): no offer on an order that already has a resolution, on any path

    @IsTest
    static void offerOnAnOrderWithAResolutionIsIneligible() {
        CARES_Tier__c tier = makeTier('Bronze', 1, true);
        makePolicy(tier, 'Wrong_Missing_Items', 50.00, 75.00, 20, true);
        Contact c = makeContact();
        resolve(c.Id, ORDER_ID, 'Issued');

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'CLEAN', 20.00, 0, 0, '');
        System.assertEquals(false, r.eligible);
        System.assertEquals(true, r.alreadyResolved);
        System.assertEquals(0, r.refundAmount);
        System.assertEquals(0, r.creditAmount);
        System.assert(r.ineligibleReason.contains('already has a refund or credit on file'), r.ineligibleReason);
    }

    @IsTest
    static void readyPathOnAResolvedOrderIsIneligible() {
        CARES_Tier__c tier = makeTier('Bronze', 1, true);
        makePolicy(tier, 'Stolen', 5.00, 5.00, 10, true);
        Contact c = makeContact();
        resolve(c.Id, ORDER_ID, 'Issued');

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Stolen', 'UNKNOWN', 0, 25.00, 25.00, 'EUR');
        System.assertEquals(false, r.eligible, 'An approved Stolen & Delayed claim is refused too when the order is paid');
        System.assertEquals(true, r.alreadyResolved);
        System.assertEquals(0, r.refundAmount);
    }

    @IsTest
    static void aDifferentOrderIsStillEligible() {
        CARES_Tier__c tier = makeTier('Bronze', 1, true);
        makePolicy(tier, 'Wrong_Missing_Items', 50.00, 75.00, 20, true);
        Contact c = makeContact();
        resolve(c.Id, 'PR-241019-TEST002', 'Issued');

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'NOT_CLEAN', 20.00, 0, 0, '');
        System.assertEquals(true, r.eligible, 'A resolution on another order does not block this one');
        System.assertEquals(false, r.alreadyResolved);
        System.assertEquals(20.00, r.refundAmount);
    }

    @IsTest
    static void aFailedResolutionAlsoBlocks() {
        CARES_Tier__c tier = makeTier('Bronze', 1, true);
        makePolicy(tier, 'Wrong_Missing_Items', 50.00, 75.00, 20, true);
        Contact c = makeContact();
        resolve(c.Id, ORDER_ID, 'Failed');

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Wrong_Missing_Items', 'CLEAN', 20.00, 0, 0, '');
        System.assertEquals(false, r.eligible, 'Any row blocks, so a person reviews instead of a second payout');
        System.assertEquals(true, r.alreadyResolved);
    }

    @IsTest
    static void mixedBatchKeepsRequestOrder() {
        CARES_Tier__c tier = makeTier('Bronze', 1, true);
        makePolicy(tier, 'Wrong_Missing_Items', 50.00, 75.00, 20, true);
        Contact c = makeContact();
        resolve(c.Id, ORDER_ID, 'Issued');

        List<CARES_Refund_CalculateOffer.Request> reqs = new List<CARES_Refund_CalculateOffer.Request>();
        for (String orderId : new List<String>{ ORDER_ID, 'PR-241019-TEST002' }) {
            CARES_Refund_CalculateOffer.Request req = new CARES_Refund_CalculateOffer.Request();
            req.contactId = c.Id;
            req.orderId = orderId;
            req.orderOutcome = 'Wrong_Missing_Items';
            req.riskStatus = 'NOT_CLEAN';
            req.affectedValue = 20.00;
            reqs.add(req);
        }
        List<CARES_Refund_CalculateOffer.Result> rs;
        System.runAs(refundUser()) {
            rs = CARES_Refund_CalculateOffer.execute(reqs);
        }
        System.assertEquals(false, rs[0].eligible, 'Resolved order first');
        System.assertEquals(true, rs[1].eligible, 'New order second');
        System.assertEquals(false, rs[1].alreadyResolved);
    }

    @IsTest
    static void readyPathWithoutAPolicyRowGivesNoBonus() {
        CARES_Tier__c tier = makeTier('Bronze', 1, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        Database.update(c, AccessLevel.SYSTEM_MODE);

        CARES_Refund_CalculateOffer.Result r = offer(c.Id, 'Stolen', 'UNKNOWN', 0, 25.00, 25.00, 'EUR');
        System.assertEquals(25.00, r.refundAmount);
        System.assertEquals(25.00, r.creditAmount, 'No policy row for the outcome means no bonus, never a default one');
    }

    // CARES_Refund_Policy__c validation rules

    private static String insertError(Decimal maxRefund, Decimal cleanMax, Decimal bonusPct) {
        CARES_Tier__c tier = makeTier('Rules', 9, true);
        Database.SaveResult sr = Database.insert(new CARES_Refund_Policy__c(
            Tier__c = tier.Id, Order_Outcome__c = 'Delayed', Max_Refund__c = maxRefund,
            Clean_History_Max_Refund__c = cleanMax, Store_Credit_Bonus_Pct__c = bonusPct, Active__c = true
        ), false, AccessLevel.SYSTEM_MODE);
        return sr.isSuccess() ? '' : sr.getErrors()[0].getMessage();
    }

    @IsTest
    static void cleanMaxBelowTheStandardMaxIsRejected() {
        System.assert(insertError(40.00, 30.00, 10).contains('at least the standard max'), 'Clean max under standard max must fail');
        System.assertEquals('', insertError(40.00, 40.00, 10), 'Equal limits are allowed');
    }

    @IsTest
    static void negativeLimitsAreRejected() {
        System.assert(insertError(-5.00, 10.00, 10).contains('cannot be negative'));
    }

    @IsTest
    static void bonusOutsideZeroToHundredIsRejected() {
        System.assert(insertError(10.00, 20.00, 150).contains('between 0% and 100%'), '150% must fail');
        System.assert(insertError(10.00, 20.00, -1).contains('between 0% and 100%'), '-1% must fail');
        System.assertEquals('', insertError(10.00, 20.00, 100), '100% is allowed');
        System.assertEquals('', insertError(10.00, 20.00, 0), '0% is allowed');
    }

    @IsTest
    static void refundNeverExceedsTheOrderTotalCap() {
        CARES_Tier__c tier = makeTier('Gold', 3, true);
        makePolicy(tier, 'Wrong_Missing_Items', 50.00, 75.00, 20, true);
        Contact c = makeContact();
        c.CARES_Tier__c = tier.Id;
        Database.update(c, AccessLevel.SYSTEM_MODE);

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
        Database.update(c, AccessLevel.SYSTEM_MODE);

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
        List<CARES_Refund_CalculateOffer.Result> rs;
        System.runAs(refundUser()) {
            rs = CARES_Refund_CalculateOffer.execute(new List<CARES_Refund_CalculateOffer.Request>{ a, b });
        }
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
        System.assert(r.message.contains(UserInfo.getDefaultCurrency()), 'Blank currency shows the org default: ' + r.message);
        System.assert(!r.message.contains('$'), 'No hardcoded dollar sign: ' + r.message);
        System.assert(!r.message.contains('business days'), 'No unsourced timing promise (D-065): ' + r.message);
        CARES_Resolution__c saved = [SELECT Amount__c FROM CARES_Resolution__c WHERE Order_Id__c = :ORDER_ID];
        System.assertEquals(15.00, saved.Amount__c);
    }

    @IsTest
    static void creditMessageUsesTheOfferCurrency() {
        Contact c = makeContact();
        CARES_Refund_IssueResolution.Request req = new CARES_Refund_IssueResolution.Request();
        req.contactId = c.Id;
        req.orderId = ORDER_ID;
        req.resolutionType = 'Store_Credit';
        req.refundAmount = 25.00;
        req.creditAmount = 27.50;
        req.currencyCode = 'EUR';
        CARES_Refund_IssueResolution.Result r;
        System.runAs(refundUser()) {
            r = CARES_Refund_IssueResolution.execute(new List<CARES_Refund_IssueResolution.Request>{ req })[0];
        }
        System.assertEquals(true, r.success, 'Issue failed: ' + r.message);
        System.assert(r.message.contains('27.50 EUR'), 'Credit message shows amount and currency: ' + r.message);
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
            CARES_Refund_IssueResolution.Result secondOrder = issue(c.Id, 'PR-241019-TEST002', 'Refund', 10.00, 12.00);
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

    // Settlement recorded with the payout (D-092)

    private static CARES_Refund_IssueResolution.Result issueWithSettlement(Id contactId, String orderId, String driver, String restaurant, Boolean lossAbsorption) {
        CARES_Refund_IssueResolution.Request req = new CARES_Refund_IssueResolution.Request();
        req.contactId = contactId;
        req.orderId = orderId;
        req.resolutionType = 'Refund';
        req.refundAmount = 25.00;
        req.creditAmount = 27.50;
        req.driverCompensation = driver;
        req.restaurantReimbursement = restaurant;
        req.lossAbsorption = lossAbsorption;
        CARES_Refund_IssueResolution.Result r;
        System.runAs(refundUser()) {
            r = CARES_Refund_IssueResolution.execute(new List<CARES_Refund_IssueResolution.Request>{ req })[0];
        }
        return r;
    }

    // Read as the Refund user: the settlement fields are visible through CARES_Refund_Access
    private static CARES_Resolution__c saved(String orderId) {
        CARES_Resolution__c row;
        System.runAs(refundUser()) {
            row = [
                SELECT Driver_Compensation__c, Restaurant_Reimbursement__c, Loss_Absorption__c, Settlement_Status__c
                FROM CARES_Resolution__c
                WHERE Order_Id__c = :orderId
            ];
        }
        return row;
    }

    @IsTest
    static void lossAbsorptionIsRecordedAndNeedsReview() {
        Contact c = makeContact();
        CARES_Refund_IssueResolution.Result r = issueWithSettlement(c.Id, ORDER_ID, 'PAY_IN_FULL', 'REIMBURSE', true);
        System.assertEquals(true, r.success, 'Issue failed: ' + r.message);
        System.assertEquals('Needs_Review', r.settlementStatus, 'The restaurant reimbursement needs a person');
        CARES_Resolution__c row = saved(ORDER_ID);
        System.assertEquals('PAY_IN_FULL', row.Driver_Compensation__c);
        System.assertEquals('REIMBURSE', row.Restaurant_Reimbursement__c);
        System.assertEquals(true, row.Loss_Absorption__c);
        System.assertEquals('Needs_Review', row.Settlement_Status__c);
    }

    @IsTest
    static void driverPaidAndNoRestaurantChangeIsJustRecorded() {
        Contact c = makeContact();
        CARES_Refund_IssueResolution.Result r = issueWithSettlement(c.Id, ORDER_ID, 'PAY_IN_FULL', 'NO_CHANGE', false);
        System.assertEquals('Recorded', r.settlementStatus);
        System.assertEquals('Recorded', saved(ORDER_ID).Settlement_Status__c);
    }

    @IsTest
    static void heldOrWithheldDriverPayNeedsReview() {
        Contact c = makeContact();
        System.assertEquals('Needs_Review', issueWithSettlement(c.Id, ORDER_ID, 'HOLD_FOR_REVIEW', 'NO_CHANGE', false).settlementStatus);
        System.assertEquals('Needs_Review', issueWithSettlement(c.Id, 'PR-241019-TEST002', 'WITHHOLD_DELIVERY_PAY', 'NO_CHANGE', false).settlementStatus);
    }

    @IsTest
    static void directPathHasNoSettlement() {
        Contact c = makeContact();
        CARES_Refund_IssueResolution.Result r = issueWithSettlement(c.Id, ORDER_ID, '', '', false);
        System.assertEquals('Not_Applicable', r.settlementStatus);
        CARES_Resolution__c row = saved(ORDER_ID);
        System.assertEquals(null, row.Driver_Compensation__c);
        System.assertEquals('Not_Applicable', row.Settlement_Status__c);
    }

    @IsTest
    static void unknownRecommendationIsLeftOffAndReviewed() {
        Contact c = makeContact();
        CARES_Refund_IssueResolution.Result r = issueWithSettlement(c.Id, ORDER_ID, 'BONUS_PAY', 'NO_CHANGE', false);
        System.assertEquals(true, r.success, 'An unknown value must not fail the payout: ' + r.message);
        System.assertEquals('Needs_Review', r.settlementStatus);
        System.assertEquals(null, saved(ORDER_ID).Driver_Compensation__c, 'Never written to the restricted picklist');
    }
}
