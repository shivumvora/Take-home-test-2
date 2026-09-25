{{ config(unique_key='location_id') }}

{#
    Stock-holding locations. Only the warehouse code is known today (from inventory);
    this is the conformed anchor for future fulfilment and store data.
#}

with locations as (

    select
        location_id,
        min(snapshot_date) as first_snapshot_date
    from {{ ref('int_ecom__inventory_snapshots') }}
    group by location_id

),

hashed as (

    select
        *,
        {{ hash_columns(['location_id', 'first_snapshot_date']) }} as _row_hash
    from locations

)

select
    hashed.*,
    current_timestamp()::timestamp_ltz as _inserted_at,
    current_timestamp()::timestamp_ltz as _updated_at
from hashed
{% if is_incremental() %}
left join {{ this }} as existing
    on hashed.location_id = existing.location_id
where existing.location_id is null
   or existing._row_hash != hashed._row_hash
{% endif %}
