/**
 * Unit tests for CARES_OrderData (D-071, D-072, D-074) and the read-only
 * get_order_status action (D-075). Data Cloud does not run in unit tests, so
 * the rows are CARES_OrderData.mockRows, in the same column order as the query.
 * The rows copy defects seen in the real data on 2026-10-21: a "1x " quantity
 * prefix and an estimate months after the order.
 */
@IsTest
private class CARES_OrderDataTest {
    private static final String APP_ID = 'PA-test-orders-2';
    private static final String DELIVERED_ID = 'PR-241018-TEST001';
    private static final String ON_THE_WAY_ID = 'PR-241019-TEST002';
    private static final String OTHER_CUSTOMERS_ID = 'PR-241020-OTHER01';

    private static List<Object> row(String customerId, String orderId, String createdAt, String status, String total, String items, String eta, String etaMinutes, String deliveredAt) {
        return new List<Object>{ customerId, orderId, createdAt, status, 'Test Kitchen', total, items, eta, etaMinutes, deliveredAt };
    }

    // Newest first, like the query: another customer's order, then this customer's order on the way, then a delivered one
    private static Contact setUp() {
        Contact c = new Contact(LastName = 'CARES Orders', Pronto_App_Account_Id__c = APP_ID);
        Database.insert(c, AccessLevel.SYSTEM_MODE);
        CARES_OrderData.mockRows = new List<List<Object>>{
            row('PA-someone-else', OTHER_CUSTOMERS_ID, '2024-10-20 12:00:00.000 UTC', 'Preparing', '10.00', 'Soup', null, '20', null),
            row(APP_ID, ON_THE_WAY_ID, '2024-10-19 12:00:00.000 UTC', 'Out for Delivery', '18.75', '1x Turkey Sandwich; 1x Iced Tea; 1x Chips', '2025-02-01 09:00:00.000 UTC', '40.000000000000000000', null),
            row(APP_ID, DELIVERED_ID, '2024-10-18 18:00:00.000 UTC', 'Delivered', '38.50', 'Cheeseburger; Large Fries; Chicken Salad; Lemonade', null, null, '2024-10-18 18:40:00.000 UTC')
        };
        return c;
    }

    private static CARES_Order_GetStatus.Result status(String contactId, String orderNumber) {
        CARES_Order_GetStatus.Request req = new CARES_Order_GetStatus.Request();
        req.contactId = contactId;
        req.orderNumber = orderNumber;
        return CARES_Order_GetStatus.execute(new List<CARES_Order_GetStatus.Request>{ req })[0];
    }

    @IsTest
    static void mostRecentOrderSkipsOtherCustomersRows() {
        Contact c = setUp();
        CARES_OrderData.Lookup latest = CARES_OrderData.find(c.Id, '', false);
        System.assertEquals(true, latest.found);
        System.assertEquals(ON_THE_WAY_ID, latest.order.orderId, 'The newer row belongs to another customer');

        CARES_OrderData.Lookup delivered = CARES_OrderData.find(c.Id, '', true);
        System.assertEquals(DELIVERED_ID, delivered.order.orderId, 'Refund only looks at delivered orders');
    }

    @IsTest
    static void anotherCustomersOrderNumberIsNotFound() {
        Contact c = setUp();
        CARES_OrderData.Lookup l = CARES_OrderData.find(c.Id, OTHER_CUSTOMERS_ID, false);
        System.assertEquals(false, l.found);
        System.assertEquals(CARES_OrderData.NOT_FOUND, l.reason);
        System.assertEquals(null, l.order);
    }

    @IsTest
    static void anOrderNotYetDeliveredIsReportedAsSuch() {
        Contact c = setUp();
        CARES_OrderData.Lookup l = CARES_OrderData.find(c.Id, ON_THE_WAY_ID, true);
        System.assertEquals(false, l.found);
        System.assertEquals(CARES_OrderData.NOT_DELIVERED, l.reason);
    }

