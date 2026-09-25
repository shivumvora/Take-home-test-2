{#
    One row per snapshot_date + location + product. If the same snapshot key is delivered
    more than once (a duplicate row or a re-sent file), the latest source_updated_at wins,
    then the most recently loaded row.
#}

with inventory_rows as (

    select * from {{ ref('stg_ecom__inventory') }}
    where snapshot_date is not null
      and location_id is not null
      and product_id is not null

),

deduplicated as (

    select
        to_varchar(snapshot_date, 'YYYY-MM-DD') || '~' || location_id || '~' || product_id
            as inventory_snapshot_id,
        *,
        count(*) over (partition by snapshot_date, location_id, product_id) as _source_row_count
    from inventory_rows
    qualify row_number() over (
        partition by snapshot_date, location_id, product_id
        order by source_updated_at desc nulls last, _loaded_at desc, _source_file_row_number desc
    ) = 1

)

select * from deduplicated
