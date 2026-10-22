/**
 * Invocable action backing the Experience Rating sub-agent's "save_csat_rating"
 * action. Persists one CSAT_Rating__c record per resolved CARES interaction, and
 * upserts the customer's CARES_Customer_Context__c row from the same sentiment
 * read (D-083): Risk Detection consumes that row before handing off to Refund.
 *
 * target: "apex://CsatRatingSaver"
 */
public with sharing class CsatRatingSaver {
  private static final Set<String> VALID_SENTIMENTS = new Set<String>{
    'POSITIVE',
    'NEUTRAL',
    'NEGATIVE',
    'FRUSTRATED'
  };
  private static final Set<String> OPEN_CONTEXT_SENTIMENTS = new Set<String>{
    'NEGATIVE',
    'FRUSTRATED'
  };
  // Only the customer's own thumbs down opens the context (score 2; thumbs up is 5). The
  // sentiment is the model's read, so a customer who asks to be marked FRUSTRATED on a
  // thumbs up must not unlock the retention bonus (G-133, D-102)
  private static final Decimal OPEN_CONTEXT_MAX_SCORE = 2;
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
      // Without read on Contact or Account the query throws in user mode; that must
      // come back as isSuccess = false, not as an action error (G-089)
      try {
        contactsById = new Map<Id, Contact>(
          [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
          ]
        );
      } catch (Exception e) {
        for (Integer i = 0; i < requests.size(); i++) {
          results[i] = errorResult(
            'Failed to read the customer: ' + e.getMessage()
          );
        }
        return results;
      }
    }

    List<CSAT_Rating__c> ratingsToInsert = new List<CSAT_Rating__c>();
    List<Integer> insertPositions = new List<Integer>();
    List<Id> insertContactIds = new List<Id>();
    List<String> insertSentiments = new List<String>();
    List<Decimal> insertScores = new List<Decimal>();

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
      if (
        String.isBlank(req.sentiment) ||
        !VALID_SENTIMENTS.contains(req.sentiment)
      ) {
        results[i] = errorResult(
          'Sentiment must be POSITIVE, NEUTRAL, NEGATIVE or FRUSTRATED.'
        );
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
      insertContactIds.add(relatedContact.Id);
      insertSentiments.add(req.sentiment);
      insertScores.add(req.score);
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
        upsertCustomerContext(
          insertContactIds,
          insertSentiments,
          insertScores,
          ratingsToInsert
        );
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

  // The context row is an enrichment, not the record of truth (the CSAT_Rating__c
  // insert above already succeeded). A failure here never fails the rating save.
  private static void upsertCustomerContext(
    List<Id> contactIds,
    List<String> sentiments,
    List<Decimal> scores,
    List<CSAT_Rating__c> insertedRatings
  ) {
    try {
      Map<Id, CARES_Customer_Context__c> existingByContact = new Map<Id, CARES_Customer_Context__c>();
      for (CARES_Customer_Context__c ctx : [
        SELECT Id, Contact__c
        FROM CARES_Customer_Context__c
        WHERE Contact__c IN :contactIds
        WITH USER_MODE
      ]) {
        existingByContact.put(ctx.Contact__c, ctx);
      }

      List<CARES_Customer_Context__c> toUpsert = new List<CARES_Customer_Context__c>();
      for (Integer i = 0; i < contactIds.size(); i++) {
        CARES_Customer_Context__c ctx = existingByContact.get(contactIds[i]);
        if (ctx == null) {
          ctx = new CARES_Customer_Context__c(Contact__c = contactIds[i]);
        }
        ctx.Sentiment__c = sentiments[i];
        ctx.Has_Open_Context__c =
          OPEN_CONTEXT_SENTIMENTS.contains(sentiments[i]) &&
          scores[i] <= OPEN_CONTEXT_MAX_SCORE;
        ctx.Last_Interaction_Date__c = Datetime.now();
        ctx.Source_Rating__c = insertedRatings[i].Id;
        toUpsert.add(ctx);
      }
      upsert as user toUpsert;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'Failed to upsert CARES_Customer_Context__c: ' + e.getMessage()
      );
    }
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

    @InvocableVariable(
      label='Sentiment'
      description='The agent\'s own assessment of the customer\'s sentiment across the whole conversation: POSITIVE, NEUTRAL, NEGATIVE or FRUSTRATED. Never dictated by the customer.'
      required=true
    )
    public String sentiment;
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
