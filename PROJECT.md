# GTM Analytics Across Two Products

Status: project specification; implementation has not started.

## Business context

Following an acquisition, a developer-tools business operates two products with separate product telemetry, CRM records, and billing identities. Each product supports self-serve purchasing and sales-assisted contracts. Customers may use either product or both, and a self-serve customer may later negotiate an enterprise agreement.

Marketing, sales, product, and finance need a consistent view of acquisition, activation, paid conversion, and expansion. Inconsistent identities and lifecycle definitions make it difficult to compare product performance, reconcile customer counts, and decide where to invest.

The initiative establishes a shared GTM measurement foundation while retaining the product-specific definitions needed to interpret each funnel.

**Case-study disclosure:** This is a fictional business scenario using synthetic data. Products A and B are illustrative; records, incidents, and findings do not represent an actual company's operations.

## Business decisions and initial investigation

Central investigation: **Did self-serve conversion actually decline, or did tracking, customer mix, identity matching, or cohort maturity change the reported result?**

| Stakeholder | Decision to support | Evidence required |
| --- | --- | --- |
| Growth and marketing | Whether to change acquisition investment | Mature conversion cohorts, channel mix, attribution coverage and, in a later phase, acquisition costs |
| Product | Where onboarding needs attention | Product-specific activation, time to activation and funnel drop-off |
| Sales and RevOps | Which accounts need coordinated engagement | Account-level usage, commercial status and, in a later phase, opportunity history |
| Finance and leadership | How many paying companies and product relationships exist | Reconciled customer counts, billing links and explicit as-of rules |

Every finding should state the affected segment, magnitude, supporting evidence, alternative explanations, recommended action, and a follow-up measure. Recommendations must follow from the analysis; no result is assumed in advance.

## Operating assumptions and boundaries

The scenario models product telemetry, CRM account records, and billing activity from two product environments. Marketing touchpoints, spend, and CRM stage history enter in later phases. Source schemas are simulated interfaces, not claims about a vendor's exact export schema.

Support product-specific funnel views and a common account view. Shared modeling does not require identical activation criteria or collapsing all journeys into one funnel. A shared account view can support coordinated engagement and cross-sell analysis without presuming an existing ABM program.

Raw records, mapping decisions, and model outputs remain traceable. Use generated records only; exclude employer data and proprietary code.

## Views and counting units

| View | Purpose | Counting unit |
| --- | --- | --- |
| Product A journey | Acquisition, activation, purchase, expansion by buying path | Workspace for activation; account-product for customers |
| Product B journey | Same questions with product B's own activation criteria | Workspace for activation; account-product for customers |
| Shared account view | Connect people, workspaces, subscriptions and opportunities across products | Canonical company/account |

Example: company A pays for both products, B pays only for product A, and C pays only for product B. This is **3 unique paying companies, 2 paying accounts per product, and 4 paying account-product relationships**. Multiple workspaces do not create additional companies. Document the legal-entity versus parent-company policy; do not automatically merge subsidiaries.

## Technical approach

Use open-source dbt Core with the dbt-duckdb adapter and a local DuckDB database. A paid dbt platform subscription is not required for local transformations and tests. DuckDB avoids a cloud warehouse bill for the first version.

Proposed stack: Python synthetic-data generation → DuckDB raw tables → dbt staging/intermediate/mart models → documented metric views and a small reporting output. Add Prefect orchestration after the underlying build is reliable.

At implementation time, select and pin mutually compatible Python, dbt Core, dbt-duckdb and DuckDB versions using the adapter's current compatibility guidance. Do not assume all newest releases work together. Record a reproducible installation and build command in README.md.

The initial deployment is local. A cloud warehouse and a hosted semantic layer are later extensions. SQL metric views centralize definitions in the first release; an interactive dashboard alone does not constitute an implemented semantic layer. Hosting, optional cloud services, and CI usage can have separate costs.

## First version

Deliver one complete investigation with these capabilities:

1. Generate reproducible synthetic product events, workspace memberships, CRM account mappings, and billing records for two products.
2. Resolve supported identities while preserving ambiguous/unmatched records.
3. Model product-specific activation and a workspace signup-to-paid funnel using equal observation windows.
4. Produce company-level and account-product-level paying customer counts without duplication.
5. Plant and resolve four defects: duplicate delivery, changed event naming, incomplete account mapping, and immature cohort comparison.
6. Show naive versus corrected metrics and explain each adjustment separately.
7. Add automated checks, model documentation, and reviewable changes.

