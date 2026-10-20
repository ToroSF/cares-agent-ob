/**
 * Invocable action backing the Identify Customer sub-agent's
 * "find_contact_by_email" action. Used only when the channel gave no ContactId
 * (D-045). Returns a match only when exactly one Contact has the email, and
 * returns only the Contact Id, never other customer data.
 *
 * target: "apex://CARES_Identity_FindContactByEmail"
 */
public with sharing class CARES_Identity_FindContactByEmail {
    public class Request {
        @InvocableVariable(
            label='Email'
            description='Email address the customer typed in the chat'
            required=true
        )
        public String email;
    }

    public class Result {
        @InvocableVariable(
            label='Found'
            description='True only when exactly one Contact has this email'
        )
        public Boolean found;

        @InvocableVariable(
            label='Contact ID'
            description='Id of the matching Contact; blank when not found'
        )
        public String contactId;
    }

    @InvocableMethod(
        label='CARES Identity Find Contact By Email'
        description='Finds the single Contact with this email address when the chat has no linked contact'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(find(req.email));
        }
        return results;
    }

    private static Result find(String rawEmail) {
        Result r = new Result();
        r.found = false;
        r.contactId = '';
        String email = rawEmail == null ? '' : rawEmail.trim().toLowerCase();
        if (!isEmail(email)) {
            return r;
        }
        // Sharing applies; only the Id leaves this method. Two or more matches is ambiguous, so not found
        List<Contact> matches = [SELECT Id FROM Contact WHERE Email = :email LIMIT 2];
        if (matches.size() == 1) {
            r.found = true;
            r.contactId = matches[0].Id;
        }
        return r;
    }

    private static Boolean isEmail(String value) {
        return String.isNotBlank(value)
            && value.length() <= 80
            && Pattern.matches('^[a-z0-9._%+\'-]+@[a-z0-9.-]+\\.[a-z]{2,}$', value);
    }
}
