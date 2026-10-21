// Escalate to Human: alerts the support team about new CARES escalation cases (D-086).
trigger CARES_EscalationCaseTrigger on Case(after insert) {
  CARES_EscalationAlerts.enqueueFor(Trigger.new);
}
