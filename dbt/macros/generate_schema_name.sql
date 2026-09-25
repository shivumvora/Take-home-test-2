{#
    prod builds each layer into its exact schema (SILVER, GOLD) rather than dbt's
    default <target_schema>_<custom_schema>. Any other target is a sandbox and gets
    prefixed schemas (DEV_SILVER, DEV_GOLD) so development never touches shared data.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim | upper }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        {{ target.schema | trim | upper }}_{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
