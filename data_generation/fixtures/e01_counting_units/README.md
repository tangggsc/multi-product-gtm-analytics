# Fixture E01: counting units

Small, hand-checkable fixture for the first counting rule in PROJECT.md (E01): product-level counts can sum to more than the company count. The expected results in `expected_paying_counts.csv` were written by hand before any transformation logic, and they serve as the independent truth ledger.

All records are synthetic. Domains use the reserved `.example` TLD.

## Companies

| Canonical company | Source records | Product A | Product B |
| --- | --- | --- | --- |
| COMPANY_001 Acme | crm_a/101, crm_b/987, billing_a/cus_a_001, billing_b/cus_b_001 | Paid, two workspaces (ws_100, ws_101) | Paid (ws_500) |
| COMPANY_002 Beta Labs | crm_b/101, billing_b/cus_b_002 | — | Paid (ws_100) |
| COMPANY_003 Gamma Data | crm_a/202, crm_b/654, billing_a/cus_a_002, billing_b/cus_b_003 | Paid (ws_200) | Payment **failed** (ws_600) |
| COMPANY_004 Delta | crm_a/303, billing_a/cus_a_003 | Paid Feb only, **expired** 2026-03-01 (ws_300) | — |
| *(unresolved)* | product A workspace ws_400, personal email, no account link | Free, no payment | — |

## Expected results

| As of (UTC) | Paying companies | Paying account-products | Paying accounts A / B | Paying workspaces |
| --- | --- | --- | --- | --- |
| 2026-03-20 | 3 | 4 | 2 / 2 | 5 |
| 2026-02-15 | 1 | 1 | 1 / 0 | 1 |

## Edge cases covered

- **Same company in two CRMs.** Acme is crm_a/101 and crm_b/987. It counts as one company and two account-products.
- **ID collision across systems.** crm_a/101 (Acme) and crm_b/101 (Beta) are different companies, so joins must use both source system and ID.
- **Workspace ID collision across products.** A/ws_100 (Acme) and B/ws_100 (Beta) are different workspaces.
- **User ID collision across products.** A/u_001 is Alice, while B/u_001 is Ben.
- **Several workspaces, one account-product.** Acme's two paid product A workspaces add workspaces, not companies or account-products.
- **Failed payment.** Gamma's product B payment does not create a paying account-product.
- **As-of entitlement.** Delta's service period is [2026-02-01, 2026-03-01), so Delta pays on 2026-02-15 but not on 2026-03-20.
- **Unresolved workspace.** ws_400 has no account link and stays unresolved. It is not guessed from email. It has no payment, so it does not affect paying counts, and it is kept for coverage reporting in a later PR.

No event deliveries are included yet. Per PROJECT.md, counting units are validated before events or funnel calculations are added.