Defer full CRM stage modeling, attribution, CAC/payback, and a hosted semantic layer until this slice is working.

## Source inventory: seven raw tables

The initial release uses **7 raw tables and 2 reference tables**. Raw tables contain generated source records; reference tables contain explicit interpretation rules. Both products' records share these table structures and are distinguished by product and source identifiers. These are planned datasets, not tables already built.

| Raw table | One row represents | Initial columns | Business purpose |
| --- | --- | --- | --- |
| `raw_crm_accounts` | One account record in one CRM system | `source_system`, `source_account_id`, `account_name`, `domain`, `created_at`, `updated_at`, `ingested_at` | Identify source companies, including duplicate representations across systems |
| `raw_users` | One user record within one product | `product`, `user_id`, `email`, `created_at`, `updated_at`, `ingested_at` | Identify product users; email is an attribute, not a durable company key |
| `raw_workspaces` | One workspace within one product | `product`, `workspace_id`, `workspace_name`, `created_by_user_id`, `source_account_system`, `source_account_id`, `created_at`, `is_test`, `ingested_at` | Establish signup cohorts and supported company links; account-link fields may be null |
| `raw_workspace_memberships` | One user's membership interval in a workspace | `product`, `membership_id`, `workspace_id`, `user_id`, `role`, `valid_from`, `valid_to`, `ingested_at` | Connect people to workspaces without assuming one company per person |
| `raw_event_deliveries` | One delivered copy of an event | `product`, `delivery_id`, `event_id`, `workspace_id`, `user_id`, `event_name`, `occurred_at`, `ingested_at` | Measure activation and retain evidence of retries, late delivery and tracking changes |
| `raw_billing_customers` | One customer record in one billing system | `source_system`, `billing_customer_id`, `customer_name`, `source_account_system`, `source_account_id`, `created_at`, `updated_at`, `ingested_at` | Connect billing identities to companies; do not assume one billing customer per company |
| `raw_billing_transactions` | One payment or refund transaction | `source_system`, `transaction_id`, `billing_customer_id`, `product`, `workspace_id`, `transaction_type`, `status`, `amount`, `currency`, `payment_at`, `service_period_start`, `service_period_end`, `original_transaction_id`, `ingested_at` | Establish paid outcomes, reconcile payments/refunds, and retain the service period supported by the source |

### Source contracts and boundaries

- Account identity is namespaced by `(source_system, source_account_id)`. User and workspace identity are namespaced by product. Transaction/customer IDs are namespaced by billing source.
- Delivery IDs identify delivered copies; `(product, event_id)` identifies a logical event. A repeated event ID is an intentional source condition, not grounds for deleting the raw delivery.
- Timestamps use UTC. `created_at`, `occurred_at`, and `payment_at` describe business events; `ingested_at` describes warehouse arrival. Preserve both.
- Memberships and service periods use inclusive starts and exclusive ends. Null `valid_to` means an open-ended membership.
- Amounts use a fixed-precision decimal. Initial payments/refunds store nonnegative amounts; transaction type determines the sign of net cash. A refund references its original transaction. Only successful payments qualify for paid conversion.
- Event actor `user_id` can be null for system-generated activity. Activation requires a valid product-workspace relationship, not necessarily a human actor.
- Initial fixtures give each transaction one explicit workspace link. This is a scope restriction, not an assumption about all contracts. Unlinked payments remain in financial reconciliation and an exception output; they do not become guessed workspace conversions. Contracts covering several workspaces require a later coverage bridge.
- Paid-customer counts in the initial fixtures rely on explicit service periods attached to successful payments. Missing service dates mean unknown entitlement, not indefinite access. Broader cancellation, trial, amendment and refund-entitlement policies require subscription/contract history in a later phase; payment history alone cannot establish those states.
- Raw tables remain inspectable. Failed constraints produce documented exceptions or blocked publication depending on severity; dbt creates cleaned models separately.

## Reference tables: two interpretation rules

Store the following as CSV files under `dbt_project/seeds/` and version-control changes. They are maintained mapping inputs, not extra raw source tables. `bridge_source_accounts` is the validated dbt output built from the account reference table.

### 1. `ref_account_mapping`

Answers: **Which canonical company does a record from this particular source represent?**

