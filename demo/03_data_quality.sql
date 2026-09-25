-- Data-quality checks: bad, missing, duplicated and unexpected data.
-- The checks themselves live in dbt (models/quality); these queries show the results
-- and trace issues back to the delivered files.

USE ROLE CANDIDATE_SHIVUM_ROLE;
USE WAREHOUSE CANDIDATE_SHIVUM_WH;
USE DATABASE CANDIDATE_SHIVUM;

-- 1. Every check with its current issue count, zeros included.
SELECT check_name, severity, issue_count, description
FROM QUALITY.V_DQ_SUMMARY;

-- 2. Every open issue, most severe first.
SELECT severity, check_name, entity, record_key, detail
FROM QUALITY.V_DQ_ISSUES
ORDER BY CASE severity WHEN 'error' THEN 1 WHEN 'warn' THEN 2 ELSE 3 END, check_name, record_key;

-- 3. Rows received vs rows kept: duplicates and superseded versions collapse, nothing double counts.
SELECT 'order headers' AS entity,
       (SELECT COUNT(*) FROM BRONZE.ECOM_SRC_ORDER_HEADERS) AS rows_received,
       (SELECT COUNT(*) FROM GOLD.FCT_ORDERS)               AS rows_in_gold,
       'one row per order, latest version'                  AS gold_rule
UNION ALL
SELECT 'order lines',
       (SELECT COUNT(*) FROM BRONZE.ECOM_SRC_ORDER_LINES),
       (SELECT COUNT(*) FROM GOLD.FCT_ORDER_LINES),
       'one row per line, latest version'
UNION ALL
SELECT 'inventory',
       (SELECT COUNT(*) FROM BRONZE.ECOM_SRC_INVENTORY),
       (SELECT COUNT(*) FROM GOLD.FCT_INVENTORY_SNAPSHOT),
       'one row per date, location and product'
UNION ALL
SELECT 'customers',
       (SELECT COUNT(*) FROM BRONZE.ECOM_SRC_CUSTOMERS),
       (SELECT COUNT(*) FROM GOLD.DIM_CUSTOMER WHERE customer_key <> 'UNKNOWN~0'),
       'one row per customer version (a new version only on a real change)'
UNION ALL
SELECT 'products',
       (SELECT COUNT(*) FROM BRONZE.ECOM_SRC_PRODUCTS),
       (SELECT COUNT(*) FROM GOLD.DIM_PRODUCT WHERE product_key <> 'UNKNOWN~0'),
       'one row per product version (a new version only on a real change)';

-- 4. Trace records back to the file and row they arrived in.
--    O1005: a real change (PAID on Day 1, CANCELLED on Day 2). O1020: an exact duplicate inside the Day 2 file.
SELECT order_id, status, total, updated_at, _source_file_name, _source_file_row_number, _loaded_at
FROM BRONZE.ECOM_SRC_ORDER_HEADERS
WHERE order_id IN ('O1005', 'O1020')
ORDER BY order_id, _loaded_at, _source_file_row_number;

-- 5. Header subtotal vs lines, for every order with a discount.
--    The source uses subtotal inconsistently (sometimes gross, sometimes net); O1004 matches neither.
SELECT
    order_id,
    subtotal_amount,
    discount_amount,
    lines_gross_amount,
    lines_discount_amount,
    lines_net_amount,
    CASE
        WHEN subtotal_amount = lines_gross_amount THEN 'subtotal is gross'
        WHEN subtotal_amount = lines_net_amount   THEN 'subtotal is net'
        ELSE 'matches neither'
    END AS subtotal_convention,
    is_reconciled
FROM GOLD.FCT_ORDERS
WHERE discount_amount <> 0 OR lines_discount_amount <> 0
ORDER BY subtotal_convention, order_id;
