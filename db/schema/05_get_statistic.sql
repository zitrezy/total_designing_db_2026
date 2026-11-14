SET search_path TO shiryaev_food, exts, public;

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
    SELECT restaurant_id, sum(total_amount) AS total_amount, avg(total_amount) AS avg_amount
    FROM delivered GROUP BY restaurant_id
),
product_qty AS (
    SELECT d.restaurant_id, os.product_id, sum(os.quantity) AS qty
    FROM delivered d
    JOIN order_structure os ON os.order_id = d.order_id
    GROUP BY d.restaurant_id, os.product_id
),
product_max AS (
    SELECT restaurant_id, max(qty) AS max_qty
    FROM product_qty GROUP BY restaurant_id
),
best_product AS (
    SELECT pq.restaurant_id,
           (array_agg(pq.product_id))[1 + floor(random() * count(*))::int] AS product_id
    FROM product_qty pq
    JOIN product_max pm ON pm.restaurant_id = pq.restaurant_id AND pm.max_qty = pq.qty
    GROUP BY pq.restaurant_id
),
client_cnt AS (
    SELECT d.restaurant_id, d.client_id, count(*) AS cnt
    FROM delivered d GROUP BY d.restaurant_id, d.client_id
),
client_max AS (
    SELECT restaurant_id, max(cnt) AS max_cnt
    FROM client_cnt GROUP BY restaurant_id
),
best_client AS (
    SELECT cc.restaurant_id,
           (array_agg(cc.client_id))[1 + floor(random() * count(*))::int] AS client_id
    FROM client_cnt cc
    JOIN client_max cm ON cm.restaurant_id = cc.restaurant_id AND cm.max_cnt = cc.cnt
    GROUP BY cc.restaurant_id
)
SELECT r.restaurant_name,
       p.product_name AS best_product_name,
       coalesce(ra.total_amount, 0) AS total_amount,
       coalesce(ra.avg_amount, 0) AS avg_amount,
       c.login AS best_user
FROM restaurant r
LEFT JOIN rest_agg ra ON ra.restaurant_id = r.restaurant_id
LEFT JOIN best_product bp ON bp.restaurant_id = r.restaurant_id
LEFT JOIN product p ON p.product_id = bp.product_id
LEFT JOIN best_client bc ON bc.restaurant_id = r.restaurant_id
LEFT JOIN client c ON c.client_id = bc.client_id;
$$;
