{#
    Daily sales by brand and category. Net sales, units, cost and margin exclude
    cancelled orders; cancelled orders are counted separately so cancellations stay visible.
    Brand and category are the product's attributes at the time of sale.
#}

select
    lines.order_date,
    dates.iso_week_number,
    dates.month_start_date,
    products.brand,
    products.category,
    count(distinct iff(not lines.is_cancelled, lines.order_id, null))       as order_count,
    count(distinct iff(lines.is_cancelled, lines.order_id, null))           as cancelled_order_count,
    sum(iff(not lines.is_cancelled, lines.quantity, 0))                     as units_sold,
    sum(iff(not lines.is_cancelled, lines.gross_amount, 0))                 as gross_sales_amount,
    sum(iff(not lines.is_cancelled, lines.discount_amount, 0))              as discount_amount,
    sum(iff(not lines.is_cancelled, lines.net_amount, 0))                   as net_sales_amount,
    sum(iff(not lines.is_cancelled, lines.cost_amount, 0))                  as cost_amount,
    sum(iff(not lines.is_cancelled, lines.margin_amount, 0))                as gross_margin_amount,
    div0(sum(iff(not lines.is_cancelled, lines.margin_amount, 0)),
         sum(iff(not lines.is_cancelled, lines.net_amount, 0)))             as gross_margin_pct,
    sum(iff(lines.is_cancelled, lines.net_amount, 0))                       as cancelled_net_amount
from {{ ref('fct_order_lines') }} as lines
inner join {{ ref('dim_product') }} as products
    on lines.product_key = products.product_key
left join {{ ref('dim_date') }} as dates
    on lines.order_date = dates.date_day
group by all
