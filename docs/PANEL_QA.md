# Panel Q&A: team answers

Short answers (two sentences) to questions we expect. Each of us must be able to answer all of them. Update as decisions change. `OPEN` = not decided yet.

1. **Who is the internal customer and which KPI?** `OPEN` (headline KPI: customer retention).
2. **Why this architecture (router + subagents)?** `OPEN`.
3. **What does the script decide and what does the model write?** The script decides identity, data access and money; the model writes the words. Reason: instructions are not guarantees.
4. **Where does each fact come from, and how did we check it?** See [GROUNDING.md](GROUNDING.md).
5. **What happens if retrieval or an action fails?** Standard path or a person; never an invented answer.
6. **Risk: one failure for People, Business, Tech, Data?** See [RISKS.md](RISKS.md).
7. **How did we test?** See [TEST_PLAN.md](TEST_PLAN.md).
8. **Why Flow here and Apex there?** Flow is easier to maintain for a customer without a dedicated IT team; Apex where speed matters. Not measured yet.
9. **ROI / consumption / security / governance objections?** `OPEN`.
10. **What would we rebuild? What is the strongest counter-argument to our own approach?** `OPEN`.
