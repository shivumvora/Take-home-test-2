{# Every key in a type 2 history has exactly one current version. #}
{% test has_one_current_version(model, column_name) %}

select {{ column_name }}
from {{ model }}
group by {{ column_name }}
having count_if(is_current) != 1

{% endtest %}


{# Validity windows move forward: valid_to, when set, is after valid_from. #}
{% test valid_period(model, column_name) %}

select *
from {{ model }}
where valid_to is not null
  and valid_to <= valid_from

{% endtest %}
