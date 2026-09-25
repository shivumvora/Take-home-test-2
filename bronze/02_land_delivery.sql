-- Land one delivery's files in the ECOM landing stage, one folder per entity.
-- Usage:
--   snow sql -f bronze/02_land_delivery.sql -D "delivery_dir=<absolute path to a day_N folder>"
-- PUT does not overwrite a file that is already in the stage, so landing the same
-- delivery twice is a no-op. No warehouse is needed.

PUT 'file://<% delivery_dir %>/customers_*.csv'     @CANDIDATE_SHIVUM.BRONZE.ECOM_LANDING/customers/     AUTO_COMPRESS = TRUE OVERWRITE = FALSE;
PUT 'file://<% delivery_dir %>/products_*.csv'      @CANDIDATE_SHIVUM.BRONZE.ECOM_LANDING/products/      AUTO_COMPRESS = TRUE OVERWRITE = FALSE;
PUT 'file://<% delivery_dir %>/order_headers_*.csv' @CANDIDATE_SHIVUM.BRONZE.ECOM_LANDING/order_headers/ AUTO_COMPRESS = TRUE OVERWRITE = FALSE;
PUT 'file://<% delivery_dir %>/order_lines_*.csv'   @CANDIDATE_SHIVUM.BRONZE.ECOM_LANDING/order_lines/   AUTO_COMPRESS = TRUE OVERWRITE = FALSE;
PUT 'file://<% delivery_dir %>/inventory_*.csv'     @CANDIDATE_SHIVUM.BRONZE.ECOM_LANDING/inventory/     AUTO_COMPRESS = TRUE OVERWRITE = FALSE;
