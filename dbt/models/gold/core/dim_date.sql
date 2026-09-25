{{ config(unique_key='date_day') }}

{#
    Calendar dimension, 2020-01-01 to 2030-12-31. Role-played as order date and
    inventory snapshot date. Incremental runs only append dates beyond the current end.
#}

with spine as (

    select
        dateadd(day, row_number() over (order by seq4()) - 1, '2020-01-01'::date) as date_day
    from table(generator(rowcount => 4018))

)

select
    date_day,
    year(date_day)                          as year_number,
    quarter(date_day)                       as quarter_number,
    month(date_day)                         as month_number,
    monthname(date_day)                     as month_name,
    date_trunc(month, date_day)             as month_start_date,
    weekiso(date_day)                       as iso_week_number,
    day(date_day)                           as day_of_month,
    dayofweekiso(date_day)                  as iso_day_of_week,
    dayname(date_day)                       as day_name,
    dayofweekiso(date_day) in (6, 7)        as is_weekend,
    current_timestamp()::timestamp_ltz      as _inserted_at,
    current_timestamp()::timestamp_ltz      as _updated_at
from spine
where date_day <= '2030-12-31'::date
{% if is_incremental() %}
  and date_day > (select max(date_day) from {{ this }})
{% endif %}
