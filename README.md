# Commerce analytics platform on Snowflake + dbt

This repo takes the two days of e-commerce extracts (customers, products, order headers, order lines and inventory) and builds them into a layered platform in Snowflake: a raw landing layer, a cleaned and conformed layer, and a star schema analysts can actually query. The files are tiny, but I built this the way I'd want the first slice of a real platform to look for a ~$500M multi-brand business with many sources, tens of millions of rows and a lot of downstream users. Some of it is deliberately more than 164 rows need.

## Architecture

```mermaid
flowchart LR
    F[Source CSVs] -->|PUT| L[(BRONZE.ECOM_LANDING<br/>stage)]
    L -->|COPY INTO| B[(BRONZE<br/>ECOM_SRC_* tables)]
    B --> S1[SILVER<br/>V_STG_ECOM__* views]
    S1 --> S2[SILVER<br/>V_INT_ECOM__* views]
    S2 --> G[(GOLD<br/>DIM_* / FCT_* tables)]
    G --> R[GOLD<br/>V_RPT_* views]
    S1 --> Q[QUALITY<br/>V_DQ_* views]
    G --> Q
```

| Schema | What's in it | How it's built |
|---|---|---|
| `BRONZE` | `ECOM_LANDING` stage, holding every delivered file untouched, and the `ECOM_SRC_*` raw tables | Stage + tables loaded with `COPY INTO` |
| `SILVER` | `V_STG_ECOM__*` (typed, renamed) and `V_INT_ECOM__*` (deduplicated, current state, history) | dbt views |
| `GOLD` | `DIM_*` / `FCT_*` star schema, plus `V_RPT_*` reporting views | dbt incremental `MERGE` tables, plus views |
| `QUALITY` | `V_DQ_ISSUES`, `V_DQ_SUMMARY` | dbt views |
| `OPS` | The dbt project object (`OPS.DWH`) and its upload stage | n/a |

The rule I used for the boundaries is simple:
- Bronze never interprets anything.
- Silver never loses anything, so it can always be rebuilt from bronze.
- Gold only holds modeled, tested data.
- Quality sits off to the side and reports problems without blocking the pipeline.

Every view in every schema starts with `V_`, so you can tell a view from a physical table by the name alone.

```
setup/01_create_schemas.sql      schemas
bronze/01_bronze_objects.sql     file format, landing stage, raw tables
bronze/02_land_delivery.sql      PUT one delivery into the landing stage
bronze/03_copy_into_bronze.sql   COPY anything not loaded yet into bronze
dbt/                             silver, gold and quality models (deployed as OPS.DWH)
demo/                            example queries (sales, inventory, data quality) and acceptance checks
Lead_Data_Engineer_Source_Data/  the source extracts
```

## Major design decisions

### Bronze is a landing zone, but with lineage

My first instinct was to load bronze strictly as-is with nothing added. I ended up keeping three columns that Snowflake hands you for free during `COPY`: `_SOURCE_FILE_NAME`, `_SOURCE_FILE_ROW_NUMBER` and `_LOADED_AT`. The customer and product files are full snapshots with no as-of date inside them, so the file name is the only thing that tells you which delivery a row came from. Without it you can't build history or detect deletes. The lineage columns also let you tell a duplicate the source sent apart from a file that got loaded twice, and trace any number in gold back to a file and row.

Everything else is loaded exactly as delivered, and all as text. A bad date or price never fails the load; typing happens in silver, where failures show up as data-quality issues.

Columns are matched by header name, not position (`MATCH_BY_COLUMN_NAME`), so a source reordering its columns can't put values in the wrong place. The trade-off is that Snowflake requires `ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE` for this setup. A short row loads with NULLs instead of failing, and the `missing_or_invalid_value` check catches it. A brand-new source column is ignored until it's added to the table.

Raw tables are named `<SOURCE>_SRC_<ENTITY>` (for example `ECOM_SRC_ORDER_HEADERS`), so they group by source system once there's more than one.

### Standard tables, not Iceberg (for now)

