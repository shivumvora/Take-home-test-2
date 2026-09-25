with source as (

    select * from {{ source('ecom', 'products') }}

),

renamed as (

    select
        -- key
        nullif(trim(product_id), '')                    as product_id,

        -- attributes
        nullif(upper(trim(sku)), '')                    as sku,
        nullif(trim(product_name), '')                  as product_name,
        nullif(trim(category), '')                      as category,
        nullif(trim(brand), '')                         as brand,
        try_to_number(trim(list_price), 12, 2)          as list_price,
        try_to_number(trim(unit_cost), 12, 2)           as unit_cost,
        try_to_boolean(trim(is_active))                 as is_active,

        -- timestamps (UTC)
        {{ to_utc_timestamp('updated_at') }}            as updated_at,

        -- lineage
        {{ delivery_date_from_file() }}                 as delivery_date,
        _source_file_name,
        _source_file_row_number,
        _loaded_at

    from source

)

select
    *,
    {{ hash_columns(['product_id', 'sku', 'product_name', 'category', 'brand',
                     'list_price', 'unit_cost', 'is_active']) }} as _record_hash
from renamed
