SET search_path TO shiryaev_food, exts, public;

CREATE OR REPLACE PROCEDURE insert_test_data(value int)
LANGUAGE plpgsql
AS $$
DECLARE
    alphabet constant text := 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';

    client_count  int;
    courier_count int;
    payment_count int;

    restaurant_addresses uuid[];
    client_addresses     uuid[];
    restaurants          uuid[];
    clients              uuid[];
    couriers             uuid[];
    categories           uuid[];

    pairs_client  uuid[];
    pairs_address uuid[];

    product_ids    uuid[];
    product_prices numeric[];
    picked_ids     uuid[];
    picked_qty     numeric[];

    new_order_id uuid;
    order_ts     timestamp;
    delivery_ts  timestamp;
    order_total  numeric(9,2);
    order_sum    numeric(9,2);
    first_price  numeric(8,2);
    bump         numeric(10,2);
    rand_val     double precision;

    order_no    int;
    pos_idx     int;
    pick_idx    int;
    pair_idx    int;
    rest_idx    int;
    courier_idx int;

    st            order_status;
    review_type   review_entity_type;
    review_entity uuid;
BEGIN
    IF value IS NULL OR value < 1 THEN
        RAISE EXCEPTION 'Параметр value должен быть >= 1';
    END IF;

    SELECT count(*) INTO client_count  FROM client;
    SELECT count(*) INTO courier_count FROM courier;
    SELECT count(*) INTO payment_count FROM payment;

    -- 1. Курьеры
    WITH ins AS (
        INSERT INTO courier (courier_id, last_name, first_name, middle_name,
                             phone_number, status, hire_date, dismissal_date)
        SELECT exts.uuid_generate_v4(),
               substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 50),
               substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 50),
               substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 50),
               concat('+7', lpad((9100000000 + courier_count + g.i)::text, 10, '0')),
               CASE WHEN g.fired THEN 'уволен'::courier_status
                    ELSE (enum_range(NULL::courier_status))[1 + floor(random() * 3)::int] END,
               g.hire_date,
               CASE WHEN g.fired
                    THEN g.hire_date + floor(random() * (current_date - g.hire_date + 1))::int
                    ELSE NULL END
        FROM (
            SELECT s.i,
                   current_date - (random() * 180)::int AS hire_date,
                   (s.i <= floor(value * 0.2)) AS fired
            FROM generate_series(1, value) AS s(i)
        ) g
        RETURNING courier_id
    )
    SELECT array_agg(courier_id) INTO couriers FROM ins;

    -- 2. Категории блюд
    WITH ins AS (
        INSERT INTO product_category (product_category_id, product_category_name)
        SELECT exts.uuid_generate_v4(),
               substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 50)
        FROM generate_series(1, value)
        RETURNING product_category_id
    )
    SELECT array_agg(product_category_id) INTO categories FROM ins;

    -- 3. Адреса: value — ресторанам, value*4 — клиентам
    WITH ins AS (
        INSERT INTO address (address_id, street, house_number, apartment_office)
        SELECT exts.uuid_generate_v4(),
               substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 100),
               (1 + floor(random() * 200))::text,
               CASE WHEN random() < 0.5 THEN NULL
                    ELSE substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 50) END
        FROM generate_series(1, value)
        RETURNING address_id
    )
    SELECT array_agg(address_id) INTO restaurant_addresses FROM ins;

    WITH ins AS (
        INSERT INTO address (address_id, street, house_number, apartment_office)
        SELECT exts.uuid_generate_v4(),
               substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 100),
               (1 + floor(random() * 200))::text,
               CASE WHEN random() < 0.5 THEN NULL
                    ELSE substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 50) END
        FROM generate_series(1, value * 4)
        RETURNING address_id
    )
    SELECT array_agg(address_id) INTO client_addresses FROM ins;

    -- 4. Рестораны
    WITH ins AS (
        INSERT INTO restaurant (restaurant_id, restaurant_name, address_id, description,
                                work_start, work_end, inn, ogrn, settlement_account, rating, status)
        SELECT exts.uuid_generate_v4(),
               substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 100),
               restaurant_addresses[g.i],
               repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int),
               g.start_time,
               g.start_time + (8 + floor(random() * 6)::int) * interval '1 hour',
               substring(md5(random()::text), 1, 1 + floor(random() * 12)::int),
               substring(md5(random()::text), 1, 1 + floor(random() * 15)::int),
               substring(md5(random()::text), 1, 1 + floor(random() * 20)::int),
               NULL,
               CASE WHEN random() < 0.9 THEN 'активен'::restaurant_status ELSE 'неактивен'::restaurant_status END
        FROM (
            SELECT s.i, make_time(8 + floor(random() * 3)::int, 0, 0) AS start_time
            FROM generate_series(1, value) AS s(i)
        ) g
        RETURNING restaurant_id
    )
    SELECT array_agg(restaurant_id) INTO restaurants FROM ins;

    -- 5. Клиенты
    WITH ins AS (
        INSERT INTO client (client_id, login, password, phone_number)
        SELECT exts.uuid_generate_v4(),
               concat(substring(md5(random()::text), 1, 10), lpad((client_count + g.i)::text, 5, '0')),
               md5(random()::text),
               concat('+7', lpad((9000000000 + client_count + g.i)::text, 10, '0'))
        FROM generate_series(1, value) AS g(i)
        RETURNING client_id
    )
    SELECT array_agg(client_id) INTO clients FROM ins;

    -- 6. Связи клиент—адрес: 1..3 разных адреса у клиента
    INSERT INTO client_address (client_id, address_id)
    SELECT clients[i], client_addresses[((i - 1) + d * value) % (value * 4) + 1]
    FROM generate_series(1, value) AS i
    CROSS JOIN generate_series(0, i % 3) AS d;

    -- 7. Блюда: по 5 на новый ресторан
    INSERT INTO product (product_id, product_name, product_category_id, price,
                         restaurant_id, photo_url, rating, status, description)
    SELECT exts.uuid_generate_v4(),
           substring(repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, 100),
           categories[1 + floor(random() * array_length(categories, 1))::int],
           round((100 + random() * 1900)::numeric, 2),
           restaurants[((g.i - 1) % value) + 1],
           CASE WHEN random() < 0.5
                THEN concat('https://cdn.foodexpress.ru/img/', md5(random()::text), '.jpg')
                ELSE NULL END,
           NULL,
           CASE WHEN random() < 0.8 THEN 'доступно'::product_status
                ELSE (enum_range(NULL::product_status))[1 + floor(random() * 3)::int] END,
           repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int)
    FROM generate_series(1, value * 5) AS g(i);

    -- 8. Заказы + позиции + оплата + отзыв
    SELECT array_agg(client_id), array_agg(address_id)
    INTO pairs_client, pairs_address
    FROM (SELECT client_id, address_id FROM client_address ORDER BY client_id, address_id) t;

    FOR order_no IN 1..(value * 5) LOOP
        pair_idx    := 1 + floor(random() * array_length(pairs_client, 1))::int;
        rest_idx    := 1 + floor(random() * array_length(restaurants, 1))::int;
        courier_idx := 1 + floor(random() * array_length(couriers, 1))::int;

        SELECT array_agg(product_id ORDER BY product_id), array_agg(price ORDER BY product_id)
        INTO product_ids, product_prices
        FROM product
        WHERE restaurant_id = restaurants[rest_idx];

        picked_ids := '{}'::uuid[];
        picked_qty := '{}'::numeric[];
        order_sum := 0;
        first_price := 0;

        FOR pos_idx IN 1..least(5, array_length(product_ids, 1)) LOOP
            pick_idx := 1 + floor(random() * array_length(product_ids, 1))::int;
            picked_ids  := picked_ids || product_ids[pick_idx];
            picked_qty  := picked_qty || round((0.5 + random() * 2.5)::numeric, 2);
            IF pos_idx = 1 THEN
                first_price := product_prices[pick_idx];
            END IF;
            order_sum := order_sum + product_prices[pick_idx] * picked_qty[pos_idx];
            product_ids    := product_ids[1:pick_idx-1] || product_ids[pick_idx+1:array_length(product_ids, 1)];
            product_prices := product_prices[1:pick_idx-1] || product_prices[pick_idx+1:array_length(product_prices, 1)];
        END LOOP;

        IF order_sum < 1000 THEN
            bump := ceil((1000 - order_sum) / first_price)::numeric;
            picked_qty[1] := picked_qty[1] + bump;
            order_sum := order_sum + bump * first_price;
        END IF;

        order_ts := localtimestamp - (random() * 180)::int * interval '1 day';

        rand_val := random();
        IF rand_val < 0.6 THEN
            st := 'доставлен'::order_status;
            delivery_ts := least(localtimestamp, order_ts + (random() * 3)::int * interval '1 hour');
        ELSIF rand_val < 0.75 THEN
            st := 'в_доставке'::order_status;
            delivery_ts := NULL;
        ELSIF rand_val < 0.85 THEN
            st := 'готовится'::order_status;
            delivery_ts := NULL;
        ELSIF rand_val < 0.95 THEN
            st := 'создан'::order_status;
            delivery_ts := NULL;
        ELSE
            st := 'отменён'::order_status;
            delivery_ts := NULL;
        END IF;

        INSERT INTO "order" (order_id, courier_id, client_id, address_id, restaurant_id,
                             order_timestamp, delivery_timestamp, order_amount,
                             status, pay_status, description)
        VALUES (exts.uuid_generate_v4(), couriers[courier_idx], pairs_client[pair_idx], pairs_address[pair_idx],
                restaurants[rest_idx], order_ts, delivery_ts, round(order_sum, 2), st, 'оплачен',
                CASE WHEN random() < 0.3 THEN NULL
                     ELSE repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int) END)
        RETURNING order_id, total_amount INTO new_order_id, order_total;

        FOR pos_idx IN 1..array_length(picked_ids, 1) LOOP
            INSERT INTO order_structure (order_id, product_id, quantity)
            VALUES (new_order_id, picked_ids[pos_idx], picked_qty[pos_idx]);
        END LOOP;

        INSERT INTO payment (payment_id, order_id, payment_type, amount,
                             transaction_number, transaction_timestamp, status)
        VALUES (exts.uuid_generate_v4(), new_order_id,
                (enum_range(NULL::payment_type))[1 + floor(random() * 3)::int],
                order_total,
                concat(substring(concat(md5(random()::text), md5(random()::text)), 1, 40),
                       lpad((payment_count + order_no)::text, 10, '0')),
                least(localtimestamp, order_ts + (random() * 2)::int * interval '1 hour'),
                'успех');

        review_type := (enum_range(NULL::review_entity_type))[1 + floor(random() * 3)::int];
        IF review_type = 'заказ' THEN
            review_entity := new_order_id;
        ELSIF review_type = 'ресторан' THEN
            review_entity := restaurants[rest_idx];
        ELSE
            review_entity := picked_ids[1 + floor(random() * array_length(picked_ids, 1))::int];
        END IF;

        INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type,
                            order_id, description, photo_url, rating)
        VALUES (exts.uuid_generate_v4(), pairs_client[pair_idx],
                least(localtimestamp, order_ts + (random() * 30)::int * interval '1 day'),
                review_entity, review_type, new_order_id,
                repeat(substring(alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int),
                CASE WHEN random() < 0.5
                     THEN concat('https://cdn.foodexpress.ru/img/', md5(random()::text), '.jpg')
                     ELSE NULL END,
                1 + floor(random() * 5));
    END LOOP;

    -- 9. Рейтинги по отзывам (BR-9.6, BR-9.7)
    UPDATE product p
    SET rating = round(s.avg_rating, 2)
    FROM (SELECT entity_id, avg(rating) AS avg_rating
          FROM review WHERE entity_type = 'блюдо' GROUP BY entity_id) s
    WHERE p.product_id = s.entity_id;

    UPDATE restaurant r
    SET rating = round(s.avg_rating, 2)
    FROM (SELECT entity_id, avg(rating) AS avg_rating
          FROM review WHERE entity_type = 'ресторан' GROUP BY entity_id) s
    WHERE r.restaurant_id = s.entity_id;

    -- 10. Выплаты за 6 месяцев (BR-10.2, BR-10.7)
    INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
    SELECT extract(year FROM m)::int, extract(month FROM m)::int, c.courier_id,
           coalesce(round(sum(o.commission) * 0.1, 2), 0),
           0.1
    FROM generate_series(date_trunc('month', current_date - interval '5 months'),
                         date_trunc('month', current_date),
                         interval '1 month') AS m
    CROSS JOIN courier c
    LEFT JOIN "order" o
           ON o.courier_id = c.courier_id
          AND o.status = 'доставлен'
          AND o.order_timestamp >= m
          AND o.order_timestamp < m + interval '1 month'
    GROUP BY m, c.courier_id
    ON CONFLICT (year, month, courier_id) DO UPDATE
    SET amount = EXCLUDED.amount,
        coefficient_used = EXCLUDED.coefficient_used;

    -- 11. Коэффициент на следующий месяц (BR-10.2); уволенным не назначается (BR-10.6)
    UPDATE courier c
    SET coefficient = CASE
            WHEN d.cnt <= 150 THEN 0.1
            WHEN d.cnt <= 250 THEN 0.2
            WHEN d.cnt <= 500 THEN 0.3
            ELSE 0.5
        END
    FROM (
        SELECT courier_id, count(*) AS cnt
        FROM "order"
        WHERE status = 'доставлен'
          AND order_timestamp >= date_trunc('month', current_date)
          AND order_timestamp < date_trunc('month', current_date) + interval '1 month'
        GROUP BY courier_id
    ) d
    WHERE c.courier_id = d.courier_id
      AND c.status <> 'уволен';
END;
$$;

CREATE OR REPLACE PROCEDURE erase_test_data()
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM review;
    DELETE FROM payment;
    DELETE FROM order_structure;
    DELETE FROM "order";
    DELETE FROM courier_pay;
    DELETE FROM client_address;
    DELETE FROM product;
    DELETE FROM restaurant;
    DELETE FROM courier;
    DELETE FROM client;
    DELETE FROM product_category;
    DELETE FROM address;
END;
$$;
