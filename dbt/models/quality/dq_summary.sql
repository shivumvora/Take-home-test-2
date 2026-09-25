{# Every data-quality check with its description and current issue count (zero included). #}

with checks (check_name, severity, description) as (

    select * from values
        ('duplicate_record_received',     'warn',  'The same record was delivered more than once (exact duplicate).'),
        ('missing_or_invalid_value',      'error', 'A required value is blank or could not be cast to its type.'),
        ('order_total_mismatch',          'error', 'Header total <> subtotal - discount + tax + shipping.'),
        ('line_total_mismatch',           'error', 'Line total <> quantity * unit_price - line_discount.'),
        ('inventory_available_mismatch',  'error', 'Available quantity <> on hand - reserved.'),
        ('header_lines_mismatch',         'warn',  'Header subtotal - discount does not equal the sum of line net amounts.'),
        ('header_subtotal_inconsistent',  'warn',  'Header subtotal matches neither the gross nor the net sum of its lines.'),
        ('unknown_dimension_member',      'warn',  'A fact row has no matching customer or product (late-arriving or missing).'),
        ('order_before_customer_created', 'warn',  'The order was placed before the customer record was created.'),
        ('cancelled_order_with_amount',   'info',  'A cancelled order still carries its amounts; reporting excludes it.'),
        ('deleted_in_source',             'info',  'A customer or product is missing from the latest snapshot delivery.')

),

issues as (

    select check_name, count(*) as issue_count
    from {{ ref('dq_issues') }}
    group by check_name

)

select
    checks.check_name,
    checks.severity,
    checks.description,
    coalesce(issues.issue_count, 0) as issue_count
from checks
left join issues
    on checks.check_name = issues.check_name
order by
    case checks.severity when 'error' then 1 when 'warn' then 2 else 3 end,
    checks.check_name