The account runs on AWS (us-east-2). At first I assumed Iceberg wasn't possible here, because the candidate role can't create an external volume. Snowflake now has Snowflake-managed storage for Iceberg (`EXTERNAL_VOLUME = SNOWFLAKE_MANAGED`), though, and a test table created fine under the candidate role. I kept standard tables anyway, on purpose:
- **Snowflake is the only engine reading this data today.** Native tables are simpler and faster, and they come with Time Travel and Fail-safe with nothing to manage.
- **With Snowflake storage, Iceberg only gets you part of the benefit.** The format is open, but the files live in Snowflake's storage, and other engines reach them through Snowflake's Horizon catalog. The real win with Iceberg is one copy of the data in *your own* lake that Spark, BigQuery and others can read directly.
- **The enterprise version would use my own bucket.** In, say, a GCP shop, I'd put bronze and gold in Iceberg on an external volume over a GCS bucket, since Snowflake storage for Iceberg isn't available on GCP-hosted accounts. An admin sets that up once and grants it to the loading and transform roles.

Switching later is mostly DDL. The bronze tables become `CREATE ICEBERG TABLE ... CATALOG = 'SNOWFLAKE'`, gold gets `table_format: iceberg` in dbt, and the MERGE design doesn't change. Before switching, I'd test two things: `COPY INTO` with `INCLUDE_METADATA` against an Iceberg table, and dbt's incremental merge on Iceberg. Iceberg also stores timestamps to the microsecond, which doesn't matter for this data.

### Silver is staging plus intermediate, all views

Normally I split silver into two parts:
- **Staging:** rename, cast and standardize.
- **Intermediate:** the transformations that get you to a clean select for gold.

I kept both even for a take-home. The split is cheap, and it's where the value shows up at scale: source quirks get absorbed once in staging, and business logic only ever sees clean, typed columns. Staging uses `TRY_` casts, so anything that can't be cast becomes a NULL that the tests and the DQ view pick up.

Silver is all views. Bronze keeps every delivery, so silver is just a repeatable calculation on top of an immutable record: rebuild it any time and you get the same answer. The physical, incremental work happens in gold.

Customer and product history comes from stacking the snapshots (`history_from_snapshots` macro) rather than `dbt snapshot`. Each delivery is compared with the previous one by a content hash, and a new version only opens when something actually changed. A key that drops out of the latest snapshot gets flagged `is_deleted_in_source`; nothing is physically deleted. The advantage over `dbt snapshot` is that the history isn't state living in a single table, so it can be rebuilt from bronze at any time.

For the incremental feeds (orders and lines), the latest `updated_at` per key wins, and ties go to the most recently loaded row. Exact duplicates collapse there.

### Gold is a star schema, incrementally merged, with readable keys

| Table | Grain | Key |
|---|---|---|
| `DIM_CUSTOMER` | customer version (type 2) | `customer_id~version`, e.g. `C003~2` |
| `DIM_PRODUCT` | product version (type 2) | `product_id~version` |
| `DIM_LOCATION` | warehouse | `location_id` |
| `DIM_DATE` | day | `date_day` |
| `FCT_ORDER_LINES` | order line, current version (the main sales fact) | `order_line_id` |
| `FCT_ORDERS` | order, current version | `order_id` |
| `FCT_INVENTORY_SNAPSHOT` | date × location × product | `snapshot_date~location_id~product_id` |
| `V_RPT_DAILY_SALES` | date × brand × category | n/a |
| `V_RPT_INVENTORY_POSITION` | location × product at the latest snapshot | n/a |

**Incremental MERGE, not truncate and reload.** Every fact and dimension is a permanent table merged on its key, so a run only writes what changed:
- **Facts** pick up rows loaded after the table's high-water mark (`_source_loaded_at`), plus anything still pointing at an `UNKNOWN~0` member, so late arrivals get fixed. A line's watermark is the later of the line itself and its header, so cancelling an order re-states its lines too.
- **Dimensions** only merge versions that are new or changed, detected with a row hash.
- **Duplicate keys** are removed in each model before the merge. Snowflake's `MERGE` either errors or behaves nondeterministically when the source has duplicate keys, so this is the last line of defense if something slips past silver.
- **Permanent tables.** Gold tables are `transient: false`, because dbt's Snowflake default is transient and I don't want that for the physical layer.

**Readable keys instead of hashes.** A key is the actual values at the table's grain, joined with `~`. It's much easier to debug and trace a row by eye.

**Revenue comes from the lines.** The source doesn't use the header `subtotal` consistently (see below). `FCT_ORDERS` keeps the header amounts, since tax and shipping only exist there, plus an `is_reconciled` flag against the lines.

