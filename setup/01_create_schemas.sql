-- Medallion layers for the analytics platform.
-- Idempotent: safe to re-run. DDL only, so no warehouse is needed.

USE ROLE CANDIDATE_SHIVUM_ROLE;
USE DATABASE CANDIDATE_SHIVUM;

CREATE SCHEMA IF NOT EXISTS BRONZE
    COMMENT = 'Raw source extracts loaded as-is, append-only, with file and load lineage. Never updated in place.';

CREATE SCHEMA IF NOT EXISTS SILVER
    COMMENT = 'Cleaned, typed, deduplicated and conformed source entities, including change history.';

CREATE SCHEMA IF NOT EXISTS GOLD
    COMMENT = 'Analytics-ready dimensional model (facts and dimensions) and reporting views for downstream users.';

CREATE SCHEMA IF NOT EXISTS QUALITY
    COMMENT = 'Data-quality results for data stewards: detected issues and a per-check summary.';

-- Platform objects that are not data: the dbt project object and its source stage.
CREATE SCHEMA IF NOT EXISTS OPS
    COMMENT = 'Platform and orchestration objects (dbt project, deployment stage). No business data.';

SHOW SCHEMAS IN DATABASE CANDIDATE_SHIVUM;
