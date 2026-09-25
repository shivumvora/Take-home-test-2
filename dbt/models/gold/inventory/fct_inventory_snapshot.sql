{{ config(unique_key='inventory_snapshot_id') }}

{#
    Periodic snapshot fact. Grain: one row per snapshot_date + location + product.
    Key: inventory_snapshot_id (snapshot_date~location_id~product_id).

    Quantities are semi-additive: sum them across locations and products, never across
    dates. The product version is taken as of the snapshot time, so value at cost uses
    the cost in force that day.

    Incremental: merges snapshot rows loaded after the last run, plus rows still pointing
    at the UNKNOWN~0 product.
#}

with inventory as (

    select * from {{ ref('int_ecom__inventory_snapshots') }}

),

products as (

    select product_key, product_id, unit_cost, effective_from, effective_to
    from {{ ref('dim_product') }}

),

joined as (

    select
        inventory.inventory_snapshot_id,
        inventory.snapshot_date,
        inventory.location_id,
        coalesce(products.product_key, 'UNKNOWN~0')                 as product_key,
        inventory.product_id,
        inventory.on_hand_qty,
        inventory.reserved_qty,
        inventory.available_qty,
        inventory.on_hand_qty * products.unit_cost                  as on_hand_value_at_cost,
        inventory.source_updated_at,
        inventory._loaded_at                                        as _source_loaded_at
    from inventory
    left join products
        on inventory.product_id = products.product_id
       and coalesce(inventory.source_updated_at,
                    dateadd(second, -1, dateadd(day, 1, inventory.snapshot_date::timestamp_ntz)))
           >= products.effective_from
       and coalesce(inventory.source_updated_at,
                    dateadd(second, -1, dateadd(day, 1, inventory.snapshot_date::timestamp_ntz)))
           < products.effective_to

)

select
    joined.*,
    current_timestamp()::timestamp_ltz as _inserted_at,
    current_timestamp()::timestamp_ltz as _updated_at
from joined
{% if is_incremental() %}
where joined._source_loaded_at > (
        select coalesce(max(_source_loaded_at), '1900-01-01'::timestamp_ltz) from {{ this }})
   or joined.inventory_snapshot_id in (
        select inventory_snapshot_id from {{ this }} where product_key = 'UNKNOWN~0')
{% endif %}
qualify row_number() over (partition by joined.inventory_snapshot_id order by joined._source_loaded_at desc) = 1
