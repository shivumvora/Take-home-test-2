# Lead Data Engineer Take-Home - Source Data

This package contains two delivery days of synthetic commerce data. The files are intentionally small enough to work with quickly, but they include common behaviors that a production ingestion/modeling approach should handle.

## File behavior

- `customers_*.csv` - full snapshot as of that delivery day. `customer_id` is the stable source key.
- `products_*.csv` - full snapshot as of that delivery day. `product_id` is the stable source key.
- `order_headers_*.csv` - incremental delivery. Existing `order_id` values may reappear when an order changes, and an exact duplicate may appear.
- `order_lines_*.csv` - incremental delivery. Existing `line_id` values may reappear when a line is corrected, and an exact duplicate may appear.
- `inventory_*.csv` - point-in-time daily snapshot by `snapshot_date`, `location_id`, and `product_id`.

## Notes

- Timestamps are UTC.
- Currency values are USD.
- Process Day 1, then Day 2. Your approach should also behave correctly if Day 2 is accidentally processed again.
- The data is synthetic and intentionally does not reference the hiring company.
- You may use any tools or approach you believe are appropriate.
