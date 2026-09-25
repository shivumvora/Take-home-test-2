{{ config(unique_key='customer_key') }}

{#
    Type 2 customer dimension: one row per customer version, plus an UNKNOWN~0 member
    that facts point to when no customer matches.

    valid_from / valid_to are the source change times. effective_from / effective_to are
    the join window used by facts: the first version reaches back to 1900-01-01 so an
    order placed before the customer record's timestamp (late-arriving dimension) still
    finds its customer, and the open version reaches forward to 9999-12-31.

    Incremental: only versions that are new or whose content changed (a closed valid_to,
    a deletion flag) are merged, detected by comparing _row_hash with the existing row.
#}

with versions as (

    select
        customer_version_id                                             as customer_key,
        customer_id,
        version_number,
        first_name,
        last_name,
        email,
        state_code,
        country_code,
        loyalty_tier,
        is_active,
        created_at,
        valid_from,
        valid_to,
        iff(version_number = 1, '1900-01-01'::timestamp_ntz, valid_from)    as effective_from,
        coalesce(valid_to, '9999-12-31'::timestamp_ntz)                     as effective_to,
        is_current,
        is_deleted_in_source
    from {{ ref('int_ecom__customers_history') }}

),

unknown_member as (

    select
        'UNKNOWN~0'                     as customer_key,
        'UNKNOWN'                       as customer_id,
        0                               as version_number,
        'Unknown'                       as first_name,
        'Unknown'                       as last_name,
        null::varchar                   as email,
        null::varchar                   as state_code,
        null::varchar                   as country_code,
        null::varchar                   as loyalty_tier,
        null::boolean                   as is_active,
        null::timestamp_ntz             as created_at,
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
        {{ hash_columns(['customer_key', 'first_name', 'last_name', 'email', 'state_code',
                         'country_code', 'loyalty_tier', 'is_active', 'created_at',
                         'valid_from', 'valid_to', 'is_current', 'is_deleted_in_source']) }} as _row_hash
    from all_members

)

select
    hashed.*,
    current_timestamp()::timestamp_ltz as _inserted_at,
    current_timestamp()::timestamp_ltz as _updated_at
from hashed
{% if is_incremental() %}
left join {{ this }} as existing
    on hashed.customer_key = existing.customer_key
where existing.customer_key is null
   or existing._row_hash != hashed._row_hash
{% endif %}
qualify row_number() over (partition by hashed.customer_key order by hashed.valid_from desc) = 1
