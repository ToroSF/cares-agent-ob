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
        @InvocableVariable(
            label='Already Resolved'
            description='True when the order already has a refund or credit on file; no offer is made'
        )
        public Boolean alreadyResolved;
    }
    @InvocableMethod(
        label='CARES Refund Calculate Offer'
        description='Calculates the refund and store credit offer from tier, order outcome and risk status'
    )
    public static List<Result> execute(List<Request> requests) {
        // The order value comes from the real orders (find_order / log_order_issue,
        // D-071, D-072). The limits come from Contact.CARES_Tier__c and
        // CARES_Refund_Policy__c (D-024, D-025, D-029).
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

        // One resolution per order (D-024): an order with a resolution gets no offer, on any path (G-091, D-088)
        Set<String> resolvedOrderIds = new Set<String>();
        if (!orderIds.isEmpty()) {
            for (CARES_Resolution__c res : [
                SELECT Order_Id__c
                FROM CARES_Resolution__c
                WHERE Order_Id__c IN :orderIds
                WITH USER_MODE
            ]) {
                resolvedOrderIds.add(res.Order_Id__c);
            }
        }

        Map<Id, Contact> contactsById = new Map<Id, Contact>();
        if (!contactIds.isEmpty()) {
            contactsById = new Map<Id, Contact>(
                [
                    SELECT Id, CARES_Tier__c, CARES_Tier__r.Name, CARES_Tier__r.Active__c
                    FROM Contact
                    WHERE Id IN :contactIds
                    WITH USER_MODE
                ]
            );
        }

        CARES_Tier__c lowestActiveTier = lowestActiveTier();

        Map<String, CARES_Refund_Policy__c> policiesByKey = policiesByTierAndOutcome();

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(calculateOne(req, contactsById, lowestActiveTier, policiesByKey, resolvedOrderIds));
        }
        return results;
    }

    private static Result calculateOne(
        Request req,
        Map<Id, Contact> contactsById,
        CARES_Tier__c lowestActiveTier,
        Map<String, CARES_Refund_Policy__c> policiesByKey,
        Set<String> resolvedOrderIds
    ) {
        Result r = new Result();
        r.currencyCode = String.isBlank(req.orderCurrency) ? UserInfo.getDefaultCurrency() : req.orderCurrency;
        r.alreadyResolved = false;
        if (String.isNotBlank(req.orderId) && resolvedOrderIds.contains(req.orderId)) {
            r.alreadyResolved = true;
            r.eligible = false;
            r.ineligibleReason = 'This order already has a refund or credit on file, so I can\'t offer another one. A team member can check it if something looks wrong.';
            r.refundAmount = 0;
            r.creditAmount = 0;
            r.tierName = '';
            return r;
        }

        CARES_Tier__c tier = resolveTier(req.contactId, contactsById, lowestActiveTier);
        r.tierName = tier == null ? '' : tier.Name;

        Decimal approvedFullAmount = req.approvedFullAmount == null ? 0 : req.approvedFullAmount;
        Boolean readyPath = approvedFullAmount > 0;

        Decimal refund;
        Decimal bonusPercent = 0;
        if (readyPath) {
            // READY path: refund = the approved full amount, no policy ceiling applied (per the node spec).
            refund = approvedFullAmount;
            // Credit bonus from the customer's tier row for this outcome (D-029). No row means no bonus, never an invented one
            CARES_Refund_Policy__c readyPolicy = tier == null ? null : policiesByKey.get(policyKey(tier.Id, req.orderOutcome));
            if (readyPolicy != null && readyPolicy.Store_Credit_Bonus_Pct__c != null) {
                bonusPercent = readyPolicy.Store_Credit_Bonus_Pct__c;
            }
        } else {
            if (tier == null) {
                r.eligible = false;
                r.ineligibleReason = 'We could not confirm your account tier, so we could not calculate an offer. A team member will take it from here.';
                r.refundAmount = 0;
                r.creditAmount = 0;
                return r;
            }
            CARES_Refund_Policy__c policy = policiesByKey.get(policyKey(tier.Id, req.orderOutcome));
            if (policy == null) {
                r.eligible = false;
                r.ineligibleReason = 'We do not have an active refund policy for this situation. A team member will take it from here.';
                r.refundAmount = 0;
                r.creditAmount = 0;
                return r;
            }
            Decimal ceiling = req.riskStatus == 'CLEAN' ? policy.Clean_History_Max_Refund__c : policy.Max_Refund__c;
            Decimal affectedValue = req.affectedValue == null ? 0 : req.affectedValue;
            refund = affectedValue < ceiling ? affectedValue : ceiling;
            bonusPercent = policy.Store_Credit_Bonus_Pct__c;
        }

        if (req.orderTotalCap != null && req.orderTotalCap > 0 && refund > req.orderTotalCap) {
            refund = req.orderTotalCap;
        }

        r.eligible = true;
        r.ineligibleReason = '';
        r.refundAmount = refund.setScale(2);
        r.creditAmount = (refund * (1 + bonusPercent / 100)).setScale(2);
        return r;
    }

    private static CARES_Tier__c resolveTier(
        String contactIdString,
        Map<Id, Contact> contactsById,
        CARES_Tier__c lowestActiveTier
    ) {
        Id contactId = toId(contactIdString);
        Contact c = contactId == null ? null : contactsById.get(contactId);
        if (c != null && c.CARES_Tier__c != null && c.CARES_Tier__r.Active__c == true) {
            CARES_Tier__c t = new CARES_Tier__c(Id = c.CARES_Tier__c, Name = c.CARES_Tier__r.Name);
            return t;
        }
        return lowestActiveTier;
    }

    private static CARES_Tier__c lowestActiveTier() {
        List<CARES_Tier__c> tiers = [
            SELECT Id, Name, Rank__c
            FROM CARES_Tier__c
            WHERE Active__c = true
            WITH USER_MODE
            ORDER BY Rank__c ASC
            LIMIT 1
        ];
        return tiers.isEmpty() ? null : tiers[0];
    }

    private static Map<String, CARES_Refund_Policy__c> policiesByTierAndOutcome() {
        Map<String, CARES_Refund_Policy__c> result = new Map<String, CARES_Refund_Policy__c>();
        for (
            CARES_Refund_Policy__c p : [
                SELECT Tier__c, Order_Outcome__c, Max_Refund__c, Clean_History_Max_Refund__c, Store_Credit_Bonus_Pct__c
                FROM CARES_Refund_Policy__c
                WHERE Active__c = true
                WITH USER_MODE
            ]
        ) {
            result.put(policyKey(p.Tier__c, p.Order_Outcome__c), p);
        }
        return result;
    }

    private static String policyKey(Id tierId, String orderOutcome) {
        return String.valueOf(tierId) + '::' + orderOutcome;
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
