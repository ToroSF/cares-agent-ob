@IsTest
private class CARES_EscalationAlertsTest {
  private class SlackMock implements HttpCalloutMock {
    Integer statusCode = 200;
    String body = '{"ok":true}';
    Boolean fail = false;
    final List<HttpRequest> requests = new List<HttpRequest>();

    public HttpResponse respond(HttpRequest req) {
      requests.add(req);
      if (fail) {
        throw new CalloutException('Read timed out');
      }
      HttpResponse res = new HttpResponse();
      res.setStatusCode(statusCode);
      res.setBody(body);
      return res;
    }
  }

  private static SlackMock mock(String mode) {
    CARES_EscalationAlerts.Settings s = new CARES_EscalationAlerts.Settings();
    s.slackMode = mode;
    s.slackChannel = 'C0TEST';
    CARES_EscalationAlerts.settingsOverride = s;
    SlackMock m = new SlackMock();
    Test.setMock(HttpCalloutMock.class, m);
    return m;
  }

  private static Case escalate(String priority, String sessionId) {
    Case c = new Case(
      Subject = 'CARES urgent escalation: safety or fraud',
      Description = 'Customer: Jane Private, jane@example.com',
      Origin = 'Agentforce',
      CARES_Escalation__c = true,
      Priority = priority,
      CARES_Order_Ref__c = 'PR-1001',
      CARES_Escalation_Reason__c = 'SAFETY',
      CARES_Messaging_Session_Id__c = sessionId
    );
    Test.startTest();
    // The test user has no access to the new fields, like the agent user
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    Test.stopTest();
    return [
      SELECT Id, CaseNumber, CARES_Alert_Status__c
      FROM Case
      WHERE Id = :c.Id
      WITH SYSTEM_MODE
    ];
  }

