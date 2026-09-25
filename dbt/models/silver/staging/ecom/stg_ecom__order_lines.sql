with source as (

    select * from {{ source('ecom', 'order_lines') }}

),

renamed as (

    select
        -- keys
        nullif(trim(line_id), '')                       as order_line_id,
        nullif(trim(order_id), '')                      as order_id,
        nullif(trim(product_id), '')                    as product_id,

        -- measures
        try_to_number(trim(quantity))                   as quantity,
        try_to_number(trim(unit_price), 12, 2)          as unit_price,
        try_to_number(trim(line_discount), 12, 2)       as line_discount_amount,
        try_to_number(trim(line_total), 12, 2)          as line_total_amount,

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
    {{ hash_columns(['order_line_id', 'order_id', 'product_id', 'quantity', 'unit_price',
                     'line_discount_amount', 'line_total_amount']) }} as _record_hash
from renamed
