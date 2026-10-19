/**
 * Invocable action backing the Experience Rating sub-agent's "save_csat_rating"
 * action. Persists one CSAT_Rating__c record per resolved CARES interaction.
 *
 * target: "apex://CsatRatingSaver"
 */
public with sharing class CsatRatingSaver {

    @InvocableMethod(
        label='Save CSAT Rating'
        description='Saves a customer satisfaction rating (1-5) and optional comment for a resolved CARES interaction, linked to the customer Contact.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        Set<Id> contactIds = new Set<Id>();
        for (Request req : requests) {
            if (req.contactId != null) {
                contactIds.add(req.contactId);
            }
        }

        Map<Id, Contact> contactsById = new Map<Id, Contact>();
        if (!contactIds.isEmpty()) {
            contactsById = new Map<Id, Contact>(
                [SELECT Id, AccountId
                 FROM Contact
                 WHERE Id IN :contactIds
                 WITH USER_MODE]
            );
        }

        List<CSAT_Rating__c> ratingsToInsert = new List<CSAT_Rating__c>();
        List<Request> requestsForInsert = new List<Request>();

        for (Request req : requests) {
            Contact relatedContact = contactsById.get(req.contactId);
            if (relatedContact == null) {
                results.add(errorResult('Contact not found: ' + req.contactId));
                continue;
            }
            if (req.score == null || req.score < 1 || req.score > 5) {
                results.add(errorResult('Score must be between 1 and 5.'));
                continue;
            }

            CSAT_Rating__c rating = new CSAT_Rating__c();
            rating.Contact__c = relatedContact.Id;
            rating.Account__c = relatedContact.AccountId;
            rating.Score__c = req.score;
            rating.Comment__c = req.comment;
            rating.Interaction_Date__c = Datetime.now();

            ratingsToInsert.add(rating);
            requestsForInsert.add(req);
        }

        if (!ratingsToInsert.isEmpty()) {
            try {
                insert as user ratingsToInsert;
                for (Integer i = 0; i < ratingsToInsert.size(); i++) {
                    Result r = new Result();
                    r.isSuccess = true;
                    r.ratingId = ratingsToInsert[i].Id;
                    results.add(r);
                }
            } catch (Exception e) {
                for (Integer i = 0; i < ratingsToInsert.size(); i++) {
                    results.add(errorResult('Failed to save rating: ' + e.getMessage()));
                }
            }
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Contact Id'
            description='Id of the customer (Contact) giving the rating'
            required=true
        )
        public String contactId;

        @InvocableVariable(
            label='Score'
            description='Satisfaction score from the slider, 1 (very unsatisfied) to 5 (very satisfied)'
            required=true
        )
        public Decimal score;

        @InvocableVariable(
            label='Comment'
            description='Optional free-text comment, typically collected only when the score is low'
            required=false
        )
        public String comment;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='Whether the rating was saved successfully'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error message if the rating could not be saved'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Rating Id'
            description='Id of the created CSAT_Rating__c record'
        )
        public Id ratingId;
    }

    private static Result errorResult(String message) {
        Result r = new Result();
        r.isSuccess = false;
        r.errorMessage = message;
        return r;
    }
}
