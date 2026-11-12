SET search_path TO shiryaev_food, exts, public;

-- BR-11.8: "order" читается один раз, без оконных функций и повторных подзапросов
-- BR-2.6: best_user — логин клиента
CREATE OR REPLACE FUNCTION get_statistic()
RETURNS TABLE (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
LANGUAGE sql
AS $$
WITH delivered AS MATERIALIZED (
    SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount
    FROM "order" o
    WHERE o.status = 'доставлен'
),
rest_agg AS (
    SELECT restaurant_id,
           sum(total_amount) AS total_amount,
           avg(total_amount) AS avg_amount
    FROM delivered
    GROUP BY restaurant_id
),
best_product AS (
    -- при равенстве — случайное блюдо
    SELECT DISTINCT ON (d.restaurant_id)
           d.restaurant_id,
           p.product_name
    FROM delivered d
    JOIN order_structure os ON os.order_id = d.order_id
    JOIN product p ON p.product_id = os.product_id
    GROUP BY d.restaurant_id, p.product_id, p.product_name
    ORDER BY d.restaurant_id, sum(os.quantity) DESC, random()
),
best_user AS (
    -- при равенстве — случайный клиент
    SELECT DISTINCT ON (d.restaurant_id)
           d.restaurant_id,
           c.login
    FROM delivered d
    JOIN client c ON c.client_id = d.client_id
    GROUP BY d.restaurant_id, d.client_id, c.login
    ORDER BY d.restaurant_id, count(*) DESC, random()
)
SELECT r.restaurant_name,
       bp.product_name AS best_product_name,
       coalesce(ra.total_amount, 0) AS total_amount,
       coalesce(ra.avg_amount, 0) AS avg_amount,
       bu.login AS best_user
FROM restaurant r
LEFT JOIN rest_agg ra ON ra.restaurant_id = r.restaurant_id
LEFT JOIN best_product bp ON bp.restaurant_id = r.restaurant_id
LEFT JOIN best_user bu ON bu.restaurant_id = r.restaurant_id;
$$;
