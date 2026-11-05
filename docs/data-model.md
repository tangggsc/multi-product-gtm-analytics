# Data Model

How the source data connects, and how the cleaned analytics tables are built from it.

- [1. Source relationship diagram](#1-source-relationship-diagram): the 7 raw tables and 2 reference tables
- [2. Analytics star schema](#2-analytics-star-schema): the cleaned dbt facts and dimensions *(not yet written)*

All data is synthetic. Table and column definitions live in [raw_schema.sql](../data_generation/raw_schema.sql) and [_sources.yml](../dbt_project/models/staging/_sources.yml).

---

## 1. Source relationship diagram

```mermaid
erDiagram
    raw_crm_accounts {
        string source_system PK "crm_a | crm_b"
        string source_account_id PK "unique only within source_system"
        string account_name
        string domain "attribute, never a merge key"
    }

    raw_users {
        string product PK "A | B"
        string user_id PK "unique only within product"
        string email "attribute, not a company key"
    }

    raw_workspaces {
        string product PK
        string workspace_id PK "unique only within product"
        string created_by_user_id FK
        string source_account_system FK "nullable"
        string source_account_id FK "nullable"
        timestamptz created_at "signup cohort"
        boolean is_test
    }

    raw_workspace_memberships {
        string product PK
        string membership_id PK
        string workspace_id FK
        string user_id FK
        string role
        timestamptz valid_from "inclusive"
        timestamptz valid_to "exclusive, null = open"
    }

    raw_event_deliveries {
        string product PK
        string delivery_id PK "one delivered copy"
        string event_id "logical event = product + event_id"
        string workspace_id FK
        string user_id FK "nullable, system events"
        string event_name FK
        timestamptz occurred_at "business time"
        timestamptz ingested_at "arrival time"
    }

    raw_billing_customers {
        string source_system PK "billing_a | billing_b"
        string billing_customer_id PK
        string customer_name
        string source_account_system FK "nullable"
        string source_account_id FK "nullable"
    }

    raw_billing_transactions {
        string source_system PK
        string transaction_id PK
        string billing_customer_id FK
        string product FK
        string workspace_id FK "nullable, explicit link only"
        string transaction_type "payment | refund"
        string status "succeeded | failed | pending"
        decimal amount "nonnegative"
        timestamptz payment_at
        timestamptz service_period_start "inclusive"
        timestamptz service_period_end "exclusive"
        string original_transaction_id FK "refund to payment"
    }

    ref_account_mapping {
        string source_system PK "crm_* or billing_*"
        string source_account_id PK "CRM account or billing customer ID"
        timestamptz valid_from PK "inclusive"
        timestamptz valid_to "exclusive, null = open"
        string canonical_account_id "the company"
        string match_method
        string evidence_reference
    }

    ref_event_mapping {
        string product PK
        string source_event_name PK
        timestamptz valid_from PK "inclusive"
        timestamptz valid_to "exclusive, null = open"
        string normalized_event_name
        boolean qualifies_for_activation
    }

    raw_crm_accounts          |o--o{ raw_workspaces            : "owns (optional link)"
    raw_crm_accounts          |o--o{ raw_billing_customers     : "billed as (optional link)"
    raw_users                 ||--o{ raw_workspaces            : "creates"
    raw_users                 ||--o{ raw_workspace_memberships : "holds"
    raw_workspaces            ||--o{ raw_workspace_memberships : "has members"
    raw_workspaces            ||--o{ raw_event_deliveries      : "emits"
    raw_users                 |o--o{ raw_event_deliveries      : "acts in (nullable)"
    raw_billing_customers     ||--o{ raw_billing_transactions  : "pays"
    raw_workspaces            |o--o{ raw_billing_transactions  : "paid for (optional link)"
    raw_billing_transactions  |o--o{ raw_billing_transactions  : "refund of"
    raw_crm_accounts          ||--o{ ref_account_mapping       : "resolved by (per interval)"
    raw_billing_customers     ||--o{ ref_account_mapping       : "resolved by (per interval)"
    ref_event_mapping         |o--o{ raw_event_deliveries      : "interprets (by occurred_at)"
```

**How to read it:** `||` means exactly one, `|o` zero or one, and `o{` zero or many. Keys marked `PK` are composite: every ID is unique only within its product or source system.

### Join keys

| From | To | Join on | Cardinality |
| --- | --- | --- | --- |
| `raw_workspaces` | `raw_crm_accounts` | `source_account_system = source_system` and `source_account_id` | Many workspaces to 0..1 account. Null link means unresolved, never guessed |
| `raw_billing_customers` | `raw_crm_accounts` | `source_account_system = source_system` and `source_account_id` | Many billing customers to 0..1 account |
| `raw_workspaces` | `raw_users` | `product` and `created_by_user_id = user_id` | Many workspaces to one creator |
| `raw_workspace_memberships` | `raw_workspaces` | `product` and `workspace_id` | Many memberships to one workspace |
| `raw_workspace_memberships` | `raw_users` | `product` and `user_id` | Many memberships to one user |
| `raw_event_deliveries` | `raw_workspaces` | `product` and `workspace_id` | Many deliveries to one workspace |
| `raw_event_deliveries` | `raw_users` | `product` and `user_id` | Many deliveries to 0..1 user (null for system events) |
| `raw_event_deliveries` | `ref_event_mapping` | `product`, `event_name = source_event_name`, and `valid_from <= occurred_at < valid_to` | Each delivery to 0..1 mapping. Unmapped names stay visible |
| `raw_billing_transactions` | `raw_billing_customers` | `source_system` and `billing_customer_id` | Many transactions to one billing customer |
| `raw_billing_transactions` | `raw_workspaces` | `product` and `workspace_id` | Many transactions to 0..1 workspace. Unlinked payments are kept, not guessed |
| `raw_billing_transactions` (refund) | `raw_billing_transactions` (payment) | `source_system` and `original_transaction_id = transaction_id` | Many refunds to one payment |
| `raw_crm_accounts` | `ref_account_mapping` | `source_system` and `source_account_id`, with the validity interval at a stated `business_at` | One source record to many intervals, at most one valid at any moment |
| `raw_billing_customers` | `ref_account_mapping` | `source_system` and `billing_customer_id = source_account_id`, with the validity interval | Same as above |

### Many-to-many relationships

These relationships have no direct foreign key. Each one is resolved through another table:

| Relationship | Resolved through | Why it matters |
| --- | --- | --- |
| Users ↔ workspaces | `raw_workspace_memberships` | One person, such as a consultant, can belong to several companies' workspaces. A person never determines a company |
| Source records ↔ companies | `ref_account_mapping.canonical_account_id` | One company appears as several CRM accounts and billing customers across systems, such as Acme as crm_a/101, crm_b/987, cus_a_001 and cus_b_001 |
| Billing customers ↔ workspaces | `raw_billing_transactions` | One billing customer can pay for several workspaces, such as Acme's ws_100 and ws_101 |
| Event deliveries ↔ logical events | `(product, event_id)` | Retries create several delivery rows for one event. Dedupe is a staging step, not a raw deletion |

### Rules the diagram cannot show

- **Always join on the namespace too.** `crm_a/101` and `crm_b/101` are different companies, and `A/ws_100` and `B/ws_100` are different workspaces. A join on the ID alone silently merges them.
- **Interval joins need an explicit time.** Mapping joins use inclusive start and exclusive end. The consuming model must say which timestamp it uses: workspace `created_at` for signup ownership, `payment_at` for payments, an as-of time for current reporting, and `occurred_at` (not `ingested_at`) for event names.
- **No canonical company table exists in raw.** `canonical_account_id` appears only in `ref_account_mapping`. `dim_accounts` will be built from it in the analytics layer.
- **Aggregate before joining.** Joining events, memberships and transactions directly multiplies rows. Each is aggregated to the target grain first (see section 2).

---

## 2. Analytics star schema

*Not yet written.*
