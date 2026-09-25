{{ config(unique_key='order_id') }}

{#
    Order-level fact. Grain: one row per order (current version). Key: order_id.

    Carries the header amounts that exist only at order level (tax, shipping, total) and
    reconciles the header to its lines: is_reconciled is TRUE when
    subtotal - discount equals the sum of line net amounts.

    Incremental: merges orders whose header or any line was loaded after the last run,
    plus orders still pointing at the UNKNOWN~0 customer.
#}

with orders as (

    select * from {{ ref('int_ecom__orders_current') }}

),

line_totals as (

    select
        order_id,
        count(*)                                as line_count,
        sum(quantity)                           as units,
        sum(quantity * unit_price)              as lines_gross_amount,
        sum(line_discount_amount)               as lines_discount_amount,
        sum(line_total_amount)                  as lines_net_amount,
        max(_loaded_at)                         as lines_loaded_at
    from {{ ref('int_ecom__order_lines_current') }}
    group by order_id

),

customers as (

    select customer_key, customer_id, effective_from, effective_to
    from {{ ref('dim_customer') }}

),

joined as (

    select
        orders.order_id,
        orders.ordered_at::date                                     as order_date,
        orders.ordered_at,
        coalesce(customers.customer_key, 'UNKNOWN~0')               as customer_key,
        orders.customer_id,
        orders.order_status,
        coalesce(orders.order_status = 'CANCELLED', false)          as is_cancelled,
        orders.currency_code,
        orders.source_system,
        orders.subtotal_amount,
        orders.discount_amount,
        orders.tax_amount,
        orders.shipping_amount,
        orders.total_amount,
        coalesce(line_totals.line_count, 0)                         as line_count,
        line_totals.units,
        line_totals.lines_gross_amount,
        line_totals.lines_discount_amount,
        line_totals.lines_net_amount,
        coalesce(orders.subtotal_amount - orders.discount_amount = line_totals.lines_net_amount, false)
                                                                    as is_reconciled,
        greatest(orders._loaded_at, coalesce(line_totals.lines_loaded_at, orders._loaded_at))
                                                                    as _source_loaded_at
    from orders
    left join line_totals
        on orders.order_id = line_totals.order_id
    left join customers
        on orders.customer_id = customers.customer_id
       and orders.ordered_at >= customers.effective_from
       and orders.ordered_at < customers.effective_to

)

select
    joined.*,
    current_timestamp()::timestamp_ltz as _inserted_at,
    current_timestamp()::timestamp_ltz as _updated_at
from joined
{% if is_incremental() %}
where joined._source_loaded_at > (
        select coalesce(max(_source_loaded_at), '1900-01-01'::timestamp_ltz) from {{ this }})
   or joined.order_id in (
        select order_id from {{ this }} where customer_key = 'UNKNOWN~0')
{% endif %}
qualify row_number() over (partition by joined.order_id order by joined._source_loaded_at desc) = 1