| source_system | source_account_id | canonical_account_id | match_method | evidence_reference | valid_from | valid_to |
| --- | --- | --- | --- | --- | --- | --- |
| crm_a | 101 | COMPANY_001 | verified_link | fixture_acme_link | 2026-01-01T00:00:00Z | NULL |
| crm_b | 987 | COMPANY_001 | verified_link | fixture_acme_link | 2026-01-01T00:00:00Z | NULL |
| billing | 555 | COMPANY_001 | explicit_crm_link | fixture_billing_555 | 2026-01-01T00:00:00Z | NULL |
| crm_b | 101 | COMPANY_002 | verified_link | fixture_beta_link | 2026-01-01T00:00:00Z | NULL |

Here `crm_a / 101` and `crm_b / 987` represent the same company. `crm_b / 101` represents a different company despite reusing ID 101. For billing rows, `source_account_id` holds the source billing customer ID; this field is a generic source-entity key in this reference table.

Join on **both source system and source ID**, plus the effective interval when historical validity matters:

```sql
left join ref_account_mapping m
    on r.source_system = m.source_system
   and r.source_account_id = m.source_account_id
   and r.business_at >= m.valid_from
   and (r.business_at < m.valid_to or m.valid_to is null)
```

`r` is a standardized intermediate input, not a raw table with a pre-existing `business_at` column. The consuming model must define `business_at` explicitly: for example workspace creation time for signup ownership, payment time for a payment, or an as-of timestamp for current reporting.

Require non-null source keys, canonical IDs and evidence references, and non-overlapping validity intervals per source key. Missing matches remain unresolved; similar domains or a shared consultant do not justify a merge. Effective dates describe business validity; reconstructing what mapping was known at an earlier run also requires mapping-version history, not just these dates.

### 2. `ref_event_mapping`

Answers: **What does this source event mean, and does it qualify for activation?**

| product | source_event_name | normalized_event_name | qualifies_for_activation | valid_from | valid_to |
| --- | --- | --- | --- | --- | --- |
| A | workflow_success | successful_run | true | 2026-01-01T00:00:00Z | 2026-07-01T00:00:00Z |
| A | flow_run_completed | successful_run | true | 2026-07-01T00:00:00Z | NULL |
| B | asset_materialization_success | successful_materialization | true | 2026-01-01T00:00:00Z | NULL |
| A | page_view | page_view | false | 2026-01-01T00:00:00Z | NULL |

Join on product, source event name and **`occurred_at`**, using the same inclusive-start/exclusive-end logic. A June event arriving in July uses June's mapping. Null end dates are open-ended; July 1 belongs to the second rule in this fixture.

Map names together only when their business meanings agree. An activation-eligible event must also satisfy the metric's seven-day window; the flag alone does not establish activation. Unmapped names stay visible in coverage reports. Require non-overlapping intervals per product and event name, and test old-name, new-name, boundary, and unknown-name inputs.

### Relationships and inspection

| Relationship | Join rule |
| --- | --- |
| Workspace → CRM account | Workspace source-account system and ID → CRM source-system and account ID |
| Source account or billing customer → canonical company | Source identity → account mapping, with the relevant validity interval |
| Membership → workspace and user | Product plus workspace ID; product plus user ID |
| Event → workspace | Product plus workspace ID |
| Event → normalized behavior | Product plus event name and event occurrence time → event mapping |
| Transaction → billing customer | Billing source system plus customer ID |
| Transaction → workspace | Product plus workspace ID, when explicitly linked |

Generate readable CSV exports as well as the local `.duckdb` database. DBeaver should expose raw, reference, staging and reporting tables so each fixture can be traced from source records to final counts. Disconnect DBeaver before a separate process writes to the local database to avoid file-lock conflicts.

## Derived model grains

| Dataset/model | One row represents | Key rule |
| --- | --- | --- |
| raw_event_deliveries | One delivered copy of an event | Include event ID, product, occurrence and receipt times |
| stg_product_events | One logical event per product | Deduplicate by product plus event ID |
| raw_workspace_memberships | One membership interval | A person can belong to multiple companies |
| bridge_source_accounts | One source account mapping per effective interval | Include source system, match method and validity dates |
| dim_accounts | One canonical company | Parent relationships are separate attributes |
| dim_workspaces | One product workspace | Workspace IDs are namespaced by product |
| fct_workspace_activation | One workspace | First qualifying event under the documented definition |
| fct_billing_transactions | One billing transaction | Preserve refunds, currency and effective dates |
| fct_workspace_funnel | One workspace signup cohort member | Paid outcome requires a supported workspace-to-billing link |
| fct_account_product_daily | One account-product-date | Aggregate memberships and billing before joining |
| mart_product_cohorts | One product-signup-week | Include numerator, denominator, maturity and coverage |
| mart_account_summary | One account at a stated as-of date | Preserve product-specific commercial status |

