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
            description='Delivery platform order id, the same id Stolen & Delayed Orders uses'
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
        @InvocableVariable(
            label='Currency Code'
            description='ISO currency code of the amounts; blank means the org default currency'
        )
        public String currencyCode;
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
        // Writes a real CARES_Resolution__c row per issued resolution (closes the
        // Refund part of G-024/G-008: no refund audit trail). Checks for an
        // existing row for the same orderId first, so a duplicate comes back as a
        // clean ineligible-style result instead of a DML unique-field exception.
        List<Result> results = new List<Result>();
        Set<Id> contactIds = new Set<Id>();
        Set<String> orderIds = new Set<String>();
        for (Request req : requests) {
            Id contactId = toId(req.contactId);
            if (contactId != null) {
                contactIds.add(contactId);
            }
            if (String.isNotBlank(req.orderId)) {
                orderIds.add(req.orderId);
            }
        }

        Map<Id, Contact> contactsById = new Map<Id, Contact>();
        if (!contactIds.isEmpty()) {
            contactsById = new Map<Id, Contact>(
                [SELECT Id FROM Contact WHERE Id IN :contactIds WITH USER_MODE]
            );
        }

        Set<String> orderIdsAlreadyResolved = new Set<String>();
        if (!orderIds.isEmpty()) {
            for (
                CARES_Resolution__c existing : [
                    SELECT Order_Id__c
                    FROM CARES_Resolution__c
                    WHERE Order_Id__c IN :orderIds
                    WITH USER_MODE
                ]
            ) {
                orderIdsAlreadyResolved.add(existing.Order_Id__c);
            }
        }

        List<CARES_Resolution__c> resolutionsToInsert = new List<CARES_Resolution__c>();
        List<Integer> insertPositions = new List<Integer>();
        // Guards a duplicate order id within this same invocation batch, since the
        // pre-insert SOQL above only sees rows already committed to the database.
        Set<String> orderIdsClaimedInThisBatch = new Set<String>();

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            results.add(null);

            if (String.isBlank(req.orderId)) {
                results[i] = failureResult('Order id is required.');
                continue;
            }
            Id contactId = toId(req.contactId);
            Contact relatedContact = contactId == null ? null : contactsById.get(contactId);
            if (relatedContact == null) {
                results[i] = failureResult('Contact not found: ' + req.contactId);
                continue;
            }
            if (orderIdsAlreadyResolved.contains(req.orderId) || orderIdsClaimedInThisBatch.contains(req.orderId)) {
                results[i] = failureResult('This order already has a resolution on file.');
                continue;
            }
            if (req.resolutionType != 'Refund' && req.resolutionType != 'Store_Credit') {
                results[i] = failureResult('Resolution type must be Refund or Store_Credit.');
                continue;
            }

            Boolean isCredit = req.resolutionType == 'Store_Credit';
            Decimal amount = isCredit ? req.creditAmount : req.refundAmount;
            if (amount == null) {
                results[i] = failureResult('Amount is required.');
                continue;
            }

            CARES_Resolution__c resolution = new CARES_Resolution__c();
            resolution.Contact__c = relatedContact.Id;
            resolution.Order_Id__c = req.orderId;
            resolution.Resolution_Type__c = req.resolutionType;
            resolution.Amount__c = amount;
            resolution.Status__c = 'Issued';

            resolutionsToInsert.add(resolution);
            insertPositions.add(i);
            orderIdsClaimedInThisBatch.add(req.orderId);
        }

        if (!resolutionsToInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(resolutionsToInsert, false, AccessLevel.USER_MODE);
            for (Integer j = 0; j < saveResults.size(); j++) {
                Integer position = insertPositions[j];
                Request req = requests[position];
                Database.SaveResult saveResult = saveResults[j];
                if (saveResult.isSuccess()) {
                    Result r = new Result();
                    r.success = true;
                    r.referenceNumber = resolutionsToInsert[j].Id;
                    // No timing promise: no Pronto source gives a refund window (D-065)
                    String currencyLabel = String.isBlank(req.currencyCode) ? UserInfo.getDefaultCurrency() : req.currencyCode;
                    r.message = req.resolutionType == 'Store_Credit'
                        ? 'Store credit of ' + req.creditAmount.setScale(2) + ' ' + currencyLabel + ' has been added to your account.'
                        : 'Refund of ' + req.refundAmount.setScale(2) + ' ' + currencyLabel + ' to your original payment method.';
                    results[position] = r;
                } else {
                    // A unique-field collision lands here when two requests in this
                    // call raced past the in-batch check (shouldn't happen given the
                    // Set guard above, but DML errors of any kind must stay a clean
                    // result, never an uncaught exception).
                    results[position] = failureResult('This order already has a resolution on file.');
                }
            }
        }

        return results;
    }

    private static Result failureResult(String message) {
        Result r = new Result();
        r.success = false;
        r.referenceNumber = '';
        r.message = message;
        return r;
    }

    // Blank or malformed ids become null instead of throwing
    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (StringException e) {
            return null;
        }
    }
}
