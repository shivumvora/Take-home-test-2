{# Type 2 customer history derived from the full customer snapshots. See macros/history_from_snapshots.sql. #}

{{ history_from_snapshots(ref('stg_ecom__customers'), 'customer_id', 'customer_version_id') }}
