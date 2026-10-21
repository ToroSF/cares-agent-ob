public with sharing class CARES_Refund_LogOrderIssue {
    private static final Set<String> ITEM_TYPES = new Set<String>{ 'Wrong_Missing_Items', 'Quality_Issue' };
    private static final Set<String> DELIVERY_TYPES = new Set<String>{ 'Stolen', 'Delayed' };

    public class Request {
        @InvocableVariable(
            label='Contact ID'
            description='Customer Contact ID from the messaging channel, never from the chat; needed to value the items'
        )
        public String contactId;
        @InvocableVariable(
            label='Order ID'
            description='Delivery platform order id, the same id Stolen & Delayed Orders uses'
            required=true
        )
        public String orderId;
        @InvocableVariable(
            label='Issue Type'
            description='Wrong_Missing_Items or Quality_Issue; Stolen or Delayed only on the Stolen & Delayed standard path'
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
            description='Names of the order items that were wrong, missing, or bad quality; blank for Stolen or Delayed'
        )
        public String affectedItems;
        @InvocableVariable(
            label='Delivery Path'
            description='STANDARD when the order came from the Stolen & Delayed standard path, otherwise blank'
        )
        public String deliveryPath;
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
        // The affected items are valued from the customer's real order (D-071, D-072), read again
        // here so the value never comes from the chat. An item not on that order is rejected (G-023).
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            Boolean deliveryIssue = req.deliveryPath == 'STANDARD' && DELIVERY_TYPES.contains(req.issueType);
            if (deliveryIssue) {
                r.accepted = true;
                r.orderOutcome = req.issueType;
                r.affectedValue = 0;
                results.add(r);
                continue;
            }
            if (ITEM_TYPES.contains(req.issueType)) {
                Decimal matchedValue = matchAffectedItems(req.contactId, req.orderId, req.affectedItems);
                r.accepted = matchedValue != null;
                r.orderOutcome = r.accepted ? req.issueType : '';
                r.affectedValue = r.accepted ? matchedValue : 0;
                results.add(r);
                continue;
            }
            r.accepted = false;
            r.orderOutcome = '';
            r.affectedValue = 0;
            results.add(r);
        }
        return results;
    }

    // Returns the summed price of every named item when all of them are on the
    // customer's order; null when the list is blank, the order is not theirs, or
    // any name doesn't match (reject rather than accept an unlisted item at a guessed value).
    private static Decimal matchAffectedItems(String contactId, String orderId, String affectedItems) {
        if (String.isBlank(affectedItems) || String.isBlank(orderId)) {
            return null;
        }
        CARES_OrderData.Lookup lookup = CARES_OrderData.find(contactId, orderId, true);
        if (!lookup.found) {
            return null;
        }
        Map<String, Decimal> pricesByLowerName = new Map<String, Decimal>();
        for (CARES_OrderData.Item item : lookup.order.items) {
            pricesByLowerName.put(item.name.toLowerCase(), item.price);
        }
        Decimal total = 0;
        for (String rawName : affectedItems.split('[,;]')) {
            // The model may copy the price from the item list: "Iced Tea $13.12"
            String name = rawName.trim().replaceFirst('\\s*\\$[0-9.]+$', '');
            if (String.isBlank(name)) {
                continue;
            }
            Decimal price = pricesByLowerName.get(name.toLowerCase());
            if (price == null) {
                return null;
            }
            total += price;
        }
        return total == 0 ? null : total;
    }
}
