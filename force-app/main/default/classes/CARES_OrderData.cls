/**
 * Reads one customer's Pronto orders from Data Cloud (Order__dlm, D-071). The join is
 * Contact.Pronto_App_Account_Id__c = Order__dlm.Customer_ID__c, so only the customer's
 * own orders can come back. The data is cleaned on read, never at the source (D-074),
 * and each item is priced as the order total split evenly over its items (D-072).
 * Data Cloud does not run in unit tests: tests set mockRows instead.
 */
public with sharing class CARES_OrderData {
    // rowData is read BY POSITION: add new columns only at the END of this list
    private static final String COLUMNS =
        'Customer_ID__c, Order_ID__c, Created_At__c, Order_Status__c, Restaurant_Name__c, ' +
        'Total_Amount__c, Items_Ordered__c, Estimated_Delivery_At__c, ETA_Minutes__c, Delivered_At__c';
    private static final Pattern ORDER_NUMBER = Pattern.compile('PR-[0-9]{6}-[A-Z0-9]{7}');

    // Lookup reasons, safe for the agent to read
    public static final String NO_ACCOUNT_LINK = 'NO_ACCOUNT_LINK';
    public static final String NOT_A_PRONTO_ORDER_NUMBER = 'NOT_A_PRONTO_ORDER_NUMBER';
    public static final String NOT_FOUND = 'NOT_FOUND';
    public static final String NOT_DELIVERED = 'NOT_DELIVERED';
    public static final String DATA_UNAVAILABLE = 'DATA_UNAVAILABLE';

    // Raw rowData in COLUMNS order, used instead of the Data Cloud query in tests
    @TestVisible
    private static List<List<Object>> mockRows;
    // Makes the test query fail like a Data Cloud outage
    @TestVisible
    private static Boolean mockQueryFails = false;

    private class OrderDataException extends Exception {
    }

    public class Item {
        public String name;
        public Decimal price;
    }

    public class OrderRow {
        public String orderId;
        public Datetime createdAt;
        public String status;
        public String restaurant;
        public Decimal total;
        public List<Item> items;
        public Datetime estimatedDeliveryAt;
        public Datetime deliveredAt;
    }

    public class Lookup {
        public Boolean found = false;
        public String reason = '';
        public OrderRow order;
    }

    // Blank orderNumber: the customer's most recent order (most recent Delivered one when deliveredOnly)
    public static Lookup find(String contactId, String orderNumber, Boolean deliveredOnly) {
        Lookup result = new Lookup();
        String orderId = normalizeOrderNumber(orderNumber);
        if (orderId == null) {
            result.reason = NOT_A_PRONTO_ORDER_NUMBER;
            return result;
        }
        String appId = appAccountId(contactId);
        if (appId == null) {
            result.reason = NO_ACCOUNT_LINK;
            return result;
        }
        List<List<Object>> rows;
        try {
            rows = queryRows(appId, orderId);
        } catch (Exception e) {
            // Never guess an order: the agent asks again or hands to a person
            result.reason = DATA_UNAVAILABLE;
            return result;
        }
        Boolean sawNotDelivered = false;
        for (List<Object> row : rows) {
            // The SQL already filters by customer; checking again keeps another customer's order out
            if (text(row, 0) != appId || (orderId != '' && text(row, 1) != orderId)) {
                continue;
            }
            OrderRow o = parse(row);
            if (deliveredOnly && o.status != 'Delivered') {
                sawNotDelivered = true;
                continue;
            }
            result.found = true;
            result.order = o;
            return result;
        }
        result.reason = (orderId != '' && sawNotDelivered) ? NOT_DELIVERED : NOT_FOUND;
        return result;
    }

    // How many of the customer's orders were not canceled (up to the query limit of 50); null when unknown.
    // Stolen & Delayed uses it for the customer's claim rate (D-090)
    public static Integer nonCanceledOrderCount(String contactId) {
        String appId = appAccountId(contactId);
        if (appId == null) {
            return null;
        }
        List<List<Object>> rows;
        try {
            rows = queryRows(appId, '');
        } catch (Exception e) {
            return null;
        }
        Integer count = 0;
        for (List<Object> row : rows) {
            if (text(row, 0) == appId && text(row, 3) != 'Canceled') {
                count++;
            }
        }
        return count;
    }

    // "Order PR-240828-PQYEQ89, ordered Aug 28, 2024, from Basil & Thyme Cafe, $65.60"
    public static String summary(OrderRow o) {
        String text = 'Order ' + o.orderId;
        if (o.createdAt != null) {
            text += ', ordered ' + o.createdAt.formatGmt('MMM d, yyyy');
        }
        if (String.isNotBlank(o.restaurant)) {
            text += ', from ' + o.restaurant;
        }
        if (o.total != null) {
            text += ', $' + o.total.setScale(2);
        }
        return text;
    }

    // "Herbal Tea $13.12; Side Salad $13.12; ...", the format log_order_issue matches against
    public static String lineItems(OrderRow o) {
        List<String> parts = new List<String>();
        for (Item i : o.items) {
            parts.add(i.name + ' $' + i.price.setScale(2));
        }
        return String.join(parts, '; ');
    }

    // Status words the customer sees in the Delivery FAQ (POL-F01)
    public static String faqStatus(String dataStatus) {
        switch on dataStatus {
            when 'Preparing' {
                return 'Accepted';
            }
            when 'PickedUp', 'Out for Delivery' {
                return 'Picked Up';
            }
            when 'Delivered' {
                return 'Delivered';
            }
            when 'Canceled' {
                return 'Canceled';
            }
            when else {
                return dataStatus;
            }
        }
    }

    // Accepts "PR-240828-PQYEQ89", "#pr-240828-pqyeq89" or "240828-PQYEQ89"; null when it is not a Pronto order number
    @TestVisible
    private static String normalizeOrderNumber(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        String s = raw.deleteWhitespace().toUpperCase().removeStart('#');
        if (!s.startsWith('PR-')) {
            s = 'PR-' + s;
        }
        return ORDER_NUMBER.matcher(s).matches() ? s : null;
    }

    private static String appAccountId(String contactId) {
        if (String.isBlank(contactId)) {
            return null;
        }
        try {
            List<Contact> contacts = [
                SELECT Pronto_App_Account_Id__c
                FROM Contact
                WHERE Id = :contactId
                WITH USER_MODE
                LIMIT 1
            ];
            return contacts.isEmpty() || String.isBlank(contacts[0].Pronto_App_Account_Id__c)
                ? null
                : contacts[0].Pronto_App_Account_Id__c;
        } catch (Exception e) {
            // Not a valid id, or no read access to the field
            return null;
        }
    }

    private static List<List<Object>> queryRows(String appId, String orderId) {
        if (Test.isRunningTest()) {
            if (mockQueryFails) {
                throw new OrderDataException('Data Cloud unavailable (test)');
            }
            return mockRows == null ? new List<List<Object>>() : mockRows;
        }
        ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
        // orderId already matched ORDER_NUMBER, so it holds no quote
        input.sql =
            'SELECT ' + COLUMNS + ' FROM Order__dlm ' +
            'WHERE Customer_ID__c = \'' + String.escapeSingleQuotes(appId) + '\'' +
            (orderId == '' ? '' : ' AND Order_ID__c = \'' + orderId + '\'') +
            ' ORDER BY Created_At__c DESC LIMIT 50';
        ConnectApi.CdpQueryOutputV2 output = ConnectApi.CdpQuery.queryAnsiSqlV2(input);
        List<List<Object>> rows = new List<List<Object>>();
        if (output != null && output.data != null) {
            for (ConnectApi.CdpQueryV2Row row : output.data) {
                rows.add(row.rowData);
            }
        }
        return rows;
    }

    private static OrderRow parse(List<Object> row) {
        OrderRow o = new OrderRow();
        o.orderId = text(row, 1);
        // Order_Date__c has day and month swapped in this data, so the order time is Created_At__c (D-074)
        o.createdAt = toDatetime(text(row, 2));
        o.status = text(row, 3);
        o.restaurant = text(row, 4);
        o.total = toDecimal(text(row, 5));
        o.items = priceItems(itemNames(text(row, 6)), o.total);
        Datetime eta = toDatetime(text(row, 7));
        Decimal etaMinutes = toDecimal(text(row, 8));
        // Some rows hold an estimate months after the order: then use order time + ETA minutes (D-074)
        if (o.createdAt != null && etaMinutes != null && (eta == null || eta > o.createdAt.addDays(1))) {
            eta = o.createdAt.addMinutes(etaMinutes.intValue());
        }
        o.estimatedDeliveryAt = eta;
        o.deliveredAt = toDatetime(text(row, 9));
        return o;
    }

    // "1x Iced Tea; Chips" -> [Iced Tea, Chips]: about 40 rows carry a quantity prefix (D-074)
    private static List<String> itemNames(String itemsOrdered) {
        List<String> names = new List<String>();
        if (String.isBlank(itemsOrdered)) {
            return names;
        }
        for (String raw : itemsOrdered.split(';')) {
            String name = raw.trim().replaceFirst('^[0-9]+\\s*[xX]\\s+', '');
            if (String.isNotBlank(name)) {
                names.add(name);
            }
        }
        return names;
    }

    // The data has no price per item: split the total evenly, the last item takes the rounding (D-072)
    private static List<Item> priceItems(List<String> names, Decimal total) {
        List<Item> items = new List<Item>();
        Integer n = names.size();
        if (n == 0) {
            return items;
        }
        Decimal orderTotal = total == null ? 0 : total.setScale(2);
        Decimal each = (orderTotal / n).setScale(2, System.RoundingMode.DOWN);
        for (Integer i = 0; i < n; i++) {
            Item item = new Item();
            item.name = names[i];
            item.price = i == n - 1 ? orderTotal - each * (n - 1) : each;
            items.add(item);
        }
        return items;
    }

    private static String text(List<Object> row, Integer position) {
        return row != null && row.size() > position && row[position] != null ? String.valueOf(row[position]).trim() : '';
    }

    // "2024-08-28 10:23:52.000 UTC" -> Datetime (GMT)
    private static Datetime toDatetime(String value) {
        if (String.isBlank(value) || value.length() < 19) {
            return null;
        }
        try {
            return Datetime.valueOfGmt(value.left(19));
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal toDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Decimal.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }
}
