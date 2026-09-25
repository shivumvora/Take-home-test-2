{#
    One row per detected data-quality issue across silver and gold.
    severity: error = the data is wrong; warn = needs review; info = expected behaviour
    that is worth tracking. The check catalogue with descriptions is in dq_summary.
#}

with

-- Identical rows received more than once. Incremental entities: same key, content and
-- updated_at in any files. Snapshot entities: same key twice within one delivery file.
duplicate_records as (

    select 'duplicate_record_received' as check_name, 'warn' as severity, 'order_header' as entity,
           order_id as record_key,
           count(*) || ' identical rows in ' || listagg(distinct _source_file_name, ', ') as detail
    from {{ ref('stg_ecom__order_headers') }}
    group by order_id, _record_hash, updated_at
    having count(*) > 1

    union all

    select 'duplicate_record_received', 'warn', 'order_line', order_line_id,
           count(*) || ' identical rows in ' || listagg(distinct _source_file_name, ', ')
    from {{ ref('stg_ecom__order_lines') }}
    group by order_line_id, _record_hash, updated_at
    having count(*) > 1

    union all

    select 'duplicate_record_received', 'warn', 'customer', customer_id,
           count(*) || ' rows in ' || _source_file_name
    from {{ ref('stg_ecom__customers') }}
    group by customer_id, _source_file_name
    having count(*) > 1

    union all

    select 'duplicate_record_received', 'warn', 'product', product_id,
           count(*) || ' rows in ' || _source_file_name
    from {{ ref('stg_ecom__products') }}
    group by product_id, _source_file_name
    having count(*) > 1

    union all

    select 'duplicate_record_received', 'warn', 'inventory',
           to_varchar(snapshot_date, 'YYYY-MM-DD') || '~' || location_id || '~' || product_id,
           count(*) || ' rows in ' || _source_file_name
    from {{ ref('stg_ecom__inventory') }}
    group by snapshot_date, location_id, product_id, _source_file_name
    having count(*) > 1

),

-- Required values that are blank or could not be cast to their type in staging.
missing_or_invalid_values as (

    select 'missing_or_invalid_value' as check_name, 'error' as severity, 'order_header' as entity,
           coalesce(order_id, _source_file_name || '#' || _source_file_row_number) as record_key,
           'blank or invalid: ' || array_to_string(array_construct_compact(
               iff(order_id is null, 'order_id', null), iff(customer_id is null, 'customer_id', null),
               iff(ordered_at is null, 'order_ts', null), iff(order_status is null, 'status', null),
               iff(total_amount is null, 'total', null), iff(updated_at is null, 'updated_at', null)), ', ') as detail
    from {{ ref('stg_ecom__order_headers') }}
    where order_id is null or customer_id is null or ordered_at is null or order_status is null
       or total_amount is null or updated_at is null

    union all

    select 'missing_or_invalid_value', 'error', 'order_line',
           coalesce(order_line_id, _source_file_name || '#' || _source_file_row_number),
           'blank or invalid: ' || array_to_string(array_construct_compact(
               iff(order_line_id is null, 'line_id', null), iff(order_id is null, 'order_id', null),
               iff(product_id is null, 'product_id', null), iff(quantity is null, 'quantity', null),
               iff(unit_price is null, 'unit_price', null), iff(line_total_amount is null, 'line_total', null),
               iff(updated_at is null, 'updated_at', null)), ', ')
    from {{ ref('stg_ecom__order_lines') }}
    where order_line_id is null or order_id is null or product_id is null or quantity is null
       or unit_price is null or line_total_amount is null or updated_at is null

    union all

    select 'missing_or_invalid_value', 'error', 'inventory',
           _source_file_name || '#' || _source_file_row_number,
           'blank or invalid: ' || array_to_string(array_construct_compact(
               iff(snapshot_date is null, 'snapshot_date', null), iff(location_id is null, 'location_id', null),
               iff(product_id is null, 'product_id', null), iff(on_hand_qty is null, 'on_hand_qty', null),
               iff(reserved_qty is null, 'reserved_qty', null), iff(available_qty is null, 'available_qty', null)), ', ')
    from {{ ref('stg_ecom__inventory') }}
    where snapshot_date is null or location_id is null or product_id is null
       or on_hand_qty is null or reserved_qty is null or available_qty is null

),

-- Arithmetic that must hold within a record.
arithmetic as (

    select 'order_total_mismatch' as check_name, 'error' as severity, 'order_header' as entity,
           order_id as record_key,
           'total ' || total_amount || ' <> subtotal - discount + tax + shipping = '
               || (subtotal_amount - discount_amount + tax_amount + shipping_amount) as detail
    from {{ ref('int_ecom__orders_current') }}
    where total_amount != subtotal_amount - discount_amount + tax_amount + shipping_amount

    union all

    select 'line_total_mismatch', 'error', 'order_line', order_line_id,
           'line_total ' || line_total_amount || ' <> quantity * unit_price - line_discount = '
               || (quantity * unit_price - line_discount_amount)
    from {{ ref('int_ecom__order_lines_current') }}
    where line_total_amount != quantity * unit_price - line_discount_amount

    union all

    select 'inventory_available_mismatch', 'error', 'inventory', inventory_snapshot_id,
           'available ' || available_qty || ' <> on_hand - reserved = ' || (on_hand_qty - reserved_qty)
    from {{ ref('int_ecom__inventory_snapshots') }}
    where available_qty != on_hand_qty - reserved_qty

),

-- Header and lines of the same order disagree.
order_consistency as (

    select 'header_lines_mismatch' as check_name, 'warn' as severity, 'order' as entity,
           order_id as record_key,
           'subtotal - discount = ' || (subtotal_amount - discount_amount)
               || ' but lines net = ' || coalesce(to_varchar(lines_net_amount), 'no lines') as detail
    from {{ ref('fct_orders') }}
    where not is_reconciled

    union all

    select 'header_subtotal_inconsistent', 'warn', 'order', order_id,
           'subtotal ' || subtotal_amount || ' matches neither lines gross ' || lines_gross_amount
               || ' nor lines net ' || lines_net_amount
               || '; header discount ' || discount_amount || ' vs line discounts ' || lines_discount_amount
    from {{ ref('fct_orders') }}
    where line_count > 0
      and subtotal_amount != lines_gross_amount
      and subtotal_amount != lines_net_amount

),

-- Relationships and timing across entities.
referential as (

    select 'unknown_dimension_member' as check_name, 'warn' as severity, 'order_line' as entity,
           order_line_id as record_key,
           'no match for ' || array_to_string(array_construct_compact(
               iff(customer_key = 'UNKNOWN~0', 'customer ' || coalesce(customer_id, '<null>'), null),
               iff(product_key = 'UNKNOWN~0', 'product ' || coalesce(product_id, '<null>'), null)), ', ') as detail
    from {{ ref('fct_order_lines') }}
    where customer_key = 'UNKNOWN~0' or product_key = 'UNKNOWN~0'

    union all

    select 'unknown_dimension_member', 'warn', 'inventory', inventory_snapshot_id,
           'no match for product ' || coalesce(product_id, '<null>')
    from {{ ref('fct_inventory_snapshot') }}
    where product_key = 'UNKNOWN~0'

    union all

    select 'order_before_customer_created', 'warn', 'order', orders.order_id,
           'ordered_at ' || orders.ordered_at || ' is before customer ' || orders.customer_id
               || ' created_at ' || customers.created_at
    from {{ ref('fct_orders') }} as orders
    inner join {{ ref('dim_customer') }} as customers
        on orders.customer_id = customers.customer_id
       and customers.version_number = 1
    where orders.ordered_at < customers.created_at

),

-- Expected behaviour worth tracking.
informational as (

    select 'cancelled_order_with_amount' as check_name, 'info' as severity, 'order' as entity,
           order_id as record_key,
           'status CANCELLED but total ' || total_amount || ' retained; excluded from net sales' as detail
    from {{ ref('fct_orders') }}
    where is_cancelled and total_amount != 0

    union all

    select 'deleted_in_source', 'info', 'customer', customer_id,
           'missing from the latest customer snapshot'
    from {{ ref('dim_customer') }}
    where is_current and is_deleted_in_source

    union all

    select 'deleted_in_source', 'info', 'product', product_id,
           'missing from the latest product snapshot'
    from {{ ref('dim_product') }}
    where is_current and is_deleted_in_source

)

select * from duplicate_records
union all select * from missing_or_invalid_values
union all select * from arithmetic
union all select * from order_consistency
union all select * from referential
union all select * from informational
