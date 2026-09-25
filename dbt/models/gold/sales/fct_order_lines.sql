{{ config(unique_key='order_line_id') }}

{#
    Primary sales fact. Grain: one row per order line (current version). Key: order_line_id.

    Revenue is taken from the lines, not the header subtotal, because the source uses
    subtotal inconsistently. Cancelled orders stay in the fact, flagged is_cancelled, and
    reporting excludes them from net sales.

    Customer and product versions are joined as of the order time, so price, cost and
    brand reflect the product when it was sold.

    Incremental: merges lines whose line or order header was loaded after the last run
    (a cancelled header re-states its lines), plus lines still pointing at an UNKNOWN~0
    member so late-arriving customers or products are picked up when they arrive.
#}

with lines as (

    select * from {{ ref('int_ecom__order_lines_current') }}

),

orders as (

    select * from {{ ref('int_ecom__orders_current') }}

),

customers as (

    select customer_key, customer_id, effective_from, effective_to
    from {{ ref('dim_customer') }}

),

products as (

    select product_key, product_id, unit_cost, effective_from, effective_to
    from {{ ref('dim_product') }}

),

joined as (

    select
        lines.order_line_id,
        lines.order_id,
        orders.ordered_at::date                                     as order_date,
        orders.ordered_at,
        coalesce(customers.customer_key, 'UNKNOWN~0')               as customer_key,
        coalesce(products.product_key, 'UNKNOWN~0')                 as product_key,
        orders.customer_id,
        lines.product_id,
        orders.order_status,
        coalesce(orders.order_status = 'CANCELLED', false)          as is_cancelled,
        orders.currency_code,
        lines.quantity,
        lines.unit_price,
        lines.quantity * lines.unit_price                           as gross_amount,
        lines.line_discount_amount                                  as discount_amount,
        lines.line_total_amount                                     as net_amount,
        lines.quantity * products.unit_cost                         as cost_amount,
        lines.line_total_amount - lines.quantity * products.unit_cost
                                                                    as margin_amount,
        greatest(lines._loaded_at, coalesce(orders._loaded_at, lines._loaded_at))
                                                                    as _source_loaded_at
    from lines
    left join orders
        on lines.order_id = orders.order_id
    left join customers
        on orders.customer_id = customers.customer_id
       and orders.ordered_at >= customers.effective_from
       and orders.ordered_at < customers.effective_to
    left join products
        on lines.product_id = products.product_id
       and orders.ordered_at >= products.effective_from
       and orders.ordered_at < products.effective_to

)

select
    joined.*,
    current_timestamp()::timestamp_ltz as _inserted_at,
    current_timestamp()::timestamp_ltz as _updated_at
from joined
{% if is_incremental() %}
where joined._source_loaded_at > (
        select coalesce(max(_source_loaded_at), '1900-01-01'::timestamp_ltz) from {{ this }})
   or joined.order_line_id in (
        select order_line_id from {{ this }}
        where customer_key = 'UNKNOWN~0' or product_key = 'UNKNOWN~0')
{% endif %}
qualify row_number() over (partition by joined.order_line_id order by joined._source_loaded_at desc) = 1