Never join event, membership, subscription and opportunity detail directly and then sum revenue. Aggregate each to the intended grain first. Version identity mappings where changes would otherwise rewrite history.

## Initial metric contracts

These are initial business rules for this scenario. Changes require a documented rationale, effective date, and assessment of historical comparability.

| Metric | Initial rule |
| --- | --- |
| Eligible signup | Non-test workspace created during the cohort period; exclusions documented |
| Product A activation | At least one successful synthetic workflow run within 7 days of signup |
| Product B activation | At least one successful synthetic asset materialization within 7 days of signup |
| 30-day signup-to-paid | Eligible workspaces with a qualifying linked payment within 30 days / eligible workspaces with a complete 30-day window |
| Paying companies | Distinct canonical accounts with an effective paid entitlement at the as-of time |
| Paying account-products | Distinct canonical account-product pairs with an effective paid entitlement |
| Identity coverage | Matched eligible workspaces / all eligible workspaces; unresolved records remain visible |

Use UTC, an explicit analysis cutoff and half-open intervals. Define a 30-day outcome as payment at or after signup and before signup + 30 days; require cutoff at or after signup + 30 days. Track late-arrival completeness separately from elapsed observation time.

Separate first acquisition route, sales assistance and current commercial arrangement. They are not one permanent self-serve/sales flag. Activation is a useful milestone, not necessarily a required chronological prerequisite for every purchase.

## Measurement risks and handling rules

For each case, explain: what can go wrong, which business number changes, the rule selected, alternatives rejected, and the test proving the result.

| ID / scope | Case and question to understand | Proposed handling and proof |
| --- | --- | --- |
| E01 / first version | Company buys both products. Why do product counts sum above company count? | Count account-product pairs separately; fixture expects 3 companies and 4 pairs |
| E02 / first version | Duplicate event deliveries inflate activation activity | Preserve deliveries; deduplicate logical events; rerun leaves outcomes unchanged |
| E03 / first version | Event naming changes create an apparent activation decline | Version event mappings by product and effective time; old/new fixtures normalize consistently; monitor unmapped names |
| E04 / first version | Recent cohorts have less time to pay | Exclude immature cohorts from mature conversion comparisons; test cutoff boundaries |
| E05 / first version | A workspace has no reliable company mapping | Keep it unresolved and report coverage; do not silently drop it or guess from email |
| E06 / extension | Consultant participates in several companies | Model memberships, not person-to-company uniqueness; ensure no company merge through the consultant |
| E07 / extension | Personal email later becomes company email | Require explicit identity evidence; retain provenance and historical validity |
| E08 / extension | Lead converts to contact in Salesforce | Link through conversion identifiers; preserve lifecycle history without double-counting the person |
| E09 / extension | Stages skip, regress or reopen | Use stage event history; distinguish first entry, re-entry and final close; never invent missing stage dates |
| E10 / extension | MQL status exists without an MQL timestamp | Flag unknown timing; disclose excluded denominator; do not substitute import time |
| E11 / extension | Self-serve customer signs enterprise contract | Preserve initial acquisition; classify subsequent revenue appropriately; count one customer |
| E12 / extension | Late events and old-record corrections bypass incremental builds | Bounded replay plus a documented older-change reconciliation strategy; compare incremental to full rebuild |
| E13 / extension | Campaign joins multiply opportunities or revenue | Use explicit bridges and weighted allocation; allocated totals reconcile to eligible base totals |
| E14 / extension | Tracking/source is missing | Preserve unknown attribution; report coverage; do not relabel missing as organic |
| E15 / extension | Spend arrives late, is unmapped, or uses another currency | Mark provisional periods, retain unallocated spend, document FX; reconcile source totals |
| E16 / extension | Subscription is refunded, canceled or overlapping | Derive paid entitlement by effective time; define net revenue separately; prevent overlap double counts |
| E17 / extension | Historical imports overwrite original dates | Preserve source event time separately from ingestion/import time; test that migration does not create acquisition spikes |
| E18 / extension | Source fields change type, disappear or stop populating | Check schema and completeness; fail or quarantine critical changes; expose impact on metric coverage |