**Point-in-time joins.** Facts point at the customer or product version that was valid when the order was placed, so price, cost and brand are historically right. The first version of each customer and product reaches back to 1900-01-01 for joining. That way an order timestamped before its customer record was created still finds it, and it still gets flagged. Facts with no match point at `UNKNOWN~0` instead of being dropped.

**Cancelled orders stay in the facts** with `is_cancelled`. Reporting excludes them from net sales but still counts them.

### dbt runs inside Snowflake

dbt is deployed as a Snowflake dbt project object (`OPS.DWH`, dbt Core 1.11.11 pinned). You can run it from the CLI, from SQL, or from the Workspace connected to this repo:
- **Environments:** the `prod` target writes to the exact schema names. Any other target writes to `DEV_*` schemas, so dev work never touches shared data.
- **Docs in Snowflake:** model and column descriptions, including grain and keys, are persisted as Snowflake comments. Someone browsing the warehouse sees them without opening the repo.
- **Cost tracking:** every dbt query carries a `dbt_dwh` query tag.

## How to reproduce

You need the Snowflake CLI (`snow`) with a connection to the account set as default, and a role that can create schemas in `CANDIDATE_SHIVUM` and use `CANDIDATE_SHIVUM_WH`.

```bash
# schemas and bronze objects (DDL only)
snow sql -f setup/01_create_schemas.sql
snow sql -f bronze/01_bronze_objects.sql

# Day 1: land the files, load whatever is new
snow sql -f bronze/02_land_delivery.sql -D "delivery_dir=<absolute path>/Lead_Data_Engineer_Source_Data/day_1"
snow sql -f bronze/03_copy_into_bronze.sql

# deploy dbt to Snowflake and build silver, gold and quality (models + tests)
snow dbt deploy DWH --source dbt --profiles-dir dbt --database CANDIDATE_SHIVUM --schema OPS --dbt-version 1.11.11
snow dbt execute --database CANDIDATE_SHIVUM --schema OPS DWH build

# Day 2: same two bronze commands with day_2, then build again
snow sql -f bronze/02_land_delivery.sql -D "delivery_dir=<absolute path>/Lead_Data_Engineer_Source_Data/day_2"
snow sql -f bronze/03_copy_into_bronze.sql
snow dbt execute --database CANDIDATE_SHIVUM --schema OPS DWH build

# verify: every row should say PASS. Repeat the Day 2 block and run it again to prove the rerun is a no-op.
snow sql -f demo/day2_acceptance_checks.sql

# example reporting and data-quality queries (or open them in a Snowsight worksheet)
snow sql -f demo/01_sales_and_orders.sql
snow sql -f demo/02_inventory.sql
snow sql -f demo/03_data_quality.sql
```

## How updates, duplicates and reruns are handled

There are three layers of protection, so a rerun has to get past all of them before it could double count:

1. **Landing.** `PUT ... OVERWRITE = FALSE` skips any file already in the stage. A correction has to come in as a new file.
2. **Bronze.** `COPY INTO` keeps a per-table load history and skips files it has already loaded. It's never run with `FORCE = TRUE`.
3. **Silver and gold.** Duplicate rows can still reach bronze: the source sends a record twice, someone forces a reload, or a file gets resent under a new name. Silver collapses them by key and latest `updated_at`, and gold removes duplicate keys again before merging.

Changes flow through the same way. A changed order or line replaces its earlier version in silver, and the gold `MERGE` updates the existing fact row. A changed customer or product becomes a new version in history. Gold closes the old version and inserts the new one, while existing facts stay pinned to the version that was valid at the time.

I held Day 2 back until everything was built, then processed it like any other delivery, then ran the whole Day 2 delivery a second time:

| | After Day 1 | After Day 2 | Day 2 rerun |
|---|---|---|---|
| Files | 5 loaded | 5 loaded | 5 skipped, 0 loaded |
| Orders / lines / inventory rows in gold | 12 / 19 / 24 | 20 / 33 / 50 | 20 / 33 / 50 |
| Net sales (excluding cancelled) | 1,177.60 | 1,838.40 | 1,838.40 |
| Rows inserted by the gold MERGEs | n/a | 55 | 0 |
| dbt build (models + 89 tests) | 110/110 | 110/110 | 110/110 |

