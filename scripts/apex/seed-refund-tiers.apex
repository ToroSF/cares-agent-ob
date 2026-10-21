// Seed Refund tiers and policy rows, and set each customer's tier from order history (D-073, R-17).
// Run once after CARES_Tier__c, CARES_Refund_Policy__c and Contact.CARES_Tier__c are deployed:
//   sf apex run --file scripts/apex/seed-refund-tiers.apex --target-org <team org>
// Safe to run again: tiers are matched by Name and policy rows by tier + outcome, then updated.
// Set DRY_RUN = true to print what would change without writing.
//
// All amounts, percentages and spend limits are team assumptions [$] (D-065), not Pronto policy.
// Owner of the values: the Refund owner. Change them here or directly on the rows in Setup.
//
// The person who runs it needs the CARES_Refund_Policy_Admin permission set: anonymous Apex
// checks field access when it compiles, and SYSTEM_MODE is not allowed in anonymous Apex.

Boolean DRY_RUN = false;

// Tier name => rank (1 = lowest; a blank or inactive tier falls back to the lowest active tier, D-047)
Map<String, Integer> TIER_RANKS = new Map<String, Integer>{
    'Explorer' => 1,
    'Insider' => 2,
    'Pronto Plus' => 3
};

// Tier name => [Max_Refund__c, Clean_History_Max_Refund__c, Store_Credit_Bonus_Pct__c]   [$]
Map<String, List<Decimal>> POLICY_VALUES = new Map<String, List<Decimal>>{
    'Explorer' => new List<Decimal>{ 25, 35, 10 },
    'Insider' => new List<Decimal>{ 40, 55, 15 },
    'Pronto Plus' => new List<Decimal>{ 60, 80, 20 }
};

List<String> OUTCOMES = new List<String>{ 'Stolen', 'Delayed', 'Wrong_Missing_Items', 'Quality_Issue' };

// Spend of non-canceled orders (Data Cloud Order__dlm) => tier. [$]
// Measured on 2026-10-21: 187 customers, average spend about 230 (4 orders) to 350 (6 orders).
// With these limits: Explorer 26, Insider 130, Pronto Plus 31.
Decimal INSIDER_MIN_SPEND = 250;
Decimal PRONTO_PLUS_MIN_SPEND = 350;

// 1. Tiers
Set<String> tierNames = TIER_RANKS.keySet();
Map<String, CARES_Tier__c> tiersByName = new Map<String, CARES_Tier__c>();
for (CARES_Tier__c t : [SELECT Id, Name FROM CARES_Tier__c WHERE Name IN :tierNames]) {
    tiersByName.put(t.Name, t);
}
for (String name : tierNames) {
    CARES_Tier__c t = tiersByName.containsKey(name) ? tiersByName.get(name) : new CARES_Tier__c();
    t.Name = name;
    t.Rank__c = TIER_RANKS.get(name);
    t.Active__c = true;
    tiersByName.put(name, t);
}
if (!DRY_RUN) {
    upsert tiersByName.values();
}
System.debug('SEED tiers: ' + tierNames);

// 1b. Retention bonus (D-083, mock data for this project): a modest flat 5% on every tier,
// applied by CARES_Refund_CalculateOffer only when Risk Detection signals a genuinely frustrated
// customer who is not already NOT_CLEAN by pattern. Same [$] disclosure as everything else here.
Decimal RETENTION_BONUS_PCT = 5;

// 2. Policy rows: one per tier and outcome
Map<String, CARES_Refund_Policy__c> policiesByKey = new Map<String, CARES_Refund_Policy__c>();
List<CARES_Tier__c> savedTiers = tiersByName.values();
for (CARES_Refund_Policy__c p : [
    SELECT Id, Tier__c, Order_Outcome__c
    FROM CARES_Refund_Policy__c
    WHERE Tier__c IN :savedTiers
]) {
    policiesByKey.put(p.Tier__c + '::' + p.Order_Outcome__c, p);
}
for (String name : tierNames) {
    CARES_Tier__c t = tiersByName.get(name);
    List<Decimal> v = POLICY_VALUES.get(name);
    for (String outcome : OUTCOMES) {
        String key = (t.Id != null ? String.valueOf(t.Id) : name) + '::' + outcome;
        CARES_Refund_Policy__c p = policiesByKey.get(key);
        if (p == null) {
            p = new CARES_Refund_Policy__c(Name = name + ' - ' + outcome, Tier__c = t.Id, Order_Outcome__c = outcome);
        }
        p.Max_Refund__c = v[0];
        p.Clean_History_Max_Refund__c = v[1];
        p.Store_Credit_Bonus_Pct__c = v[2];
        p.Retention_Bonus_Pct__c = RETENTION_BONUS_PCT;
        p.Active__c = true;
        policiesByKey.put(key, p);
    }
}
if (!DRY_RUN) {
    upsert policiesByKey.values();
}
System.debug('SEED policy rows: ' + policiesByKey.size());

// 3. Customer tier from order spend in Data Cloud
ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
input.sql =
    'SELECT Customer_ID__c, SUM(Total_Amount__c) FROM Order__dlm ' +
    'WHERE Order_Status__c <> \'Canceled\' GROUP BY Customer_ID__c';
ConnectApi.CdpQueryOutputV2 output = ConnectApi.CdpQuery.queryAnsiSqlV2(input);
Map<String, Decimal> spendByCustomer = new Map<String, Decimal>();
for (ConnectApi.CdpQueryV2Row row : output.data) {
    if (row.rowData[0] != null && row.rowData[1] != null) {
        spendByCustomer.put(String.valueOf(row.rowData[0]), Decimal.valueOf(String.valueOf(row.rowData[1])));
    }
}

Set<String> customerIds = spendByCustomer.keySet();
List<Contact> toUpdate = new List<Contact>();
Map<String, Integer> countByTier = new Map<String, Integer>();
for (Contact c : [
    SELECT Id, Pronto_App_Account_Id__c, CARES_Tier__c
    FROM Contact
    WHERE Pronto_App_Account_Id__c IN :customerIds
]) {
    Decimal spend = spendByCustomer.get(c.Pronto_App_Account_Id__c);
    String tierName = spend >= PRONTO_PLUS_MIN_SPEND ? 'Pronto Plus' : spend >= INSIDER_MIN_SPEND ? 'Insider' : 'Explorer';
    countByTier.put(tierName, (countByTier.containsKey(tierName) ? countByTier.get(tierName) : 0) + 1);
    Id tierId = tiersByName.get(tierName).Id;
    if (tierId != null && c.CARES_Tier__c != tierId) {
        toUpdate.add(new Contact(Id = c.Id, CARES_Tier__c = tierId));
    }
}
if (!DRY_RUN) {
    update toUpdate;
}
System.debug(
    'SEED customers with orders: ' + spendByCustomer.size() + '; tiers: ' + countByTier +
    '; contacts updated: ' + toUpdate.size() + (DRY_RUN ? ' (dry run)' : '')
);
