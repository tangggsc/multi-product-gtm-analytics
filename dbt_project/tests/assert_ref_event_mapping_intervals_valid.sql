-- Each (product, source_event_name) must have at most one meaning at any
-- instant. Fails on empty/inverted intervals and on overlapping intervals.
-- Intervals are inclusive-start, exclusive-end; null valid_to is open-ended.
with mapping as (
    select
        *,
        row_number() over (
            partition by product, source_event_name order by valid_from
        ) as interval_seq
    from {{ ref('ref_event_mapping') }}
)

select
    'empty_or_inverted_interval' as failure, product, source_event_name,
    valid_from, valid_to, null::timestamptz as other_valid_from, null::timestamptz as other_valid_to
from mapping
where valid_to is not null and valid_to <= valid_from

union all

select
    'overlapping_intervals', a.product, a.source_event_name,
    a.valid_from, a.valid_to, b.valid_from, b.valid_to
from mapping a
join mapping b
    on a.product = b.product
   and a.source_event_name = b.source_event_name
   and a.interval_seq < b.interval_seq
where a.valid_from < coalesce(b.valid_to, 'infinity'::timestamptz)
  and b.valid_from < coalesce(a.valid_to, 'infinity'::timestamptz)
