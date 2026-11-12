SET search_path TO shiryaev_food, exts, public;

-- BR-11.9: непрерывная серия месяцев от первого доставленного заказа до последнего
CREATE OR REPLACE VIEW how_much_money AS
WITH RECURSIVE
month_agg AS (
    SELECT date_trunc('month', o.order_timestamp)::date AS m,
           sum(o.order_amount) AS sum_no_commission,
           sum(o.total_amount) AS sum_with_commission
    FROM "order" o
    WHERE o.status = 'доставлен'
    GROUP BY 1
),
months AS (
    SELECT min(m) AS m,
           max(m) AS last_m
    FROM month_agg
    UNION ALL
    SELECT (m + interval '1 month')::date,
           last_m
    FROM months
    WHERE m < last_m
),
pay_agg AS (
    SELECT make_date(cp.year, cp.month, 1) AS m,
           sum(cp.amount) AS courier_pay
    FROM courier_pay cp
    GROUP BY 1
),
base AS (
    SELECT ms.m,
           coalesce(ma.sum_no_commission, 0) AS sum_no_commission,
           coalesce(ma.sum_with_commission, 0) AS sum_with_commission,
           coalesce(ma.sum_with_commission, 0) - coalesce(ma.sum_no_commission, 0) AS commission,
           coalesce(pa.courier_pay, 0) AS courier_pay
    FROM months ms
    LEFT JOIN month_agg ma ON ma.m = ms.m
    LEFT JOIN pay_agg pa ON pa.m = ms.m
    WHERE ms.m IS NOT NULL
)
SELECT to_char(m, 'YYYY-MM') AS year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       lag(commission) OVER (ORDER BY m) AS prev_commission,
       commission - lag(commission) OVER (ORDER BY m) AS commission_diff,
       courier_pay,
       commission - courier_pay AS net_profit
FROM base;
