-- Raw source tables (7). One definition for both products; rows are
-- distinguished by product and source-system identifiers.
-- Conventions: all timestamps are UTC (TIMESTAMPTZ); intervals are
-- inclusive-start / exclusive-end; amounts are fixed-precision decimals.
-- No primary keys are enforced here: raw tables must be able to hold
-- source defects (duplicates, nulls) so they stay inspectable. Key rules
-- are asserted by dbt source tests instead.

create schema if not exists raw;

-- One account record in one CRM system.
create or replace table raw.raw_crm_accounts (
    source_system        varchar,
    source_account_id    varchar,
    account_name         varchar,
    domain               varchar,
    created_at           timestamptz,
    updated_at           timestamptz,
    ingested_at          timestamptz
);

-- One user record within one product. Email is an attribute, not a company key.
create or replace table raw.raw_users (
    product              varchar,
    user_id              varchar,
    email                varchar,
    created_at           timestamptz,
    updated_at           timestamptz,
    ingested_at          timestamptz
);

-- One workspace within one product. Account-link fields may be null.
create or replace table raw.raw_workspaces (
    product                varchar,
    workspace_id           varchar,
    workspace_name         varchar,
    created_by_user_id     varchar,
    source_account_system  varchar,
    source_account_id      varchar,
    created_at             timestamptz,
    is_test                boolean,
    ingested_at            timestamptz
);

-- One user's membership interval in a workspace. Null valid_to = open-ended.
create or replace table raw.raw_workspace_memberships (
    product              varchar,
    membership_id        varchar,
    workspace_id         varchar,
    user_id              varchar,
    role                 varchar,
    valid_from           timestamptz,
    valid_to             timestamptz,
    ingested_at          timestamptz
);

-- One delivered copy of an event. (product, event_id) is the logical event.
create or replace table raw.raw_event_deliveries (
    product              varchar,
    delivery_id          varchar,
    event_id             varchar,
    workspace_id         varchar,
    user_id              varchar,
    event_name           varchar,
    occurred_at          timestamptz,
    ingested_at          timestamptz
);

-- One customer record in one billing system.
create or replace table raw.raw_billing_customers (
    source_system          varchar,
    billing_customer_id    varchar,
    customer_name          varchar,
    source_account_system  varchar,
    source_account_id      varchar,
    created_at             timestamptz,
    updated_at             timestamptz,
    ingested_at            timestamptz
);

-- One payment or refund transaction. Amounts are nonnegative; the
-- transaction type determines the sign of net cash.
create or replace table raw.raw_billing_transactions (
    source_system            varchar,
    transaction_id           varchar,
    billing_customer_id      varchar,
    product                  varchar,
    workspace_id             varchar,
    transaction_type         varchar,
    status                   varchar,
    amount                   decimal(18, 2),
    currency                 varchar,
    payment_at               timestamptz,
    service_period_start     timestamptz,
    service_period_end       timestamptz,
    original_transaction_id  varchar,
    ingested_at              timestamptz
);