    @IsTest
    static void orderNumbersAreNormalizedAndCheckedBeforeAnyQuery() {
        Contact c = setUp();
        System.assertEquals(true, CARES_OrderData.find(c.Id, ' #pr-241018-test001 ', true).found, 'Case, spaces and # are ignored');
        System.assertEquals(true, CARES_OrderData.find(c.Id, '241018-TEST001', true).found, 'The PR- prefix is optional');
        System.assertEquals(CARES_OrderData.NOT_A_PRONTO_ORDER_NUMBER, CARES_OrderData.find(c.Id, '1042', true).reason);
        System.assertEquals(CARES_OrderData.NOT_A_PRONTO_ORDER_NUMBER, CARES_OrderData.find(c.Id, 'PR-241018-X\' OR 1=1', true).reason, 'Nothing but a real order number reaches the SQL');
    }

    @IsTest
    static void aContactWithoutAnAppAccountIdHasNoOrders() {
        setUp();
        Contact noLink = new Contact(LastName = 'No Link');
        Database.insert(noLink, AccessLevel.SYSTEM_MODE);
        System.assertEquals(CARES_OrderData.NO_ACCOUNT_LINK, CARES_OrderData.find(noLink.Id, '', false).reason);
        System.assertEquals(CARES_OrderData.NO_ACCOUNT_LINK, CARES_OrderData.find('', '', false).reason);
        System.assertEquals(CARES_OrderData.NO_ACCOUNT_LINK, CARES_OrderData.find('not-an-id', '', false).reason);
    }

    @IsTest
    static void itemsLoseTheQuantityPrefixAndSplitTheTotal() {
        Contact c = setUp();
        CARES_OrderData.OrderRow o = CARES_OrderData.find(c.Id, ON_THE_WAY_ID, false).order;
        System.assertEquals(3, o.items.size());
        System.assertEquals('Turkey Sandwich', o.items[0].name, 'The "1x " prefix is removed');
        System.assertEquals(6.25, o.items[0].price, '18.75 / 3');
        Decimal sum = 0;
        for (CARES_OrderData.Item i : o.items) {
            sum += i.price;
        }
        System.assertEquals(18.75, sum, 'Item prices add up to the total');

        CARES_OrderData.OrderRow d = CARES_OrderData.find(c.Id, DELIVERED_ID, true).order;
        System.assertEquals(9.62, d.items[0].price, '38.50 / 4, rounded down');
        System.assertEquals(9.64, d.items[3].price, 'The last item takes the rounding');
        System.assertEquals('Cheeseburger $9.62; Large Fries $9.62; Chicken Salad $9.62; Lemonade $9.64', CARES_OrderData.lineItems(d));
        System.assertEquals('Order PR-241018-TEST001, ordered Oct 18, 2024, from Test Kitchen, $38.50', CARES_OrderData.summary(d));
    }

    @IsTest
    static void anEstimateMonthsAfterTheOrderIsReplacedByOrderTimePlusEtaMinutes() {
        Contact c = setUp();
        CARES_OrderData.OrderRow o = CARES_OrderData.find(c.Id, ON_THE_WAY_ID, false).order;
        System.assertEquals(Datetime.newInstanceGmt(2024, 10, 19, 12, 40, 0), o.estimatedDeliveryAt);
    }

    @IsTest
    static void dataStatusesUseTheDeliveryFaqWords() {
        System.assertEquals('Accepted', CARES_OrderData.faqStatus('Preparing'));
        System.assertEquals('Picked Up', CARES_OrderData.faqStatus('PickedUp'));
        System.assertEquals('Picked Up', CARES_OrderData.faqStatus('Out for Delivery'));
        System.assertEquals('Delivered', CARES_OrderData.faqStatus('Delivered'));
        System.assertEquals('Canceled', CARES_OrderData.faqStatus('Canceled'));
        System.assertEquals('Returned', CARES_OrderData.faqStatus('Returned'), 'An unknown status is passed through, not guessed');
    }

    @IsTest
    static void noRowsMeansNotFound() {
        Contact c = setUp();
        CARES_OrderData.mockRows = new List<List<Object>>();
        System.assertEquals(CARES_OrderData.NOT_FOUND, CARES_OrderData.find(c.Id, '', false).reason);
    }

