-- Bronze objects for the ECOM source system: file format, landing stage and raw tables.
-- Idempotent: everything is IF NOT EXISTS, so re-running never drops loaded rows,
-- landed files or COPY load history (which is what makes reloads safe).

USE ROLE CANDIDATE_SHIVUM_ROLE;
USE DATABASE CANDIDATE_SHIVUM;
USE SCHEMA BRONZE;

-- The header row is parsed so COPY matches columns by name, not position: a source
-- that reorders its columns cannot shift values into the wrong column.
-- Values are kept exactly as delivered: nothing is converted to NULL, empty fields
-- stay empty strings. A NULL in bronze therefore means the column was absent from the file.
-- ERROR_ON_COLUMN_COUNT_MISMATCH must be FALSE to load CSV with INCLUDE_METADATA.
CREATE FILE FORMAT IF NOT EXISTS ECOM_CSV_FORMAT
    TYPE = CSV
    PARSE_HEADER = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ()
    EMPTY_FIELD_AS_NULL = FALSE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    COMMENT = 'ECOM source extracts: comma-delimited CSV with a header row';

-- Landing zone: immutable copies of every delivered file, one folder per entity
-- (/customers/, /products/, ...). In production this would be an external stage
-- over a cloud bucket fed by the source system.
CREATE STAGE IF NOT EXISTS ECOM_LANDING
    FILE_FORMAT = ECOM_CSV_FORMAT
    COMMENT = 'Landing zone for ECOM source files, one folder per entity';

-- Raw tables. Source columns mirror the files and are all text; typing, cleansing and
-- deduplication happen in silver. The three trailing columns are supplied by COPY:
--   _SOURCE_FILE_NAME       stage path of the file the row came from
--   _SOURCE_FILE_ROW_NUMBER row position within that file
--   _LOADED_AT              when the load began

CREATE TABLE IF NOT EXISTS ECOM_SRC_CUSTOMERS (
    CUSTOMER_ID             VARCHAR,
    EMAIL                   VARCHAR,
    FIRST_NAME              VARCHAR,
    LAST_NAME               VARCHAR,
    STATE                   VARCHAR,
    COUNTRY                 VARCHAR,
    CREATED_AT              VARCHAR,
    UPDATED_AT              VARCHAR,
    LOYALTY_TIER            VARCHAR,
    IS_ACTIVE               VARCHAR,
    _SOURCE_FILE_NAME       VARCHAR,
    _SOURCE_FILE_ROW_NUMBER NUMBER,
    _LOADED_AT              TIMESTAMP_LTZ
)
COMMENT = 'Raw ECOM customers. Full snapshot per delivery file; key customer_id.';

CREATE TABLE IF NOT EXISTS ECOM_SRC_PRODUCTS (
    PRODUCT_ID              VARCHAR,
    SKU                     VARCHAR,
    PRODUCT_NAME            VARCHAR,
    CATEGORY                VARCHAR,
    BRAND                   VARCHAR,
    LIST_PRICE              VARCHAR,
    UNIT_COST               VARCHAR,
    IS_ACTIVE               VARCHAR,
    UPDATED_AT              VARCHAR,
    _SOURCE_FILE_NAME       VARCHAR,
    _SOURCE_FILE_ROW_NUMBER NUMBER,
    _LOADED_AT              TIMESTAMP_LTZ
)
COMMENT = 'Raw ECOM products. Full snapshot per delivery file; key product_id.';

CREATE TABLE IF NOT EXISTS ECOM_SRC_ORDER_HEADERS (
    ORDER_ID                VARCHAR,
    CUSTOMER_ID             VARCHAR,
    ORDER_TS                VARCHAR,
    STATUS                  VARCHAR,
    CURRENCY                VARCHAR,
    SUBTOTAL                VARCHAR,
    DISCOUNT                VARCHAR,
    TAX                     VARCHAR,
    SHIPPING                VARCHAR,
    TOTAL                   VARCHAR,
    UPDATED_AT              VARCHAR,
    SOURCE_SYSTEM           VARCHAR,
    _SOURCE_FILE_NAME       VARCHAR,
    _SOURCE_FILE_ROW_NUMBER NUMBER,
    _LOADED_AT              TIMESTAMP_LTZ
)
COMMENT = 'Raw ECOM order headers. Incremental; an order_id reappears when it changes, and exact duplicates can occur.';

CREATE TABLE IF NOT EXISTS ECOM_SRC_ORDER_LINES (
    LINE_ID                 VARCHAR,
    ORDER_ID                VARCHAR,
    PRODUCT_ID              VARCHAR,
    QUANTITY                VARCHAR,
    UNIT_PRICE              VARCHAR,
    LINE_DISCOUNT           VARCHAR,
    LINE_TOTAL              VARCHAR,
    UPDATED_AT              VARCHAR,
    _SOURCE_FILE_NAME       VARCHAR,
    _SOURCE_FILE_ROW_NUMBER NUMBER,
    _LOADED_AT              TIMESTAMP_LTZ
)
COMMENT = 'Raw ECOM order lines. Incremental; a line_id reappears when it is corrected, and exact duplicates can occur.';

CREATE TABLE IF NOT EXISTS ECOM_SRC_INVENTORY (
    SNAPSHOT_DATE           VARCHAR,
    LOCATION_ID             VARCHAR,
    PRODUCT_ID              VARCHAR,
    ON_HAND_QTY             VARCHAR,
    RESERVED_QTY            VARCHAR,
    AVAILABLE_QTY           VARCHAR,
    SOURCE_UPDATED_AT       VARCHAR,
    _SOURCE_FILE_NAME       VARCHAR,
    _SOURCE_FILE_ROW_NUMBER NUMBER,
    _LOADED_AT              TIMESTAMP_LTZ
)
COMMENT = 'Raw ECOM inventory. Daily point-in-time snapshot; key snapshot_date + location_id + product_id.';
