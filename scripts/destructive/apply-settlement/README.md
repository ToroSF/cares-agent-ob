# Retire `CARES_Refund_ApplySettlement` (D-092)

The settlement is now recorded by `issue_resolution` on the payout's `CARES_Resolution__c` row, so the `apply_settlement` stub is gone from the repo and the agent. Removing a class from the repo doesn't delete it in the org; deploy this once, with the deploy that ships D-092:

```
sf project deploy start --source-dir force-app --post-destructive-changes scripts/destructive/apply-settlement/destructiveChanges.xml --target-org <org>
```

The published agent version that still calls `apply_settlement` must be deactivated (a newer version active) before the class can be deleted.