  @IsTest
  static void urgentCaseRingsTheBellAndPostsToSlackWithHere() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_BOT);
    Case c = escalate('High', '0Mw000000000001AAA');

    Assert.areEqual('Bell: Sent | Slack: Sent', c.CARES_Alert_Status__c);
    Assert.areEqual(1, m.requests.size());
    HttpRequest req = m.requests[0];
    Assert.areEqual('callout:CARES_Slack/chat.postMessage', req.getEndpoint());
    String body = req.getBody();
    Assert.isTrue(body.contains('<!here>'), 'URGENT calls the channel');
    Assert.isTrue(body.contains(':red_circle:'));
    Assert.isTrue(body.contains(c.CaseNumber));
    Assert.isTrue(body.contains('C0TEST'));
    Assert.isTrue(body.contains('Open conversation'), 'Live chat gets a link');
  }

  // The job runs as the agent user that logged the case. Live, its first run
  // failed on the notification type lookup, which the admin runner never sees
  @IsTest
  static void agentProfileJobRingsTheBell() {
    mock(CARES_EscalationAlerts.MODE_OFF);
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Einstein Agent User' LIMIT 1];
    User u = new User(
      Alias = 'escag',
      Email = 'esc.agent@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Escalation Agent',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'esc.agent.' + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'CARES_Escalation_Access' LIMIT 1];
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    Case c = new Case(Subject = 'CARES escalation', Origin = 'Agentforce', Priority = 'Medium');
    Database.insert(c, AccessLevel.SYSTEM_MODE);

    System.runAs(u) {
      Test.startTest();
      System.enqueueJob(new CARES_EscalationAlerts(new List<Id>{ c.Id }));
      Test.stopTest();
    }
    c = [SELECT CARES_Alert_Status__c FROM Case WHERE Id = :c.Id WITH SYSTEM_MODE];
    Assert.areEqual('Bell: Sent | Slack: Off', c.CARES_Alert_Status__c);
  }

  @IsTest
  static void slackGetsNoPersonalData() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_BOT);
    escalate('High', null);
    String body = m.requests[0].getBody();
    Assert.isFalse(body.contains('Jane'), 'No name in Slack (D-087)');
    Assert.isFalse(body.contains('jane@example.com'), 'No email in Slack');
    Assert.isFalse(body.containsIgnoreCase('risk'), 'No risk status in Slack');
    Assert.isFalse(body.contains('Open conversation'), 'No chat, no link');
  }

  @IsTest
  static void normalCaseIsYellowWithoutHere() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_BOT);
    escalate('Medium', null);
    String body = m.requests[0].getBody();
    Assert.isFalse(body.contains('<!here>'));
    Assert.isTrue(body.contains(':large_yellow_circle:'));
  }

  @IsTest
  static void slackHttpErrorIsRecordedAndTheBellStillRings() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_BOT);
    m.statusCode = 404;
    Case c = escalate('High', null);
    Assert.areEqual('Bell: Sent | Slack: Failed: HTTP 404', c.CARES_Alert_Status__c);
  }

  @IsTest
  static void slackApiErrorIsRecorded() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_BOT);
    m.body = '{"ok":false,"error":"not_in_channel"}';
    Case c = escalate('High', null);
    Assert.areEqual(
      'Bell: Sent | Slack: Failed: not_in_channel',
      c.CARES_Alert_Status__c
    );
  }

  @IsTest
  static void slackTimeoutIsRecorded() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_BOT);
    m.fail = true;
    Case c = escalate('High', null);
    Assert.areEqual(
      'Bell: Sent | Slack: Failed: System.CalloutException',
      c.CARES_Alert_Status__c
    );
  }

  @IsTest
  static void workflowModeSendsFlatVariables() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_WORKFLOW);
    m.body = '';
    Case c = escalate('High', null);
    Assert.areEqual('Bell: Sent | Slack: Sent', c.CARES_Alert_Status__c);
    Assert.areEqual('callout:CARES_Slack', m.requests[0].getEndpoint());
    Map<String, Object> vars = (Map<String, Object>) JSON.deserializeUntyped(
      m.requests[0].getBody()
    );
    Assert.areEqual(c.CaseNumber, vars.get('case_number'));
    Assert.areEqual('yes', vars.get('urgent'));
    Assert.areEqual('SAFETY', vars.get('reason'));
    Assert.isFalse(vars.containsKey('blocks'));
  }

  @IsTest
  static void slackOffMakesNoCallout() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_OFF);
    Case c = escalate('High', null);
    Assert.areEqual('Bell: Sent | Slack: Off', c.CARES_Alert_Status__c);
    Assert.areEqual(0, m.requests.size());
  }

  @IsTest
  static void botModeWithoutChannelFailsWithoutCallout() {
    SlackMock m = mock(CARES_EscalationAlerts.MODE_BOT);
    CARES_EscalationAlerts.settingsOverride.slackChannel = '';
    Case c = escalate('High', null);
    Assert.areEqual('Bell: Sent | Slack: Failed: no channel', c.CARES_Alert_Status__c);
    Assert.areEqual(0, m.requests.size());
  }

  @IsTest
  static void otherCasesGetNoAlert() {
    mock(CARES_EscalationAlerts.MODE_BOT);
    Test.startTest();
    Database.insert(
      new List<Case>{
        new Case(Subject = 'Web case', Origin = 'Web', CARES_Order_Ref__c = 'PR-1'),
        new Case(Subject = 'Agent case', Origin = 'Agentforce', CARES_Order_Ref__c = 'PR-2')
      },
      AccessLevel.SYSTEM_MODE
    );
    Assert.areEqual(0, Limits.getQueueableJobs(), 'Only CARES escalation cases');
    Test.stopTest();
  }

  @IsTest
  static void settingsLoadWithoutError() {
    CARES_EscalationAlerts.Settings s = CARES_EscalationAlerts.loadSettings();
    Assert.isNotNull(s.slackMode);
  }
}
