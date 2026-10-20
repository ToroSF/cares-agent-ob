/**
 * Invocable action backing the Experience Rating sub-agent's "save_csat_rating"
 * action. Persists one CSAT_Rating__c record per resolved CARES interaction.
 *
 * target: "apex://CsatRatingSaver"
 */
public with sharing class CsatRatingSaver {
  @InvocableMethod(
    label='Save CSAT Rating'
    description='Saves a customer satisfaction rating (1-5, mapped from a thumbs up/down choice) and the agent\'s own written summary for a resolved CARES interaction, linked to the customer Contact.'
  )
  public static List<Result> execute(List<Request> requests) {
    // One result per request, in request order (invocable contract)
    List<Result> results = new List<Result>();
    List<Id> requestContactIds = new List<Id>();
    Set<Id> contactIds = new Set<Id>();
    for (Request req : requests) {
      Id contactId = toId(req.contactId);
      requestContactIds.add(contactId);
      results.add(null);
      if (contactId != null) {
        contactIds.add(contactId);
      }
    }

    Map<Id, Contact> contactsById = new Map<Id, Contact>();
    if (!contactIds.isEmpty()) {
      contactsById = new Map<Id, Contact>(
        [
          SELECT Id, AccountId
          FROM Contact
          WHERE Id IN :contactIds
          WITH USER_MODE
        ]
      );
    }

    List<CSAT_Rating__c> ratingsToInsert = new List<CSAT_Rating__c>();
    List<Integer> insertPositions = new List<Integer>();

    for (Integer i = 0; i < requests.size(); i++) {
      Request req = requests[i];
      Contact relatedContact = requestContactIds[i] == null
        ? null
        : contactsById.get(requestContactIds[i]);
      if (relatedContact == null) {
        results[i] = errorResult('Contact not found: ' + req.contactId);
        continue;
      }
      if (req.score == null || req.score < 1 || req.score > 5) {
        results[i] = errorResult('Score must be between 1 and 5.');
        continue;
      }

      CSAT_Rating__c rating = new CSAT_Rating__c();
      rating.Contact__c = relatedContact.Id;
      rating.Account__c = relatedContact.AccountId;
      rating.Score__c = req.score;
      rating.Comment__c = req.comment;
      rating.Interaction_Date__c = Datetime.now();

      ratingsToInsert.add(rating);
      insertPositions.add(i);
    }

    if (!ratingsToInsert.isEmpty()) {
      try {
        insert as user ratingsToInsert;
        for (Integer j = 0; j < ratingsToInsert.size(); j++) {
          Result r = new Result();
          r.isSuccess = true;
          r.ratingId = ratingsToInsert[j].Id;
          results[insertPositions[j]] = r;
        }
      } catch (Exception e) {
        for (Integer j = 0; j < ratingsToInsert.size(); j++) {
          results[insertPositions[j]] = errorResult(
            'Failed to save rating: ' + e.getMessage()
          );
        }
      }
    }

    return results;
  }

  // Blank or malformed ids become null instead of throwing
  private static Id toId(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Id.valueOf(value);
    } catch (StringException e) {
      return null;
    }
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
      description='Score mapped from the customer\'s thumbs up/down choice: 5 for thumbs up, 2 for thumbs down'
      required=true
    )
    public Decimal score;

    @InvocableVariable(
      label='Comment'
      description='The agent\'s own written summary of how the interaction went, generated from the conversation'
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
