{{ config(unique_key='product_key') }}

{#
    Type 2 product dimension: one row per product version, plus an UNKNOWN~0 member.
    Brand and category are attributes here; brand becomes its own dimension once it
    carries attributes of its own.

    Same conventions as dim_customer: effective_from / effective_to are the fact join
    window (first version from 1900-01-01, open version to 9999-12-31), and only new or
    changed versions are merged, detected by _row_hash.
#}

with versions as (

    select
        product_version_id                                              as product_key,
        product_id,
        version_number,
        sku,
        product_name,
        brand,
        category,
        list_price,
        unit_cost,
        is_active,
        valid_from,
        valid_to,
        iff(version_number = 1, '1900-01-01'::timestamp_ntz, valid_from)    as effective_from,
        coalesce(valid_to, '9999-12-31'::timestamp_ntz)                     as effective_to,
        is_current,
        is_deleted_in_source
    from {{ ref('int_ecom__products_history') }}

),

unknown_member as (

    select
        'UNKNOWN~0'                     as product_key,
        'UNKNOWN'                       as product_id,
        0                               as version_number,
        null::varchar                   as sku,
        'Unknown'                       as product_name,
        'Unknown'                       as brand,
        'Unknown'                       as category,
        null::number(12, 2)             as list_price,
        null::number(12, 2)             as unit_cost,
        null::boolean                   as is_active,
        '1900-01-01'::timestamp_ntz     as valid_from,
        null::timestamp_ntz             as valid_to,
        '1900-01-01'::timestamp_ntz     as effective_from,
        '9999-12-31'::timestamp_ntz     as effective_to,
        true                            as is_current,
        false                           as is_deleted_in_source

),

all_members as (

    select * from versions
    union all
    select * from unknown_member

),

hashed as (

    select
        *,
        {{ hash_columns(['product_key', 'sku', 'product_name', 'brand', 'category',
                         'list_price', 'unit_cost', 'is_active', 'valid_from', 'valid_to',
                         'is_current', 'is_deleted_in_source']) }} as _row_hash
    from all_members

)

select
    hashed.*,
    current_timestamp()::timestamp_ltz as _inserted_at,
    current_timestamp()::timestamp_ltz as _updated_at
from hashed
{% if is_incremental() %}
left join {{ this }} as existing
    on hashed.product_key = existing.product_key
where existing.product_key is null
   or existing._row_hash != hashed._row_hash
{% endif %}
qualify row_number() over (partition by hashed.product_key order by hashed.valid_from desc) = 1
