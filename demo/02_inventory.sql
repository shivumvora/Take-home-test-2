-- Inventory reporting on the gold star schema.
-- Inventory quantities are semi-additive: sum them across locations and products,
-- never across snapshot dates. The position view always uses the latest snapshot.

USE ROLE CANDIDATE_SHIVUM_ROLE;
USE WAREHOUSE CANDIDATE_SHIVUM_WH;
USE DATABASE CANDIDATE_SHIVUM;

-- 1. Current position by location.
SELECT
    snapshot_date,
    location_id,
    COUNT(*)                        AS products,
    SUM(on_hand_qty)                AS on_hand,
    SUM(reserved_qty)               AS reserved,
    SUM(available_qty)              AS available,
    SUM(on_hand_value_at_cost)      AS value_at_cost
FROM GOLD.V_RPT_INVENTORY_POSITION
GROUP BY snapshot_date, location_id
ORDER BY location_id;

-- 2. Current position by brand and category, most valuable stock first.
SELECT
    brand,
    category,
    SUM(on_hand_qty)                AS on_hand,
    SUM(available_qty)              AS available,
    SUM(on_hand_value_at_cost)      AS value_at_cost
FROM GOLD.V_RPT_INVENTORY_POSITION
GROUP BY brand, category
ORDER BY value_at_cost DESC;

-- 3. Day-over-day stock movement at the latest snapshot (only rows that moved or are new).
--    These can't be reconciled to sales yet: orders don't carry a fulfilment location.
WITH movements AS (

    SELECT
        snapshot_date,
        location_id,
        product_id,
        on_hand_qty,
        LAG(on_hand_qty) OVER (PARTITION BY location_id, product_id ORDER BY snapshot_date) AS on_hand_previous
    FROM GOLD.FCT_INVENTORY_SNAPSHOT

)

SELECT
    snapshot_date,
    location_id,
    product_id,
    on_hand_previous,
    on_hand_qty                         AS on_hand,
    on_hand_qty - on_hand_previous      AS change
FROM movements
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM movements)
  AND (on_hand_previous IS NULL OR on_hand_qty <> on_hand_previous)
ORDER BY change NULLS FIRST, product_id, location_id;

-- 4. Stock that needs attention: inactive products still holding stock, and low availability.
SELECT
    location_id,
    product_id,
    product_name,
    brand,
    is_product_active,
    available_qty,
    IFF(NOT is_product_active, 'inactive product still holding stock', 'low stock (under 20 available)') AS reason
FROM GOLD.V_RPT_INVENTORY_POSITION
WHERE NOT is_product_active
   OR available_qty < 20
ORDER BY reason, available_qty;
