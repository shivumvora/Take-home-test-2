{#
    Current state of each order line: the latest version received for every line_id.
    Exact duplicates and superseded corrections collapse here. Ties on updated_at go to
    the most recently loaded row.
#}

with line_versions as (

    select * from {{ ref('stg_ecom__order_lines') }}
    where order_line_id is not null

),

latest as (

    select
        *,
        count(*) over (partition by order_line_id)                      as _source_row_count,
        count(distinct _record_hash) over (partition by order_line_id)  as _version_count
    from line_versions
    qualify row_number() over (
        partition by order_line_id
        order by updated_at desc nulls last, _loaded_at desc, _source_file_row_number desc
    ) = 1

)

select * from latest
