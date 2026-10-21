/**
 * Runs the CARES_Create_Escalation_Case Flow: the fixed summary, the account,
 * the reason code and the chat link (D-085, G-082), and the reuse comment
 * (D-063). Reads use SYSTEM_MODE because the user running the tests has no
 * access to the CARES Case fields.
 */
@IsTest
private class CARES_EscalationCaseFlowTest {
  private static final String SESSION_ID = '0Mw000000000001AAA';

  @TestSetup
  static void setup() {
    Account a = new Account(Name = 'CARES Flow Test');
    insert a;
    insert new Contact(LastName = 'Flow Test', AccountId = a.Id);
  }

  private static Contact customer() {
    return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Flow Test'];
  }

  private static Flow.Interview run(Map<String, Object> inputs) {
    Flow.Interview f = Flow.Interview.createInterview(
      'CARES_Create_Escalation_Case',
      inputs
    );
    f.start();
    return f;
  }

  private static Map<String, Object> urgentFor(Id contactId) {
    return new Map<String, Object>{
      'contactId' => contactId,
      'channelContactId' => contactId,
      'escalationCategory' => 'URGENT',
      'escalationReason' => 'SAFETY',
      'sessionId' => SESSION_ID,
      'orderId' => 'PR-1001',
      'riskStatus' => 'CLEAN'
    };
  }

  @IsTest
  static void urgentCaseHasTheFullSummaryAndTheChat() {
    Contact c = customer();
    Flow.Interview f = run(urgentFor(c.Id));

    Assert.areEqual(true, f.getVariableValue('success'));
    Assert.areEqual(false, f.getVariableValue('reusedExisting'));
    Id caseId = (Id) f.getVariableValue('caseId');
    Case k = [
      SELECT
        CaseNumber,
        Description,
        Priority,
        Status,
        Origin,
        AccountId,
        ContactId,
        CARES_Order_Ref__c,
        CARES_Escalation_Reason__c,
        CARES_Messaging_Session_Id__c
      FROM Case
      WHERE Id = :caseId
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(k.CaseNumber, f.getVariableValue('caseNumber'));
    Assert.areEqual('High', k.Priority);
    Assert.areEqual('Escalated', k.Status);
    Assert.areEqual('Agentforce', k.Origin);
    Assert.areEqual(c.AccountId, k.AccountId, 'Account from the contact (G-082)');
    Assert.areEqual('PR-1001', k.CARES_Order_Ref__c);
    Assert.areEqual('SAFETY', k.CARES_Escalation_Reason__c);
    Assert.areEqual(SESSION_ID, k.CARES_Messaging_Session_Id__c);

    List<String> lines = k.Description.split('\\r?\\n');
    Assert.areEqual(12, lines.size(), 'One fact per line: ' + k.Description);
    Assert.isTrue(lines[0].startsWith('Escalated by CARES. Internal only'));
    Assert.areEqual('Category: URGENT', lines[1]);
    Assert.areEqual('Priority: High', lines[2]);
    Assert.areEqual(
      'Why: Safety, health, fraud or legal report (SAFETY)',
      lines[3]
    );
    Assert.areEqual('Customer: Verified (signed in to the chat)', lines[4]);
    Assert.areEqual('Order: PR-1001', lines[5]);
    Assert.areEqual('Stolen & Delayed check: not run', lines[6]);
    Assert.areEqual('Risk status (internal): CLEAN', lines[7]);
    Assert.areEqual('Offer: none made', lines[8]);
    Assert.areEqual('Customer chose: nothing confirmed', lines[9]);
    Assert.isTrue(lines[10].contains(SESSION_ID));
    Assert.isTrue(lines[11].startsWith('Next step: Contact the customer now'));
  }

  @IsTest
  static void secondEscalationForTheSameIssueAddsAComment() {
    Contact c = customer();
    Flow.Interview first = run(urgentFor(c.Id));
    Map<String, Object> again = urgentFor(c.Id);
    again.put('sessionId', null);
    Flow.Interview second = run(again);

    Assert.areEqual(true, second.getVariableValue('reusedExisting'));
    Assert.areEqual(
      first.getVariableValue('caseNumber'),
      second.getVariableValue('caseNumber')
    );
    Assert.areEqual(
      first.getVariableValue('caseId'),
      second.getVariableValue('caseId')
    );
    Assert.areEqual(1, [SELECT COUNT() FROM Case WHERE ContactId = :c.Id WITH SYSTEM_MODE]);
    CaseComment cc = [
      SELECT CommentBody, IsPublished
      FROM CaseComment
      WHERE ParentId = :(Id) first.getVariableValue('caseId')
      WITH SYSTEM_MODE
    ];
    Assert.isFalse(cc.IsPublished, 'The summary is internal');
    Assert.isTrue(cc.CommentBody.contains('Why: Safety'));
  }

  @IsTest
  static void customerFoundByEmailAndOfferAreLabelled() {
    Contact c = customer();
    Flow.Interview f = run(
      new Map<String, Object>{
        'contactId' => c.Id,
        'escalationReason' => 'OFFER_DISPUTED',
        'orderId' => 'PR-2002',
        'offerAmount' => 5,
        'creditAmount' => 7.5,
        'currencyCode' => 'USD',
        'chosenResolution' => 'Refund',
        'stolenDelayedDecision' => 'MANUAL_REVIEW',
        'stolenDelayedReason' => 'LOW_TRUST_CUSTOMER'
      }
    );
    String d = [
      SELECT Description
      FROM Case
      WHERE Id = :(Id) f.getVariableValue('caseId')
      WITH SYSTEM_MODE
    ]
    .Description;
    Assert.isTrue(d.contains('Category: GENERAL'));
    Assert.isTrue(d.contains('Priority: Medium'));
    Assert.isTrue(d.contains('(OFFER_DISPUTED)'));
    Assert.isTrue(d.contains('Customer: Found by email'));
    Assert.isTrue(d.contains('Offer: refund 5'));
    Assert.isTrue(d.contains('USD'));
    Assert.isTrue(d.contains('Customer chose: Refund'));
    Assert.isTrue(
      d.contains('Stolen & Delayed check: MANUAL_REVIEW (LOW_TRUST_CUSTOMER)')
    );
    Assert.isTrue(d.contains('Chat: none (not a live chat'));
  }

  @IsTest
  static void unknownCustomerStillGetsACase() {
    Flow.Interview f = run(
      new Map<String, Object>{ 'escalationCategory' => 'URGENT' }
    );
    Assert.areEqual(true, f.getVariableValue('success'));
    Case k = [
      SELECT Description, ContactId, CARES_Escalation_Reason__c, CARES_Order_Ref__c
      FROM Case
      WHERE Id = :(Id) f.getVariableValue('caseId')
      WITH SYSTEM_MODE
    ];
    Assert.isNull(k.ContactId);
    Assert.areEqual('NOT_GIVEN', k.CARES_Escalation_Reason__c, 'Older agent versions send no reason');
    Assert.areEqual('NONE', k.CARES_Order_Ref__c);
    Assert.isTrue(k.Description.contains('Customer: Unknown'));
  }
}
