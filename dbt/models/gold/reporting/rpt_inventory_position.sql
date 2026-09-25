{#
    Current inventory position: the latest snapshot for every location and product,
    with product attributes as of that snapshot and stock value at cost.
#}

with latest_snapshot as (

    select max(snapshot_date) as snapshot_date
    from {{ ref('fct_inventory_snapshot') }}

)

select
    inventory.snapshot_date,
    inventory.location_id,
    products.product_id,
    products.sku,
    products.product_name,
    products.brand,
    products.category,
    products.is_active                  as is_product_active,
    inventory.on_hand_qty,
    inventory.reserved_qty,
    inventory.available_qty,
    products.unit_cost,
    inventory.on_hand_value_at_cost
from {{ ref('fct_inventory_snapshot') }} as inventory
inner join latest_snapshot
    on inventory.snapshot_date = latest_snapshot.snapshot_date
inner join {{ ref('dim_product') }} as products
    on inventory.product_key = products.product_key
