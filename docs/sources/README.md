# Official Pronto sources

These four PDFs are the only official Pronto rules we build on (D-046). Anything else in the repo is a team assumption and is marked as one.

| Code | File | Audience (from the document) | Words | Used how | SHA-256 (first 12) |
|---|---|---|---|---|---|
| P | [pronto-customer-support-playbook.pdf](pronto-customer-support-playbook.pdf) | Pronto support agents and supervisors (internal) | ~560 | Rules written into the agent script and flows. **Never retrieved or quoted to customers** (D-051) | `70ad15833dd0` |
| F | [pronto-delivery-and-order-lifecycle-faq.pdf](pronto-delivery-and-order-lifecycle-faq.pdf) | Customers | ~330 | Retrieved by Pronto Help (Data Library `CARES_Customer_Policy`) | `e84ca48c162e` |
| T | [pronto-promotions-membership-and-gift-certificates-terms.pdf](pronto-promotions-membership-and-gift-certificates-terms.pdf) | Customers | ~270 | Retrieved by Pronto Help | `6458c30858cc` |
| M | [pronto-merchant-and-storefront-standards.pdf](pronto-merchant-and-storefront-standards.pdf) | Customers | ~200 | Retrieved by Pronto Help. The allergen line is also a hard rule in the script | `194715cd8683` |

- Received: 2026-10-13. Added to the repo: 2026-10-20. Owner of this folder: @Mateus-Goes (grounding).
- If Pronto sends a new version: replace the file, update the hash and the date here, re-run the alignment check in [POLICY_ALIGNMENT.md](../POLICY_ALIGNMENT.md), re-index the Data Library (`sf agent adl file add`, no agent republish needed) and re-run the golden set in [grounding/golden-set.md](../grounding/golden-set.md).
- The documents give no amounts, percentages, windows or tiers. Every number in CARES is a team assumption, marked `[$]` (D-052).
- Rule IDs used in the docs: `POL-P..` (Playbook), `POL-F..` (FAQ), `POL-T..` (Terms), `POL-M..` (Merchant). The `POL-` prefix avoids a clash with test IDs (`T-`, `R-`).
