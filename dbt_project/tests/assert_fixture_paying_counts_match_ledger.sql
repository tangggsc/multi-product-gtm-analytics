-- Fixture sanity check: counts derived directly from raw billing records and
-- the account mapping must equal the hand-written expected ledger at every
-- as-of time in the ledger. This proves the fixture encodes the intended
-- counting units (E01) before any mart models exist. Later PRs will test the
-- mart models against the same ledger.
--
-- Paid entitlement rule used here (initial fixture scope):
--   successful payment whose service period covers the as-of time,
--   service_period_start <= as_of < service_period_end.
-- Refund and cancellation effects on entitlement are out of scope until
-- subscription history exists (see PROJECT.md, E16).

with as_of_points as (
    select distinct as_of from {{ source('expected', 'paying_counts') }}
),

products as (
    select unnest(['A', 'B']) as product
),

entitled_payments as (
    select
        p.as_of,
        t.source_system,
        t.transaction_id,
        t.product,
        t.workspace_id,
        m.canonical_account_id
    from as_of_points p
    join {{ source('raw', 'raw_billing_transactions') }} t
        on t.transaction_type = 'payment'
       and t.status = 'succeeded'
       and t.service_period_start <= p.as_of
       and p.as_of < t.service_period_end
    left join {{ ref('ref_account_mapping') }} m
        on m.source_system = t.source_system
       and m.source_account_id = t.billing_customer_id
       and p.as_of >= m.valid_from
       and (p.as_of < m.valid_to or m.valid_to is null)
),

actual as (
    select p.as_of, 'paying_companies' as metric, null::varchar as product,
           count(distinct e.canonical_account_id) as actual_value
    from as_of_points p left join entitled_payments e using (as_of)
    group by p.as_of

    union all

    select p.as_of, 'paying_account_products', null,
           count(distinct e.canonical_account_id || '|' || e.product)
    from as_of_points p left join entitled_payments e using (as_of)
    group by p.as_of

    union all

    select p.as_of, 'paying_accounts', pr.product,
           count(distinct e.canonical_account_id)
    from as_of_points p
    cross join products pr
    left join entitled_payments e
        on e.as_of = p.as_of and e.product = pr.product
    group by p.as_of, pr.product

    union all

    select p.as_of, 'paying_workspaces', null,
           count(distinct e.product || '|' || e.workspace_id)
    from as_of_points p left join entitled_payments e using (as_of)
    group by p.as_of
),

expected as (
    select as_of, metric, product, expected_value
    from {{ source('expected', 'paying_counts') }}
),

count_mismatches as (
    select
        'count_mismatch' as failure,
        coalesce(a.as_of, x.as_of) as as_of,
        coalesce(a.metric, x.metric) as metric,
        coalesce(a.product, x.product) as product,
        x.expected_value,
        a.actual_value
    from actual a
    full outer join expected x
        on a.as_of = x.as_of
       and a.metric = x.metric
       and a.product is not distinct from x.product
    where x.expected_value is distinct from a.actual_value
),

-- Distinct counts silently ignore nulls, so an unmapped billing customer
-- would shrink the counts without failing them. Surface it explicitly.
unmapped_entitled_payments as (
    select
        'entitled_payment_without_account_mapping' as failure,
        as_of,
        source_system || '|' || transaction_id as metric,
        product,
        null::integer as expected_value,
        null::bigint as actual_value
    from entitled_payments
    where canonical_account_id is null
)

select * from count_mismatches
union all
select * from unmapped_entitled_payments
