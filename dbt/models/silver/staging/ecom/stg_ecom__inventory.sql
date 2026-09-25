with source as (

    select * from {{ source('ecom', 'inventory') }}

),

renamed as (

    select
        -- keys
        try_to_date(trim(snapshot_date))                as snapshot_date,
        nullif(upper(trim(location_id)), '')            as location_id,
        nullif(trim(product_id), '')                    as product_id,

        -- measures
        try_to_number(trim(on_hand_qty))                as on_hand_qty,
        try_to_number(trim(reserved_qty))               as reserved_qty,
        try_to_number(trim(available_qty))              as available_qty,

        -- timestamps (UTC)
        {{ to_utc_timestamp('source_updated_at') }}     as source_updated_at,

        -- lineage
        {{ delivery_date_from_file() }}                 as delivery_date,
        _source_file_name,
        _source_file_row_number,
        _loaded_at

    from source

)

select
    *,
    {{ hash_columns(['snapshot_date', 'location_id', 'product_id', 'on_hand_qty',
                     'reserved_qty', 'available_qty']) }} as _record_hash
from renamed