[demo/day2_acceptance_checks.sql](demo/day2_acceptance_checks.sql) turns every condition in the brief and the source README into an expected-vs-actual check. All 38 pass after Day 2 and again after the rerun:
- **New records:** C016, P013, 8 new orders.
- **Changes:** O1005 cancelled, with its untouched line re-stated. O1011 and L1018 corrected. C003 moving WA→CA while O1005 stays on the old version. P004 going 70→74, with old and new orders each on the right version. C012 and P008 deactivated.
- **Duplicates:** O1020 and L1033 each have two rows in bronze, one in gold, and are flagged.
- **Late data:** the late-arriving C016.
- **Stability:** totals don't move on the rerun.

One thing that tripped me up: dbt's `SUCCESS n` on a `MERGE` only counts inserts, so the Day 2 updates don't show up in that number. The acceptance checks are what prove the updates happened.

The two files don't cover every case, so for honesty:
- **Handled but not exercised:** out-of-order deliveries (current state goes by `updated_at` and history by delivery date, not load order), forced reloads, renamed resends, and a customer dropping out of a snapshot. The logic is there, but nothing in this data triggers it.
- **Not handled:** a line deleted from an order. The incremental feed has no delete signal, so that line would stay in the fact until the source sends a correction or cancellation.

## Assumptions and data quirks

Assumptions:
- Timestamps are UTC and amounts are USD, per the source README.
- The delivery date comes from the file name (`<entity>_YYYY-MM-DD.csv`), which the landing convention guarantees.
- `updated_at` orders the versions of a key.
- `is_active = FALSE` is a status, not a delete.
- An order uses the customer and product that were in force at `ordered_at`.

Quirks I found while profiling the files, and what I did about them:
1. **`subtotal` means different things on different orders.** Sometimes it's gross, with the header discount matching the line discounts; sometimes it's already net, with a header discount of 0. O1004 matches neither: subtotal 124.00 against lines of 128.00 gross and 111.60 net. That's why revenue comes from line totals, and O1004 gets flagged.
2. **C016 was created (Day 2, 19:05) after its own order O1016 (16:55).** This is handled by the 1900-01-01 join window, and it's flagged.
3. **Cancelled orders keep their full amounts** (O1005 still shows 138.24). They're excluded from net sales by status, and flagged as info.
4. **L1018 keeps a unit price of 70.00 after P004's list price moves to 74.00.** That's correct as a sale-time price, and the point-in-time join handles it.
5. **Inventory can't be reconciled to sales,** because orders don't carry a fulfilment location.
6. **Customer names and emails are plain-text PII.**

## Demonstrating the result

There are three query files in `demo/`, each commented so you can open it in a Snowsight worksheet and run it top to bottom. The outputs below are from after Day 2.

### Sales and orders: [demo/01_sales_and_orders.sql](demo/01_sales_and_orders.sql)

This file has five queries: a daily summary, sales by brand and category, orders by status, each customer's tier at the time of the order vs today, and the top products with the prices they actually sold at.

| Order date | Orders | Cancelled | Units | Gross | Discounts | Net sales | Margin | Avg order |
|---|---|---|---|---|---|---|---|---|
| 2026-09-01 | 11 | 1 | 19 | 1,102.00 | 57.40 | 1,044.60 | 639.85 | 94.96 |
| 2026-09-02 | 8 | 0 | 14 | 830.00 | 36.20 | 793.80 | 491.05 | 99.23 |

A few things worth pointing out:
- **O1005 counts as cancelled on Sep 1,** the day it was placed, even though the cancellation arrived on Day 2.
- **C007 shows both tiers.** They ordered as Silver on Day 1 and are Gold now, and the customer query shows "tier when ordered: Silver, tier today: Gold". That's the type 2 dimension doing its job.
- **P004 shows both prices.** It sold at 70.00 before its price change and 74.00 after.
- **Everything reconciles.** Net sales add up to the same 1,838.40 whether you total by day, by brand and category, or by the PAID orders in the status query.

### Inventory: [demo/02_inventory.sql](demo/02_inventory.sql)

This file covers the current position by location and by brand/category, the day-over-day movement, and stock that needs attention.

| Location | Products | On hand | Reserved | Available | Value at cost |
|---|---|---|---|---|---|
| WH_EAST | 13 | 404 | 22 | 382 | 6,911.75 |
| WH_WEST | 13 | 494 | 23 | 471 | 7,935.00 |

