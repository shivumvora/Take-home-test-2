with source as (

    select * from {{ source('ecom', 'order_headers') }}

),

renamed as (

    select
        -- keys
        nullif(trim(order_id), '')                      as order_id,
        nullif(trim(customer_id), '')                   as customer_id,

        -- attributes
        nullif(upper(trim(status)), '')                 as order_status,
        nullif(upper(trim(currency)), '')               as currency_code,
        nullif(upper(trim(source_system)), '')          as source_system,

        -- amounts
        try_to_number(trim(subtotal), 12, 2)            as subtotal_amount,
        try_to_number(trim(discount), 12, 2)            as discount_amount,
        try_to_number(trim(tax), 12, 2)                 as tax_amount,
        try_to_number(trim(shipping), 12, 2)            as shipping_amount,
        try_to_number(trim(total), 12, 2)               as total_amount,

        -- timestamps (UTC)
        {{ to_utc_timestamp('order_ts') }}              as ordered_at,
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
    {{ hash_columns(['order_id', 'customer_id', 'order_status', 'currency_code', 'source_system',
                     'subtotal_amount', 'discount_amount', 'tax_amount', 'shipping_amount',
                     'total_amount', 'ordered_at']) }} as _record_hash
from renamed
