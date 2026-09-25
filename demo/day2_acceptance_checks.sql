-- Acceptance checks for the two provided deliveries, run after Day 2 is loaded and built.
-- Each row turns one condition from the exercise brief or the source README into an
-- expected vs actual comparison. Every row should report PASS, and still PASS after
-- Day 2 is landed, loaded and built a second time (the rerun must change nothing).

USE ROLE CANDIDATE_SHIVUM_ROLE;
USE WAREHOUSE CANDIDATE_SHIVUM_WH;
USE DATABASE CANDIDATE_SHIVUM;

WITH checks (requirement, check_name, expected, actual) AS (

    -- New records arrive ----------------------------------------------------------
    SELECT 'New records', 'New customer C016 added as a first version', 'C016~1',
           (SELECT LISTAGG(customer_key, ',') FROM GOLD.DIM_CUSTOMER WHERE customer_id = 'C016')
    UNION ALL
    SELECT 'New records', 'New product P013 added as a first version', 'P013~1',
           (SELECT LISTAGG(product_key, ',') FROM GOLD.DIM_PRODUCT WHERE product_id = 'P013')
    UNION ALL
    SELECT 'New records', 'Orders in FCT_ORDERS (12 Day 1 + 8 new)', '20',
           (SELECT TO_VARCHAR(COUNT(*)) FROM GOLD.FCT_ORDERS)
    UNION ALL
    SELECT 'New records', 'Lines in FCT_ORDER_LINES (19 Day 1 + 14 new)', '33',
           (SELECT TO_VARCHAR(COUNT(*)) FROM GOLD.FCT_ORDER_LINES)
    UNION ALL
    SELECT 'New records', 'Rows in FCT_INVENTORY_SNAPSHOT (24 + 26)', '50',
           (SELECT TO_VARCHAR(COUNT(*)) FROM GOLD.FCT_INVENTORY_SNAPSHOT)
    UNION ALL
    SELECT 'New records', 'Customer versions (15 + C016 + 3 changes)', '19',
           (SELECT TO_VARCHAR(COUNT(*)) FROM GOLD.DIM_CUSTOMER WHERE customer_key <> 'UNKNOWN~0')
    UNION ALL
    SELECT 'New records', 'Product versions (12 + P013 + 2 changes)', '15',
           (SELECT TO_VARCHAR(COUNT(*)) FROM GOLD.DIM_PRODUCT WHERE product_key <> 'UNKNOWN~0')

    -- Existing records change -----------------------------------------------------
    UNION ALL
    SELECT 'Changed records', 'O1005 cancelled on Day 2', 'CANCELLED',
           (SELECT order_status FROM GOLD.FCT_ORDERS WHERE order_id = 'O1005')
    UNION ALL
    SELECT 'Changed records', 'Cancellation re-states its unchanged line L1008', 'true',
           (SELECT TO_VARCHAR(is_cancelled) FROM GOLD.FCT_ORDER_LINES WHERE order_line_id = 'L1008')
    UNION ALL
    SELECT 'Changed records', 'O1011 corrected: total 80.60 -> 75.20', '75.20',
           (SELECT TO_VARCHAR(total_amount) FROM GOLD.FCT_ORDERS WHERE order_id = 'O1011')
    UNION ALL
    SELECT 'Changed records', 'L1018 corrected: net 70.00 -> 65.00', '65.00',
           (SELECT TO_VARCHAR(net_amount) FROM GOLD.FCT_ORDER_LINES WHERE order_line_id = 'L1018')
    UNION ALL
    SELECT 'Changed records', 'C003 moved WA -> CA as a new version', 'C003~1:WA,C003~2:CA',
           (SELECT LISTAGG(customer_key || ':' || state_code, ',') WITHIN GROUP (ORDER BY version_number)
            FROM GOLD.DIM_CUSTOMER WHERE customer_id = 'C003')
    UNION ALL
    SELECT 'Changed records', 'O1005 (placed before the move) keeps C003~1', 'C003~1',
           (SELECT customer_key FROM GOLD.FCT_ORDERS WHERE order_id = 'O1005')
    UNION ALL
    SELECT 'Changed records', 'C007 loyalty tier Silver -> Gold', 'C007~1:Silver,C007~2:Gold',
           (SELECT LISTAGG(customer_key || ':' || loyalty_tier, ',') WITHIN GROUP (ORDER BY version_number)
            FROM GOLD.DIM_CUSTOMER WHERE customer_id = 'C007')
    UNION ALL
    SELECT 'Changed records', 'C012 deactivated (current version inactive)', 'false',
           (SELECT TO_VARCHAR(is_active) FROM GOLD.DIM_CUSTOMER WHERE customer_id = 'C012' AND is_current)
    UNION ALL
    SELECT 'Changed records', 'P004 list price 70 -> 74 as a new version', 'P004~1:70.00,P004~2:74.00',
           (SELECT LISTAGG(product_key || ':' || list_price, ',') WITHIN GROUP (ORDER BY version_number)
            FROM GOLD.DIM_PRODUCT WHERE product_id = 'P004')
    UNION ALL
    SELECT 'Changed records', 'L1018 (ordered before the price change) keeps P004~1', 'P004~1',
           (SELECT product_key FROM GOLD.FCT_ORDER_LINES WHERE order_line_id = 'L1018')
    UNION ALL
    SELECT 'Changed records', 'L1024 (ordered after the price change) uses P004~2', 'P004~2',
           (SELECT product_key FROM GOLD.FCT_ORDER_LINES WHERE order_line_id = 'L1024')
    UNION ALL
    SELECT 'Changed records', 'P008 deactivated; Day 2 inventory uses the inactive version', 'P008~2:false',
           (SELECT f.product_key || ':' || TO_VARCHAR(p.is_active)
            FROM GOLD.FCT_INVENTORY_SNAPSHOT f JOIN GOLD.DIM_PRODUCT p ON f.product_key = p.product_key
            WHERE f.inventory_snapshot_id = '2026-09-02~WH_WEST~P008')

    -- Duplicates ------------------------------------------------------------------
    UNION ALL
    SELECT 'Duplicates', 'O1020 received twice in bronze', '2',
           (SELECT TO_VARCHAR(COUNT(*)) FROM BRONZE.ECOM_SRC_ORDER_HEADERS WHERE order_id = 'O1020')
    UNION ALL
    SELECT 'Duplicates', 'O1020 counted once in gold', '1',
           (SELECT TO_VARCHAR(COUNT(*)) FROM GOLD.FCT_ORDERS WHERE order_id = 'O1020')
    UNION ALL
    SELECT 'Duplicates', 'L1033 received twice in bronze', '2',
           (SELECT TO_VARCHAR(COUNT(*)) FROM BRONZE.ECOM_SRC_ORDER_LINES WHERE line_id = 'L1033')
    UNION ALL
    SELECT 'Duplicates', 'L1033 counted once in gold', '1',
           (SELECT TO_VARCHAR(COUNT(*)) FROM GOLD.FCT_ORDER_LINES WHERE order_line_id = 'L1033')
    UNION ALL
    SELECT 'Duplicates', 'Duplicates reported by data quality', 'order_header:O1020,order_line:L1033',
           (SELECT LISTAGG(entity || ':' || record_key, ',') WITHIN GROUP (ORDER BY entity, record_key)
            FROM QUALITY.V_DQ_ISSUES WHERE check_name = 'duplicate_record_received')

    -- Bad, missing or unexpected data ---------------------------------------------
    UNION ALL
    SELECT 'Unexpected data', 'O1016 placed before C016 existed still resolves to C016~1', 'C016~1',
           (SELECT customer_key FROM GOLD.FCT_ORDERS WHERE order_id = 'O1016')
    UNION ALL
    SELECT 'Unexpected data', 'Order placed before its customer existed is flagged', 'O1016',
           (SELECT LISTAGG(record_key, ',') FROM QUALITY.V_DQ_ISSUES WHERE check_name = 'order_before_customer_created')
    UNION ALL
    SELECT 'Unexpected data', 'Inconsistent header subtotal is flagged', 'O1004',
           (SELECT LISTAGG(record_key, ',') FROM QUALITY.V_DQ_ISSUES WHERE check_name = 'header_subtotal_inconsistent')
    UNION ALL
    SELECT 'Unexpected data', 'Cancelled order still carrying amounts is flagged', 'O1005',
           (SELECT LISTAGG(record_key, ',') FROM QUALITY.V_DQ_ISSUES WHERE check_name = 'cancelled_order_with_amount')
    UNION ALL
    SELECT 'Unexpected data', 'Error-severity data-quality issues', '0',
           (SELECT TO_VARCHAR(COUNT(*)) FROM QUALITY.V_DQ_ISSUES WHERE severity = 'error')
    UNION ALL
    SELECT 'Unexpected data', 'Fact rows on an UNKNOWN~0 member', '0',
           (SELECT TO_VARCHAR(
                (SELECT COUNT(*) FROM GOLD.FCT_ORDER_LINES WHERE customer_key = 'UNKNOWN~0' OR product_key = 'UNKNOWN~0')
              + (SELECT COUNT(*) FROM GOLD.FCT_ORDERS WHERE customer_key = 'UNKNOWN~0')
              + (SELECT COUNT(*) FROM GOLD.FCT_INVENTORY_SNAPSHOT WHERE product_key = 'UNKNOWN~0')))

    -- No double counting ----------------------------------------------------------
    UNION ALL
    SELECT 'No double counting', 'Bronze rows: customers, products, headers, lines, inventory', '31,25,23,35,50',
           (SELECT (SELECT TO_VARCHAR(COUNT(*)) FROM BRONZE.ECOM_SRC_CUSTOMERS) || ','
                || (SELECT TO_VARCHAR(COUNT(*)) FROM BRONZE.ECOM_SRC_PRODUCTS) || ','
                || (SELECT TO_VARCHAR(COUNT(*)) FROM BRONZE.ECOM_SRC_ORDER_HEADERS) || ','
                || (SELECT TO_VARCHAR(COUNT(*)) FROM BRONZE.ECOM_SRC_ORDER_LINES) || ','
                || (SELECT TO_VARCHAR(COUNT(*)) FROM BRONZE.ECOM_SRC_INVENTORY))
    UNION ALL
    SELECT 'No double counting', 'Net sales excluding cancelled orders', '1838.40',
           (SELECT TO_VARCHAR(SUM(net_amount)) FROM GOLD.FCT_ORDER_LINES WHERE NOT is_cancelled)
    UNION ALL
    SELECT 'No double counting', 'Daily sales view reconciles to the fact', '1838.40',
           (SELECT TO_VARCHAR(SUM(net_sales_amount)) FROM GOLD.V_RPT_DAILY_SALES)
    UNION ALL
    SELECT 'No double counting', 'Units sold excluding cancelled orders', '33',
           (SELECT TO_VARCHAR(SUM(quantity)) FROM GOLD.FCT_ORDER_LINES WHERE NOT is_cancelled)
    UNION ALL
    SELECT 'No double counting', 'Orders excluding cancelled', '19',
           (SELECT TO_VARCHAR(COUNT(*)) FROM GOLD.FCT_ORDERS WHERE NOT is_cancelled)
    UNION ALL
    SELECT 'No double counting', 'Units on hand at the latest snapshot (2026-09-02)', '898',
           (SELECT TO_VARCHAR(SUM(on_hand_qty)) FROM GOLD.V_RPT_INVENTORY_POSITION)

    -- Source conventions ----------------------------------------------------------
    UNION ALL
    SELECT 'Conventions', 'Timestamps kept in UTC (O1001 ordered 15:10Z)', '2026-09-01 15:10:00',
           (SELECT TO_VARCHAR(ordered_at, 'YYYY-MM-DD HH24:MI:SS') FROM GOLD.FCT_ORDERS WHERE order_id = 'O1001')
    UNION ALL
    SELECT 'Conventions', 'All orders in USD', 'USD',
           (SELECT LISTAGG(DISTINCT currency_code, ',') FROM GOLD.FCT_ORDERS)
)

SELECT
    requirement,
    check_name,
    expected,
    actual,
    IFF(expected = actual, 'PASS', 'FAIL') AS status
FROM checks;
