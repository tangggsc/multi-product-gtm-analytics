-- Each source key must map to at most one canonical company at any instant.
-- Fails on (a) intervals that end at or before they start and (b) any two
-- intervals for the same (source_system, source_account_id) that overlap.
-- Intervals are inclusive-start, exclusive-end; null valid_to is open-ended.
with mapping as (
    select
        *,
        row_number() over (
            partition by source_system, source_account_id order by valid_from
        ) as interval_seq
    from {{ ref('ref_account_mapping') }}
)

select
    'empty_or_inverted_interval' as failure, source_system, source_account_id,
    valid_from, valid_to, null::timestamptz as other_valid_from, null::timestamptz as other_valid_to
from mapping
where valid_to is not null and valid_to <= valid_from

union all

select
    'overlapping_intervals', a.source_system, a.source_account_id,
    a.valid_from, a.valid_to, b.valid_from, b.valid_to
from mapping a
join mapping b
    on a.source_system = b.source_system
   and a.source_account_id = b.source_account_id
   and a.interval_seq < b.interval_seq
where a.valid_from < coalesce(b.valid_to, 'infinity'::timestamptz)
  and b.valid_from < coalesce(a.valid_to, 'infinity'::timestamptz)
