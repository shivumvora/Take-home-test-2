{#
    Type 2 history from full-snapshot deliveries.

    Bronze keeps every delivered snapshot, so history is a pure function of bronze:
    rebuilding it from scratch always gives the same answer, and replaying a file
    cannot create extra versions.

      1. One row per key per delivery (latest updated_at wins if a delivery repeats a key).
      2. Keep a delivery's row only when its business content (_record_hash) differs from
         the previous delivery for that key. A->B->A therefore yields three versions.
      3. valid_from is the source updated_at of the version; valid_to is the next version's
         valid_from (exclusive). The open version has valid_to NULL and is_current TRUE.
      4. A key missing from the latest delivery is flagged is_deleted_in_source on its
         current version. Nothing is physically deleted.
#}
{% macro history_from_snapshots(relation, key_column, version_id_column) %}

with snapshots as (

    select *
    from {{ relation }}
    where {{ key_column }} is not null
    qualify row_number() over (
        partition by {{ key_column }}, delivery_date
        order by updated_at desc, _loaded_at desc, _source_file_row_number desc
    ) = 1

),

changes as (

    select *
    from snapshots
    qualify coalesce(
        lag(_record_hash) over (partition by {{ key_column }} order by delivery_date),
        '<first>'
    ) != _record_hash

),

latest_delivery as (

    select max(delivery_date) as latest_delivery_date
    from snapshots

),

last_seen as (

    select
        {{ key_column }},
        max(delivery_date) as last_seen_delivery_date
    from snapshots
    group by {{ key_column }}

),

versioned as (

    select
        changes.*,
        row_number() over (
            partition by changes.{{ key_column }} order by changes.delivery_date
        ) as version_number,
        changes.updated_at as valid_from,
        lead(changes.updated_at) over (
            partition by changes.{{ key_column }} order by changes.delivery_date
        ) as valid_to,
        last_seen.last_seen_delivery_date,
        latest_delivery.latest_delivery_date
    from changes
    inner join last_seen
        on changes.{{ key_column }} = last_seen.{{ key_column }}
    cross join latest_delivery

)

select
    {{ key_column }} || '~' || version_number as {{ version_id_column }},
    version_number,
    valid_from,
    valid_to,
    valid_to is null as is_current,
    valid_to is null and last_seen_delivery_date < latest_delivery_date as is_deleted_in_source,
    last_seen_delivery_date,
    * exclude (version_number, valid_from, valid_to, last_seen_delivery_date, latest_delivery_date)
      rename (delivery_date as first_seen_delivery_date)
from versioned

{% endmacro %}