What the queries show:
- **Movement:** 20 of the 24 existing positions went down overnight (37 units in total), and P013 arrived at both warehouses. Only 14 units were sold on Day 2, which is exactly why I'd want a fulfilment location on orders before trying to reconcile stock to sales.
- **Needs attention:** P008 is inactive but still has 28 units available across the two warehouses, and 6 positions are under 20 units available.

### Data quality: [demo/03_data_quality.sql](demo/03_data_quality.sql)

There are two layers:
- **dbt tests (89)** are the build gate. Missing or duplicate keys and broken fact-to-dimension links fail the build. Uncastable values, unexpected values and silver-level reference problems warn, because a late-arriving customer should be reported, not stop the pipeline.
- **`QUALITY.V_DQ_ISSUES`** lists every issue as a row, with the check, severity, entity, record key and a readable detail, so someone can act on it. **`V_DQ_SUMMARY`** shows every check with its count, zeros included.

The checks cover:
- **Bad data:** order totals, line totals and inventory arithmetic that don't add up.
- **Missing data:** blank or uncastable values, and facts linked to an unknown customer or product.
- **Duplicates:** the same record delivered more than once.
- **Unexpected data:** header vs line mismatches, inconsistent subtotals, orders placed before their customer existed, cancelled orders still carrying amounts, and keys dropped from a snapshot.

After Day 2 it finds 5 issues, and all 5 are real:

| Severity | Check | Record | Detail |
|---|---|---|---|
| warn | duplicate_record_received | O1020 | 2 identical rows in the Day 2 order headers file |
| warn | duplicate_record_received | L1033 | 2 identical rows in the Day 2 order lines file |
| warn | header_subtotal_inconsistent | O1004 | subtotal 124.00 matches neither lines gross 128.00 nor lines net 111.60 |
| warn | order_before_customer_created | O1016 | ordered 16:55, but C016 was created at 19:05 |
| info | cancelled_order_with_amount | O1005 | cancelled but still carries 138.24; excluded from net sales |

The same file also shows how much collapses between bronze and gold. It traces O1005 and O1020 back to the exact file and row they arrived in: O1005's PAID and CANCELLED versions come from different files, while O1020's duplicate is rows 10 and 11 of the same file. It also lays out the subtotal conventions order by order.

| Entity | Rows received in bronze | Rows in gold | Gold rule |
|---|---|---|---|
| Order headers | 23 | 20 | one per order, latest version |
| Order lines | 35 | 33 | one per line, latest version |
| Inventory | 50 | 50 | one per date, location and product |
| Customers | 31 | 19 | one per customer version (new version only on a real change) |
| Products | 25 | 15 | one per product version (new version only on a real change) |

The acceptance checks in [demo/day2_acceptance_checks.sql](demo/day2_acceptance_checks.sql) are the fourth piece. They're covered in the reruns section above.

## Monitoring in production

- **Loads.** Alert on `COPY_HISTORY` errors and partial loads, and on deliveries that should have landed but didn't, by checking landed files against a delivery calendar per source.
- **Freshness.** Run dbt source freshness on `_loaded_at`, with thresholds tied to each source's SLA.
- **Data quality.** Snapshot `V_DQ_SUMMARY` after every run. Page on error-severity checks, and trend the warn counts, since a sudden jump means something even when nothing breaks. Watch row counts and totals between deliveries.
- **Pipeline runs.** dbt project runs log to the Snowflake event table, so alert on failed `EXECUTE DBT PROJECT` runs and on long runtimes. Because dbt only reports inserts for a MERGE, pull inserted and updated counts per table from `QUERY_HISTORY` using the `dbt_dwh` tag.
- **Cost.** Put resource monitors on each warehouse and attribute credits by query tag. This whole exercise used well under half a credit of the 5 available.

## If the data grew to 30M+ rows

Gold is already incremental, so most of the work is in the layers around it:
- **Ingestion.** Move to an external stage with Snowpipe auto-ingest, and prune bronze by load date.
- **Silver.** The intermediate views become incremental tables or Dynamic Tables that only process new `_loaded_at` rows, instead of recalculating over all of bronze on every run.
- **Type 2 dimensions.** The MERGE itself scales fine. The expensive part today is working out the versions: the silver view rebuilds history from every snapshot ever delivered, and the row-hash comparison reads the whole dimension. At scale I'd compare only the newest delivery with the current versions, emit the closed row and the new row for each changed key, and MERGE those. For the exception cases (a late or out-of-order delivery, or a backdated correction that inserts a version in the middle of history), I'd rebuild the full history for just the affected keys and write it with delete+insert on the natural key. The facts in those time windows would then be re-pointed.
- **Big facts.** Add `incremental_predicates` so each MERGE only scans recent partitions of the target, and cluster the large facts by date.
- **Warehouses.** Use separate warehouses for loading, transforming and BI, so they don't compete. Only size up for backfills.

