with source as (

    select * from {{ source('ecom', 'customers') }}

),

renamed as (

    select
        -- key
        nullif(trim(customer_id), '')                   as customer_id,

        -- attributes
        nullif(lower(trim(email)), '')                  as email,
        nullif(trim(first_name), '')                    as first_name,
        nullif(trim(last_name), '')                     as last_name,
        nullif(upper(trim(state)), '')                  as state_code,
        nullif(upper(trim(country)), '')                as country_code,
        nullif(trim(loyalty_tier), '')                  as loyalty_tier,
        try_to_boolean(trim(is_active))                 as is_active,

        -- timestamps (UTC)
        {{ to_utc_timestamp('created_at') }}            as created_at,
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
    {{ hash_columns(['customer_id', 'email', 'first_name', 'last_name', 'state_code',
                     'country_code', 'loyalty_tier', 'is_active', 'created_at']) }} as _record_hash
from renamed
