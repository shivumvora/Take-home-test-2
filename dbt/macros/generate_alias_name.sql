{#
    Views are named V_<model> in every schema (V_STG_ECOM__CUSTOMERS, V_RPT_DAILY_SALES),
    so a reader can tell a view from a physical table by name alone. Model names and
    ref() calls are unchanged; only the Snowflake object name gets the prefix.
#}
{% macro generate_alias_name(custom_alias_name=none, node=none) -%}
    {%- set base_name = custom_alias_name | trim if custom_alias_name else node.name -%}
    {%- if node.resource_type == 'model' and node.config.materialized == 'view' -%}
        {{ 'v_' ~ base_name }}
    {%- else -%}
        {{ base_name }}
    {%- endif -%}
{%- endmacro %}
