{# Shared column conventions for staging models. #}

{# Parse an ISO-8601 text timestamp and return it as UTC TIMESTAMP_NTZ (NULL if unparseable). #}
{% macro to_utc_timestamp(column) -%}
    convert_timezone('UTC', try_to_timestamp_tz(trim({{ column }})))::timestamp_ntz
{%- endmacro %}

{# Delivery date carried in the landed file name, e.g. customers/customers_2026-09-01.csv.gz. #}
{% macro delivery_date_from_file(column='_source_file_name') -%}
    try_to_date(regexp_substr({{ column }}, '[0-9]{4}-[0-9]{2}-[0-9]{2}'))
{%- endmacro %}

{# Deterministic hash of business columns, used for change detection and duplicate checks. #}
{% macro hash_columns(columns) -%}
    md5(concat_ws('||'
    {%- for column in columns %},
        coalesce(cast({{ column }} as varchar), '<null>')
    {%- endfor %}
    ))
{%- endmacro %}
