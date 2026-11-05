{#
  Use custom schema names as-is (raw, reference, staging, ...) instead of
  dbt's default "<target_schema>_<custom_schema>" so the layers are easy to
  find in DBeaver. Resources without a custom schema use the target schema.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
