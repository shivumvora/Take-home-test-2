{#
    Current state of each order: the latest version received for every order_id.
    Exact duplicates and superseded versions collapse here, so re-delivered or replayed
    rows can never double-count. Ties on updated_at go to the most recently loaded row.
#}

with order_versions as (

    select * from {{ ref('stg_ecom__order_headers') }}
    where order_id is not null

),

latest as (

    select
        *,
        count(*) over (partition by order_id)                       as _source_row_count,
        count(distinct _record_hash) over (partition by order_id)   as _version_count
    from order_versions
    qualify row_number() over (
        partition by order_id
        order by updated_at desc nulls last, _loaded_at desc, _source_file_row_number desc
    ) = 1

)

select * from latest
