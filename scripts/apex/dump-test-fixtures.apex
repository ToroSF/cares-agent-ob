// Dumps the demo orders (Order__dlm) and linked Contacts for the test fixtures.
// Read-only. Run: python3 scripts/testing/build_fixtures.py (it calls this file).
// Anonymous Apex runs in system mode, so it can read Contact.Pronto_App_Account_Id__c, which the CLI user cannot read through SOQL.
Integer total = 0;
for (Integer off = 0; off < 1200; off += 400) {
    ConnectApi.CdpQueryInput q = new ConnectApi.CdpQueryInput();
    q.sql = 'SELECT Customer_ID__c, Order_ID__c, Order_Status__c, Created_At__c, Total_Amount__c, Items_Ordered__c FROM Order__dlm ORDER BY Order_ID__c LIMIT 400 OFFSET ' + off;
    ConnectApi.CdpQueryOutputV2 o = ConnectApi.CdpQuery.queryAnsiSqlV2(q);
    if (o.data == null) break;
    for (ConnectApi.CdpQueryV2Row r : o.data) {
        System.debug('FXO|' + String.join(r.rowData, '|'));
        total++;
    }
}
System.debug('FXN|' + total);
Map<Id, Integer> cases = new Map<Id, Integer>();
for (AggregateResult a : [SELECT ContactId c, COUNT(Id) n FROM Case WHERE ContactId != null GROUP BY ContactId]) cases.put((Id) a.get('c'), (Integer) a.get('n'));
for (Contact c : [SELECT Id, Name, Email, CARES_Tier__r.Name, Pronto_App_Account_Id__c, AccountId FROM Contact WHERE Pronto_App_Account_Id__c != null]) {
    System.debug('FXC|' + c.Id + '|' + c.Name + '|' + c.Email + '|' + c.CARES_Tier__r?.Name + '|' + c.Pronto_App_Account_Id__c + '|' + (cases.containsKey(c.Id) ? cases.get(c.Id) : 0));
}
