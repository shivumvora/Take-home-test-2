{# Type 2 product history derived from the full product snapshots. See macros/history_from_snapshots.sql. #}

{{ history_from_snapshots(ref('stg_ecom__products'), 'product_id', 'product_version_id') }}