    @IsTest
    static void aMalformedRowIsReadWithoutThrowing() {
        Contact c = setUp();
        CARES_OrderData.mockRows = new List<List<Object>>{
            new List<Object>{ APP_ID, 'PR-241022-BADROW1', 'not a date at all, really', 'Delivered', null, 'abc', '  ', 'later', 'soon' }
        };
        CARES_OrderData.Lookup l = CARES_OrderData.find(c.Id, '', true);
        System.assertEquals(true, l.found);
        System.assertEquals(null, l.order.createdAt);
        System.assertEquals(null, l.order.total);
        System.assertEquals(0, l.order.items.size(), 'No items: log_order_issue then rejects every name');
        System.assertEquals(null, l.order.estimatedDeliveryAt);
        System.assertEquals(null, l.order.deliveredAt, 'A short row reads as blank, not out of range');
        System.assertEquals('Order PR-241022-BADROW1', CARES_OrderData.summary(l.order));
    }

    @IsTest
    static void aDataCloudErrorIsReportedNeverGuessed() {
        Contact c = setUp();
        CARES_OrderData.mockQueryFails = true;
        CARES_OrderData.Lookup l = CARES_OrderData.find(c.Id, '', false);
        System.assertEquals(false, l.found);
        System.assertEquals(CARES_OrderData.DATA_UNAVAILABLE, l.reason);
        System.assertEquals(CARES_OrderData.DATA_UNAVAILABLE, status(c.Id, '').notFoundReason);
    }

    // get_order_status (D-075)

    @IsTest
    static void statusOfTheMostRecentOrderOnItsWay() {
        Contact c = setUp();
        CARES_Order_GetStatus.Result r = status(c.Id, '');
        System.assertEquals(true, r.found);
        System.assertEquals(ON_THE_WAY_ID, r.orderId);
        System.assertEquals('Picked Up', r.status);
        System.assert(r.statusSummary.contains('on its way'), r.statusSummary);
        System.assert(r.statusSummary.contains('Oct 19, 2024 12:40 PM UTC'), r.statusSummary);
        System.assert(r.statusSummary.contains('estimate'), 'The ETA is called an estimate (POL-P20)');
    }

    @IsTest
    static void statusOfADeliveredOrderGivesTheDeliveryTime() {
        Contact c = setUp();
        CARES_Order_GetStatus.Result r = status(c.Id, DELIVERED_ID);
        System.assertEquals('Delivered', r.status);
        System.assertEquals('Order PR-241018-TEST001 from Test Kitchen was delivered on Oct 18, 2024 6:40 PM UTC.', r.statusSummary);
    }

    @IsTest
    static void statusSummariesForAcceptedCanceledAndUnknown() {
        Contact c = setUp();
        CARES_OrderData.mockRows = new List<List<Object>>{
            row(APP_ID, 'PR-241021-TEST003', '2024-10-21 12:00:00.000 UTC', 'Preparing', '10.00', 'Soup', '2024-10-21 12:30:00.000 UTC', '30', null),
            row(APP_ID, 'PR-241020-TEST004', '2024-10-20 12:00:00.000 UTC', 'Canceled', '10.00', 'Soup', null, null, null),
            row(APP_ID, 'PR-241019-TEST005', '2024-10-19 12:00:00.000 UTC', 'Returned', '10.00', 'Soup', null, null, null)
        };
        System.assert(status(c.Id, '').statusSummary.contains('preparing it. Estimated delivery: Oct 21, 2024 12:30 PM UTC'));
        System.assertEquals('Order PR-241020-TEST004 from Test Kitchen was canceled.', status(c.Id, 'PR-241020-TEST004').statusSummary);
        System.assertEquals('Order PR-241019-TEST005 from Test Kitchen has the status Returned.', status(c.Id, 'PR-241019-TEST005').statusSummary);
    }

    @IsTest
    static void statusOfAnotherCustomersOrderIsNotFound() {
        Contact c = setUp();
        CARES_Order_GetStatus.Result r = status(c.Id, OTHER_CUSTOMERS_ID);
        System.assertEquals(false, r.found);
        System.assertEquals('', r.status);
        System.assertEquals('', r.statusSummary);
        System.assertEquals(CARES_OrderData.NOT_FOUND, r.notFoundReason);
    }
}