## If I had more time…

These are the things I left out on purpose to stay within the timebox, roughly in the order I'd tackle them.

- **Orchestration.** Right now the steps are run by hand. I'd set up a Snowflake task graph (land → copy → dbt build → checks) with alerting on failure, with Snowpipe feeding bronze from a real bucket.
- **CI/CD and environments.** Run `dbt build` against the `dev` target on every pull request, using slim CI on modified models only, and deploy the dbt project on merge. I'd also move dev and prod into separate databases instead of prefixed schemas.
- **Security and governance.** Add masking policies on email and names, tag PII columns, and use proper functional roles (loader, transformer, analyst) instead of one role doing everything. With multiple brands, row access policies might also be needed if brand teams should only see their own data.
- **A delivery control table.** Register every file with its name, checksum and row count, so a renamed resend gets rejected at landing instead of only being collapsed in silver. Today the duplicate check doesn't flag a renamed resend of a snapshot file. If the source can send a record count per file, reconcile against it too.
- **Schema drift and quarantine.** Alert when a file shows up with columns bronze doesn't have. Route rows that fail typing into a rejects table with the reason, instead of only reporting them.
- **Type 2 hardening.** Build the key-based change detection and targeted rebuild described above. I'd probably also switch the version key to `id~valid_from` (for example `C003~2026-09-02T15:05:00`). It's still readable and at the true grain, and unlike a version number it doesn't shift meaning when a late version is inserted. On top of that, re-point facts when a backdated change arrives; today only facts sitting on `UNKNOWN~0` get re-merged.
- **Line deletes.** Ask the source for a delete or tombstone signal, or for full order snapshots, so removed lines can be retired.
- **Testing.** Add dbt unit tests for the history macro, the deduplication and the merge logic, covering A→B→A changes, tied `updated_at` values, deletes and late members. Add a few synthetic deliveries to exercise the paths these two files never hit: a dropped customer, an out-of-order delivery and a forced reload.
- **Modeling.** Spread header tax, shipping and header-only discounts across lines for true line-level net revenue. Add a proper `dim_brand` once brand has attributes of its own, and currency conversion once there's more than USD. Get a fulfilment location on orders so inventory can finally be reconciled to sales.
- **Iceberg** for bronze and gold, once other engines need to read the data: on an external volume over our own bucket rather than Snowflake storage, after testing the COPY and MERGE paths mentioned above.

## How I used AI

I used Claude Code, an AI coding assistant, for most of the hands-on work. I made the design calls and pushed back where I didn't agree:
- **Profiling.** It profiled the source files with a script rather than by eye, which is how the subtotal inconsistency and the late C016 came up early.
- **Drafting.** It drafted the SQL, the dbt models and this README, and I reviewed and shaped them. Some decisions went its way: it talked me into the three lineage columns in bronze after I'd said no extra columns. Others went mine: the `ECOM_SRC_` naming, the staging/intermediate split, incremental MERGE over truncate-and-reload, readable `a~b~c` keys and the `V_` view prefix.
- **Checking.** It looked up the Snowflake docs before relying on syntax, for example the `INCLUDE_METADATA` restrictions and which dbt versions Snowflake supports, and it parsed and compiled the dbt project locally before every deploy.
- **Staying within the budget.** It batched each round of Snowflake work into a single script run, both for the credit budget and to cut down on sign-ins.
- **Mistakes caught.** It got things wrong a couple of times:
  - The worst was loading Day 1 and Day 2 together at the start. I had it roll that back so Day 2 could be tested as a real second delivery.
  - It also told me Iceberg wasn't possible on this account, reasoning from the missing external-volume privileges. That turned out to be wrong once we actually tried it. It was a good reminder to test instead of infer.
- **Verification.** It wrote the acceptance checks and demo queries from the brief and the source README, and I used those to verify the end result.
