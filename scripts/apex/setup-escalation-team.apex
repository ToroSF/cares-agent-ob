// Set up the people who take over CARES escalations (D-086, G-068).
// Run once after the CARES_Support_Team group and the two queues are deployed:
//   sf apex run --file scripts/apex/setup-escalation-team.apex --target-org <team org>
// Safe to run again: it only adds what is missing. It never removes anyone.
// Set DRY_RUN = true to print what would change without writing.
//
// For each person in TEAM it:
//   1. adds them to the CARES_Support_Team group (members of both CARES queues and of the bell);
//   2. turns on Service Cloud User, needed to accept chats in Omni-Channel (one feature licence each);
//   3. assigns Agent_Presence_Status_Access (the "Available" status on the Messaging channel).
// Group membership is not deployable metadata, which is why this is a script.

Boolean DRY_RUN = false;

// Usernames in the team org. Demo usernames, not secrets.
List<String> TEAM = new List<String>{
    'rojas.c1@salesforce.com',
    'jacobo.torohub@salesforce.com',
    'mdegoeshub@salesforce.com',
    'lpalomaneshub2@salesforce.com'
};

Group team = [SELECT Id FROM Group WHERE DeveloperName = 'CARES_Support_Team' AND Type = 'Regular' LIMIT 1];
PermissionSet presence = [SELECT Id FROM PermissionSet WHERE Name = 'Agent_Presence_Status_Access' LIMIT 1];

List<User> users = [SELECT Id, Username, UserPermissionsSupportUser FROM User WHERE Username IN :TEAM AND IsActive = true];
Set<Id> inGroup = new Set<Id>();
for (GroupMember m : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :team.Id]) {
    inGroup.add(m.UserOrGroupId);
}
Set<Id> hasPresence = new Set<Id>();
for (PermissionSetAssignment a : [SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId = :presence.Id]) {
    hasPresence.add(a.AssigneeId);
}

List<GroupMember> members = new List<GroupMember>();
List<User> supportUsers = new List<User>();
List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
for (User u : users) {
    if (!inGroup.contains(u.Id)) {
        members.add(new GroupMember(GroupId = team.Id, UserOrGroupId = u.Id));
    }
    if (u.UserPermissionsSupportUser != true) {
        supportUsers.add(new User(Id = u.Id, UserPermissionsSupportUser = true));
    }
    if (!hasPresence.contains(u.Id)) {
        assignments.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = presence.Id));
    }
}

System.debug('SETUP found ' + users.size() + ' of ' + TEAM.size() + ' users');
System.debug('SETUP group members to add: ' + members.size());
System.debug('SETUP Service Cloud User to turn on: ' + supportUsers.size());
System.debug('SETUP presence permission sets to assign: ' + assignments.size());

if (!DRY_RUN) {
    insert members;
    update supportUsers;
    insert assignments;
    System.debug('SETUP done');
}
