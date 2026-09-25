-- Sales and order reporting on the gold star schema.
-- Net sales = line totals after line discounts, excluding cancelled orders.
-- Revenue comes from the lines, not the header subtotal (see README: data quirks).

USE ROLE CANDIDATE_SHIVUM_ROLE;
USE WAREHOUSE CANDIDATE_SHIVUM_WH;
USE DATABASE CANDIDATE_SHIVUM;

-- 1. Daily sales summary: one row per order date.
--    O1005 was placed on Sep 1 and cancelled on Day 2, so it shows as a cancelled order on Sep 1.
SELECT
    order_date,
    COUNT(DISTINCT IFF(NOT is_cancelled, order_id, NULL))   AS orders,
    COUNT(DISTINCT IFF(is_cancelled, order_id, NULL))       AS cancelled_orders,
    SUM(IFF(NOT is_cancelled, quantity, 0))                 AS units,
    SUM(IFF(NOT is_cancelled, gross_amount, 0))             AS gross_sales,
    SUM(IFF(NOT is_cancelled, discount_amount, 0))          AS discounts,
    SUM(IFF(NOT is_cancelled, net_amount, 0))               AS net_sales,
    SUM(IFF(NOT is_cancelled, margin_amount, 0))            AS gross_margin,
    ROUND(DIV0(net_sales, orders), 2)                       AS avg_order_value
FROM GOLD.FCT_ORDER_LINES
GROUP BY order_date
ORDER BY order_date;

-- 2. Net sales by brand and category, from the reporting view.
--    Brand and category are the product's attributes at the time of sale.
SELECT
    brand,
    category,
    SUM(units_sold)                                                         AS units,
    SUM(net_sales_amount)                                                   AS net_sales,
    SUM(gross_margin_amount)                                                AS gross_margin,
    ROUND(DIV0(SUM(gross_margin_amount), SUM(net_sales_amount)) * 100, 1)   AS margin_pct
FROM GOLD.V_RPT_DAILY_SALES
GROUP BY brand, category
ORDER BY net_sales DESC;

-- 3. Orders by status, with header amounts next to line net sales.
--    Header totals include tax and shipping; cancelled orders keep their amounts in the source.
SELECT
    order_status,
    COUNT(*)                    AS orders,
    SUM(lines_net_amount)       AS line_net_sales,
    SUM(tax_amount)             AS tax,
    SUM(shipping_amount)        AS shipping,
    SUM(total_amount)           AS order_totals,
    COUNT_IF(is_reconciled)     AS orders_reconciled_to_lines
FROM GOLD.FCT_ORDERS
GROUP BY order_status
ORDER BY order_status;

-- 4. Customer sales with loyalty tier at the time of each order vs today (type 2 in action).
--    C007 ordered as Silver on Day 1 and is Gold now; the order stays attributed to Silver.
SELECT
    f.customer_id,
    cur.first_name || ' ' || cur.last_name                                  AS customer,
    LISTAGG(DISTINCT hist.loyalty_tier, ', ')                               AS tier_when_ordered,
    cur.loyalty_tier                                                        AS tier_today,
    COUNT(DISTINCT f.order_id)                                              AS orders,
    SUM(f.net_amount)                                                       AS net_sales
FROM GOLD.FCT_ORDER_LINES AS f
INNER JOIN GOLD.DIM_CUSTOMER AS hist
    ON f.customer_key = hist.customer_key
INNER JOIN GOLD.DIM_CUSTOMER AS cur
    ON cur.customer_id = hist.customer_id
   AND cur.is_current
WHERE NOT f.is_cancelled
GROUP BY f.customer_id, customer, tier_today
ORDER BY net_sales DESC;

-- 5. Top products by net sales, with every price they actually sold at.
--    P004 sold at 70.00 before its Day 2 price change and 74.00 after it.
SELECT
    p.product_id,
    p.product_name,
    p.brand,
    SUM(f.quantity)                                                             AS units,
    SUM(f.net_amount)                                                           AS net_sales,
    LISTAGG(DISTINCT f.unit_price, ', ') WITHIN GROUP (ORDER BY f.unit_price)  AS prices_sold_at
FROM GOLD.FCT_ORDER_LINES AS f
INNER JOIN GOLD.DIM_PRODUCT AS p
    ON f.product_key = p.product_key
WHERE NOT f.is_cancelled
GROUP BY p.product_id, p.product_name, p.brand
ORDER BY net_sales DESC
LIMIT 5;
