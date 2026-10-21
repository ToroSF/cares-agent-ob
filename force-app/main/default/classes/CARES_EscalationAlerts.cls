/**
 * Escalate to Human: tells the support team about a new CARES escalation case
 * (D-086). Two layers, and one failing does not stop the other:
 *   1. Bell: a Salesforce notification (desktop and mobile push) to the
 *      CARES Support Team group.
 *   2. Slack: one message through the CARES_Slack Named Credential, when the
 *      Default record of CARES_Alert_Setting__mdt turns it on.
 * It runs after the case is saved, so an alert can never change the reply to
 * the customer. Slack gets no personal data and no risk status, only the case
 * number, reason code, order ref, priority and links (D-087).
 * The result of each layer is written to Case.CARES_Alert_Status__c.
 *
 * Without sharing and in system mode: the job reads and stamps cases owned by a
 * queue, and the agent user that triggers it has no Edit on Case and no access
 * to the alert fields. It only touches CARES escalation cases.
 */
public without sharing class CARES_EscalationAlerts implements Queueable, Database.AllowsCallouts {
  public static final String MODE_OFF = 'OFF';
  public static final String MODE_BOT = 'BOT';
  public static final String MODE_WORKFLOW = 'WORKFLOW';

  @TestVisible
  private static final String NOTIFICATION_TYPE = 'CARES_Escalation_Alert';
  @TestVisible
  private static final String SUPPORT_GROUP = 'CARES_Support_Team';
  // A burst of cases (a data load) must not use up the callout limit.
  @TestVisible
  private static final Integer MAX_CASES_PER_JOB = 20;

  public class Settings {
    public String slackMode = MODE_OFF;
    public String slackChannel;
    public Boolean bellEnabled = true;
  }

  @TestVisible
  private static Settings settingsOverride;

  private final List<Id> caseIds;
  // Read when the job is queued, so the job uses the setting of that moment.
  private final Settings settings;

  public CARES_EscalationAlerts(List<Id> caseIds) {
    this.caseIds = caseIds;
    this.settings = loadSettings();
  }

  /** Called by the Case trigger after insert. Never throws: the case must save. */
  public static void enqueueFor(List<Case> cases) {
    List<Id> ids = new List<Id>();
    for (Case c : cases) {
      if (isCaresEscalation(c)) {
        ids.add(c.Id);
      }
    }
    if (ids.isEmpty()) {
      return;
    }
    try {
      System.enqueueJob(new CARES_EscalationAlerts(ids));
    } catch (Exception e) {
      // No alert, but the case is in the queue. The blank status shows it.
      System.debug(
        LoggingLevel.ERROR,
        'CARES alert not queued: ' + e.getMessage()
      );
    }
  }

  /** Only cases logged by the CARES_Create_Escalation_Case Flow (the D-082 marker). */
  @TestVisible
  private static Boolean isCaresEscalation(Case c) {
    return c.CARES_Escalation__c == true;
  }

  public static Settings loadSettings() {
    if (settingsOverride != null) {
      return settingsOverride;
    }
    Settings s = new Settings();
    CARES_Alert_Setting__mdt r = CARES_Alert_Setting__mdt.getInstance(
      'Default'
    );
    if (r == null) {
      return s;
    }
    if (String.isNotBlank(r.Slack_Mode__c)) {
      s.slackMode = r.Slack_Mode__c.trim().toUpperCase();
    }
    s.slackChannel = r.Slack_Channel__c;
    s.bellEnabled = r.Bell_Enabled__c == true;
    return s;
  }

  public void execute(QueueableContext context) {
    List<Case> cases = [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Priority,
        CARES_Escalation_Reason__c,
        CARES_Order_Ref__c,
        CARES_Messaging_Session_Id__c
      FROM Case
      WHERE Id IN :caseIds
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
    ];
    Map<Id, String> slack = new Map<Id, String>();
    Map<Id, String> bell = new Map<Id, String>();
    // Callouts first: a callout is not allowed after pending work in the same job.
    for (Integer i = 0; i < cases.size(); i++) {
      slack.put(
        cases[i].Id,
        i < MAX_CASES_PER_JOB
          ? sendSlack(cases[i], settings)
          : 'Skipped: too many cases at once'
      );
    }
    Id groupId = supportGroupId();
    Id typeId = notificationTypeId();
    for (Case c : cases) {
      bell.put(c.Id, sendBell(c, settings, groupId, typeId));
    }
    for (Case c : cases) {
      c.CARES_Alert_Status__c = ('Bell: ' +
        bell.get(c.Id) +
        ' | Slack: ' +
        slack.get(c.Id))
        .left(255);
    }
    Database.update(cases, false, AccessLevel.SYSTEM_MODE);
  }

  // Bell

  @TestVisible
  private static String sendBell(Case c, Settings s, Id groupId, Id typeId) {
    if (s.bellEnabled != true) {
      return 'Off';
    }
    if (groupId == null) {
      return 'Failed: no ' + SUPPORT_GROUP + ' group';
    }
    if (typeId == null) {
      return 'Failed: no ' + NOTIFICATION_TYPE + ' type';
    }
    try {
      Messaging.CustomNotification n = new Messaging.CustomNotification();
      n.setNotificationTypeId(typeId);
      n.setTitle(
        (isUrgent(c) ? 'URGENT: ' : '') + 'CARES case ' + c.CaseNumber
      );
      n.setBody(
        'Why: ' +
          reasonText(c) +
          '. Order: ' +
          orderText(c) +
          '.' +
          (hasLiveChat(c) ? ' The customer is waiting in a live chat.' : '')
      );
      n.setTargetId(c.Id);
      n.send(new Set<String>{ groupId });
      return 'Sent';
    } catch (Exception e) {
      return 'Failed: ' + e.getMessage();
    }
  }

  // Slack

  @TestVisible
  private static String sendSlack(Case c, Settings s) {
    if (s.slackMode == MODE_OFF) {
      return 'Off';
    }
    HttpRequest req = new HttpRequest();
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json; charset=utf-8');
    req.setTimeout(10000);
    if (s.slackMode == MODE_BOT) {
      if (String.isBlank(s.slackChannel)) {
        return 'Failed: no channel';
      }
      req.setEndpoint('callout:CARES_Slack/chat.postMessage');
      req.setBody(JSON.serialize(botMessage(c, s.slackChannel)));
    } else if (s.slackMode == MODE_WORKFLOW) {
      req.setEndpoint('callout:CARES_Slack');
      req.setBody(JSON.serialize(workflowMessage(c)));
    } else {
      return 'Failed: unknown mode ' + s.slackMode;
    }
    try {
      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
        return 'Failed: HTTP ' + res.getStatusCode();
      }
      // The Web API answers 200 with ok = false on errors such as not_in_channel.
      if (s.slackMode == MODE_BOT) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        if (body.get('ok') != true) {
          return 'Failed: ' + String.valueOf(body.get('error'));
        }
      }
      return 'Sent';
    } catch (Exception e) {
      return 'Failed: ' + e.getTypeName();
    }
  }

  /** Block Kit message for chat.postMessage. */
  @TestVisible
  private static Map<String, Object> botMessage(Case c, String channel) {
    Boolean urgent = isUrgent(c);
    String title =
      (urgent ? ':red_circle: URGENT: ' : ':large_yellow_circle: ') +
      'CARES escalation, case ' +
      c.CaseNumber;
    List<Object> blocks = new List<Object>{
      new Map<String, Object>{
        'type' => 'header',
        'text' => plain(title)
      }
    };
    if (urgent) {
      blocks.add(
        section(
          '<!here> A customer reported a safety, health, fraud or legal issue. Someone take it now.'
        )
      );
    }
    blocks.add(
      new Map<String, Object>{
        'type' => 'section',
        'fields' => new List<Object>{
          mrkdwn('*Case*\n<' + caseUrl(c) + '|' + c.CaseNumber + '>'),
          mrkdwn('*Priority*\n' + escape(c.Priority)),
          mrkdwn('*Why*\n' + escape(reasonText(c))),
          mrkdwn('*Order*\n' + escape(orderText(c))),
          mrkdwn(
            '*Live chat*\n' +
            (hasLiveChat(c)
              ? 'Yes, waiting in Omni-Channel'
              : 'No, reply from the case')
          )
        }
      }
    );
    List<Object> buttons = new List<Object>{ button('Open case', caseUrl(c)) };
    if (hasLiveChat(c)) {
      buttons.add(button('Open conversation', sessionUrl(c)));
    }
    blocks.add(
      new Map<String, Object>{ 'type' => 'actions', 'elements' => buttons }
    );
    blocks.add(
      new Map<String, Object>{
        'type' => 'context',
        'elements' => new List<Object>{
          mrkdwn(
            'No customer details in Slack. The summary is on the case in Salesforce.'
          )
        }
      }
    );
    return new Map<String, Object>{
      'channel' => channel,
      'text' => title,
      'blocks' => blocks,
      'unfurl_links' => false
    };
  }

  /** Flat text variables for a Slack Workflow Builder webhook, written for people. */
  @TestVisible
  private static Map<String, Object> workflowMessage(Case c) {
    return new Map<String, Object>{
      'headline' => (isUrgent(c) ? '🔴 URGENT' : '🟡 New escalation') +
        ' · Case ' +
        c.CaseNumber,
      'case_number' => c.CaseNumber,
      'case_url' => caseUrl(c),
      'urgent' => isUrgent(c) ? 'yes' : 'no',
      'priority' => c.Priority,
      'reason' => reasonText(c),
      'reason_code' => reasonOf(c),
      'order_ref' => orderText(c),
      'live_chat' => hasLiveChat(c) ? 'yes' : 'no',
      'conversation_url' => hasLiveChat(c) ? sessionUrl(c) : ''
    };
  }

  // Helpers

  // The Flow sets High priority only for the URGENT category.
  private static Boolean isUrgent(Case c) {
    return c.Priority == 'High';
  }

  private static Boolean hasLiveChat(Case c) {
    return String.isNotBlank(c.CARES_Messaging_Session_Id__c);
  }

  private static String reasonOf(Case c) {
    return String.isBlank(c.CARES_Escalation_Reason__c)
      ? 'NOT_GIVEN'
      : c.CARES_Escalation_Reason__c;
  }

  // Plain words for the reason codes the agent sets (D-085). A new code shows as is.
  private static final Map<String, String> REASON_TEXT = new Map<String, String>{
    'SAFETY' => 'Safety, health, fraud or legal issue',
    'REPEATED_ISSUES' => 'Many past issues, needs a review',
    'CLAIM_REVIEW' => 'Claim needs a person to review',
    'IDENTITY_FAILED' => 'Customer could not be verified',
    'ISSUE_FAILED' => 'Refund could not be issued',
    'CLAIM_FAILED' => 'Claim could not be handed off',
    'ORDER_NOT_FOUND' => 'Order not found',
    'NOT_ELIGIBLE' => 'Not eligible for a refund',
    'OFFER_DISPUTED' => 'Customer did not accept the offer',
    'CUSTOMER_REQUEST' => 'Customer asked for a person',
    'NOT_GIVEN' => 'Not given'
  };

  @TestVisible
  private static String reasonText(Case c) {
    String code = reasonOf(c);
    return REASON_TEXT.containsKey(code) ? REASON_TEXT.get(code) : code;
  }

  // The Flow writes NONE when the case has no order.
  @TestVisible
  private static String orderText(Case c) {
    String ref = c.CARES_Order_Ref__c;
    return String.isBlank(ref) || ref == 'NONE' ? 'No order linked' : ref;
  }

  private static String caseUrl(Case c) {
    return recordUrl('Case', c.Id);
  }

  private static String sessionUrl(Case c) {
    return recordUrl('MessagingSession', c.CARES_Messaging_Session_Id__c);
  }

  private static String recordUrl(String objectName, String recordId) {
    return URL.getOrgDomainUrl().toExternalForm() +
      '/lightning/r/' +
      objectName +
      '/' +
      recordId +
      '/view';
  }

  // Slack mrkdwn control characters.
  private static String escape(String value) {
    return value == null
      ? ''
      : value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
  }

  private static Map<String, Object> plain(String text) {
    return new Map<String, Object>{
      'type' => 'plain_text',
      'text' => text,
      'emoji' => true
    };
  }

  private static Map<String, Object> mrkdwn(String text) {
    return new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => text };
  }

  private static Map<String, Object> section(String text) {
    return new Map<String, Object>{ 'type' => 'section', 'text' => mrkdwn(text) };
  }

  private static Map<String, Object> button(String label, String url) {
    return new Map<String, Object>{
      'type' => 'button',
      'text' => plain(label),
      'url' => url
    };
  }

  // The job runs as the agent user, who cannot read these in user mode. A failed
  // lookup means no bell, never a failed job: Slack and the status still go out.
  private static Id supportGroupId() {
    try {
      List<Group> groups = [
        SELECT Id
        FROM Group
        WHERE DeveloperName = :SUPPORT_GROUP AND Type = 'Regular'
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      return groups.isEmpty() ? null : groups[0].Id;
    } catch (Exception e) {
      return null;
    }
  }

  private static Id notificationTypeId() {
    try {
      List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = :NOTIFICATION_TYPE
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      return types.isEmpty() ? null : types[0].Id;
    } catch (Exception e) {
      return null;
    }
  }
}