## Synthetic investigation design

Generate clean underlying business activity first and retain an independent expected-results ledger. Then create corrupted source deliveries by introducing defects. This lets tests validate recovery against known truth rather than comparing two implementations of the same faulty rule.

Include one scenario with stable underlying conversion but misleading observed decline, and another with a real decline that remains after corrections. Do not force every anomaly to be a tracking issue. Explain how product/customer mix changes aggregate rates even when segment rates are stable.

Create small hand-checkable fixtures before generating a larger dataset. Do not choose impressive headline results before running the analysis.

## Validation and acceptance criteria

- [ ] Document grains, keys, definitions, exclusions and as-of policy.
- [ ] Test primary-key uniqueness, required keys and supported relationships.
- [ ] Verify E01 counts: 3 companies, 4 paying account-product pairs.
- [ ] Duplicate deliveries and reruns do not change logical outcomes.
- [ ] Both activation event versions produce expected results.
- [ ] Cohort boundary fixtures pass; immature cohorts are labeled.
- [ ] Unresolved identities appear in coverage and exception outputs.
- [ ] Payments reconcile at transaction grain before aggregation.
- [ ] Naive/corrected results reconcile through an adjustment breakdown, including interactions between defects.
- [ ] The real-decline scenario is still detected after measurement fixes.
- [ ] A clean environment can reproduce fixtures, models, tests and outputs with documented commands.
- [ ] No synthetic result is represented as a real company result.

## Later phases

1. Sales funnel: synthetic CRM stage history, stage conversion and velocity.
2. Attribution: first touch, last touch and a transparent linear baseline with defined windows, conversion unit and treatment of unknowns. Credit sums to one per eligible conversion. Attribution is descriptive, not causal proof.
3. Economics: distinguish media-only CAC from fully loaded CAC; align spend/customer periods and segments; calculate gross-margin-based payback. If a cohort has not paid back, report not yet observed rather than zero. Treat LTV as assumption-sensitive and optional.
4. Reporting: implement a real semantic layer when access permits; retain distinct-count and join protections, rather than only dashboard calculations.
5. Operations: orchestration, source freshness, retry behavior, backfills and recovery evidence. Pin dependencies and measure CI resource requirements before choosing hosting.

## Proposed folder structure

| Path | Purpose |
| --- | --- |
| PROJECT.md | Business context, scope, risks and decisions |
| README.md | Project overview, implementation status, key findings and reproducible run instructions |
| data_generation/ | Generator and independent truth ledger |
| dbt_project/ | dbt configuration, staging, intermediate and mart models |
| dbt_project/seeds/ | Small deterministic edge-case inputs |
| dbt_project/tests/ | Data assertions; unit-test definitions live with models as required by the chosen dbt version |
| metrics/ | Metric contracts and, later, implemented semantic models |
| docs/decisions/ | Tradeoffs, unresolved questions and definition versions |
| docs/investigation.md | Business question, evidence, conclusions and limitations |
| outputs/ | Synthetic result tables and reporting artifacts |
| .github/workflows/ | Reproducible build and validation checks |

The paths above describe the planned implementation. This specification does not imply that the models, tests, or reporting outputs already exist.

## Suggested pull requests

1. Define source tables and add sample data with expected customer counts.
2. Add canonical accounts and coverage reporting.
3. Normalize product events and define activation.
4. Add mature signup cohorts and linked paid outcomes.
5. Add shared account reporting and reconciliation checks.
6. Publish conversion investigation and reproducible build.

Each PR states the business problem, changed behavior, edge cases, validation actually performed, and relevant limitations. Never claim checks passed before running them.

## Delivery approach and next milestone

Deliver in small, independently reviewable changes. Establish expected business outcomes for each fixture before implementing its transformation. Record unresolved policy decisions explicitly and explain how they affect published metrics.

Next: build the three-company/four-account-product fixture and a few workspaces; validate counting units before adding events or funnel calculations.

## References

Verified November 4, 2026. Compatibility and hosted pricing should be checked again during implementation.

- dbt Core source and license: https://github.com/dbt-labs/dbt-core
- dbt Core open-source distribution explanation: https://docs.getdbt.com/blog/dbt-core-v2-is-here
- DuckDB adapter and installation/compatibility guidance: https://github.com/duckdb/dbt-duckdb
- DuckDB setup documentation: https://docs.getdbt.com/docs/local/connect-data-platform/duckdb-setup
