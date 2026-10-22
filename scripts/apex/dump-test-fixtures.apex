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
// Issue cases as the Risk Flow counts them: last 30 days (risk_lookback_days), any Type but Refund / Compensation,
// and not the escalation Cases CARES opened itself (CARES_Escalation__c, D-082; Risk Flow v3)
Map<Id, Integer> issues = new Map<Id, Integer>();
Datetime windowStart = Datetime.now().addDays(-30);
for (AggregateResult a : [SELECT ContactId c, COUNT(Id) n FROM Case WHERE ContactId != null AND CreatedDate >= :windowStart AND (Type = null OR Type != 'Refund / Compensation') AND CARES_Escalation__c = false GROUP BY ContactId]) issues.put((Id) a.get('c'), (Integer) a.get('n'));
// Open customer context as CARES_Get_Customer_Context reads it (D-083): Has_Open_Context__c, last interaction in the window.
// The agent writes these rows itself on every saved rating, so a test contact can gain one
Set<Id> openContext = new Set<Id>();
for (CARES_Customer_Context__c x : [SELECT Contact__c FROM CARES_Customer_Context__c WHERE Has_Open_Context__c = true AND Last_Interaction_Date__c >= :windowStart]) openContext.add(x.Contact__c);
for (Contact c : [SELECT Id, Name, Email, CARES_Tier__r.Name, Pronto_App_Account_Id__c, AccountId FROM Contact WHERE Pronto_App_Account_Id__c != null]) {
    System.debug('FXC|' + c.Id + '|' + c.Name + '|' + c.Email + '|' + c.CARES_Tier__r?.Name + '|' + c.Pronto_App_Account_Id__c + '|' + (cases.containsKey(c.Id) ? cases.get(c.Id) : 0) + '|' + (issues.containsKey(c.Id) ? issues.get(c.Id) : 0) + '|' + (openContext.contains(c.Id) ? 1 : 0));
}
