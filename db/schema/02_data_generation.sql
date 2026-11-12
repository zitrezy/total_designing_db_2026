SET search_path TO shiryaev_food, exts, public;

CREATE OR REPLACE PROCEDURE insert_test_data(value int)
LANGUAGE plpgsql
AS $$
DECLARE
    v_base         int;
    v_courier_base int;
    v_addr_base    int;
    v_i            int;
    v_j            int;
    v_k            int;
    v_idx          int;
    v_cnt          int;
    v_del_count    int;
    v_rnd          double precision;

    v_couriers    uuid[];
    v_clients     uuid[];
    v_restaurants uuid[];
    v_rest_new    uuid[];
    v_categories  uuid[];
    v_rest_addr   uuid[];
    v_cli_addr    uuid[];
    v_ca_client   uuid[];
    v_ca_addr     uuid[];
    v_prods       uuid[];
    v_prices      numeric[];
    v_picked      uuid[];
    v_pqty        numeric[];

    v_name        varchar(100);
    v_login       varchar(50);
    v_fio         varchar(150);
    v_street      varchar(100);
    v_house       varchar(20);
    v_apt         varchar(50);
    v_phone       varchar(15);
    v_details     text;
    v_desc        text;
    v_photo       text;
    v_start       time;
    v_end         time;
    v_hire        date;
    v_dism        date;
    v_base_ts     timestamp;
    v_ts          timestamp;
    v_ts2         timestamp;
    v_m           date;
    v_amount      numeric(14,2);
    v_price       numeric(12,2);
    v_qty         numeric(10,2);
    v_bump        numeric(10,2);
    v_total       numeric(14,2);
    v_coeff       numeric(3,2);
    v_comm_sum    numeric(14,2);
    v_rating      numeric(3,2);
    v_first_price numeric(12,2);
    v_id          uuid;
    v_order_id    uuid;
    v_rest_id     uuid;
    v_client_id   uuid;
    v_addr_id     uuid;
    v_courier_id  uuid;
    v_cat_id      uuid;
    v_entity_id   uuid;
    v_c_status    courier_status;
    v_r_status    restaurant_status;
    v_p_status    product_status;
    v_o_status    order_status;
    v_pay_status  order_pay_status;
    v_pmt_status  payment_status;
    v_pmt_type    payment_type;
    v_entity_type review_entity_type;
BEGIN
    IF value IS NULL OR value < 1 THEN
        RAISE EXCEPTION 'Параметр value должен быть >= 1';
    END IF;

    -- сдвиги для уникальности при повторных вызовах
    SELECT count(*) INTO v_base         FROM client;
    SELECT count(*) INTO v_courier_base FROM courier;
    SELECT count(*) INTO v_addr_base    FROM address;

    -- 1. Курьеры
    FOR v_i IN 1..value LOOP
        v_fio := concat('Фамилия ', v_courier_base + v_i,
                        ' Имя ', v_courier_base + v_i,
                        ' Отчество ', v_courier_base + v_i);
        v_phone := concat('+7', lpad((9100000000 + v_courier_base + v_i)::text, 10, '0'));
        v_hire := current_date - floor(random() * 180)::int;
        IF v_i <= floor(value * 0.2) THEN
            v_c_status := 'уволен'::courier_status;                     -- BR-6.3
            v_dism := v_hire + floor(random() * ((current_date - v_hire)::int + 1))::int;
        ELSE
            v_c_status := (enum_range(NULL::courier_status))[1 + floor(random() * 3)::int]::courier_status;  -- BR-6.6
            v_dism := NULL;
        END IF;
        INSERT INTO courier (courier_id, fio, phone_number, status, hire_date, dismissal_date)
        VALUES (exts.uuid_generate_v4(), v_fio, v_phone, v_c_status, v_hire, v_dism);
    END LOOP;

    -- 2. Категории блюд
    FOR v_i IN 1..value LOOP
        v_name := concat('категория ', v_base + v_i);
        INSERT INTO product_category (product_category_id, product_category_name)
        VALUES (exts.uuid_generate_v4(), v_name);
    END LOOP;

    SELECT array_agg(product_category_id) INTO v_categories FROM product_category;

    -- 3. Адреса: первые value — ресторанам, остальные — клиентам (BR-11.7)
    FOR v_i IN 1..(value * 5) LOOP
        v_street := concat('улица ', v_addr_base + v_i);
        v_house := concat('дом ', v_addr_base + v_i);
        IF random() < 0.5 THEN
            v_apt := NULL;                                              -- BR-3.2
        ELSE
            v_apt := concat('кв ', v_addr_base + v_i);
        END IF;
        INSERT INTO address (address_id, street, house_number, apartment_office)
        VALUES (exts.uuid_generate_v4(), v_street, v_house, v_apt)
        RETURNING address_id INTO v_id;
        IF v_i <= value THEN
            v_rest_addr := array_append(v_rest_addr, v_id);
        ELSE
            v_cli_addr := array_append(v_cli_addr, v_id);
        END IF;
    END LOOP;

    -- 4. Рестораны
    FOR v_i IN 1..value LOOP
        v_name := concat('ресторан ', v_base + v_i);
        v_desc := concat('описание ресторана ', v_base + v_i);
        v_start := make_time(7 + floor(random() * 3)::int, (floor(random() * 2))::int * 30, 0);
        v_end := v_start + make_interval(hours => 8 + floor(random() * 7)::int);  -- BR-4.4
        v_details := concat('тест реквизиты ', v_base + v_i);
        IF random() < 0.9 THEN
            v_r_status := 'активен'::restaurant_status;
        ELSE
            v_r_status := 'неактивен'::restaurant_status;
        END IF;
        INSERT INTO restaurant (restaurant_id, restaurant_name, address_id, description,
                                work_start, work_end, company_details, rating, status)
        VALUES (exts.uuid_generate_v4(), v_name, v_rest_addr[v_i], v_desc,
                v_start, v_end, v_details, NULL, v_r_status)
        RETURNING restaurant_id INTO v_id;
        v_rest_new := array_append(v_rest_new, v_id);
    END LOOP;

    -- 5. Клиенты
    FOR v_i IN 1..value LOOP
        v_login := concat('user_', lpad((v_base + v_i)::text, 5, '0'));
        v_phone := concat('+7', lpad((9000000000 + v_base + v_i)::text, 10, '0'));
        INSERT INTO client (client_id, login, password, phone_number)
        VALUES (exts.uuid_generate_v4(), v_login, md5(random()::text), v_phone)  -- BR-2.3
        RETURNING client_id INTO v_id;
        v_clients := array_append(v_clients, v_id);
    END LOOP;

    -- 6. Связи клиент—адрес (BR-2.4, BR-2.5)
    FOR v_i IN 1..value LOOP
        v_cnt := 1 + (v_i % 3);
        FOR v_j IN 0..(v_cnt - 1) LOOP
            v_idx := ((v_i - 1) + v_j * value) % (value * 4) + 1;
            INSERT INTO client_address (client_id, address_id)
            VALUES (v_clients[v_i], v_cli_addr[v_idx]);
        END LOOP;
    END LOOP;

    -- 7. Блюда: по 5 на каждый новый ресторан
    FOR v_i IN 1..(value * 5) LOOP
        v_name := concat('блюдо ', v_base + v_i);
        v_price := round((100 + random() * 1900)::numeric, 2);          -- BR-5.3
        v_rest_id := v_rest_new[((v_i - 1) % value) + 1];
        v_cat_id := v_categories[1 + floor(random() * array_length(v_categories, 1))::int];
        IF random() < 0.8 THEN
            v_p_status := 'доступно'::product_status;
        ELSE
            v_p_status := (enum_range(NULL::product_status))[1 + floor(random() * 3)::int]::product_status;
        END IF;
        IF random() < 0.6 THEN
            v_photo := concat('фото_', v_base + v_i);
        ELSE
            v_photo := NULL;                                            -- BR-5.6
        END IF;
        v_desc := concat('описание блюда ', v_base + v_i);
        INSERT INTO product (product_id, product_name, product_category_id, price,
                             restaurant_id, photo_url, rating, status, description)
        VALUES (exts.uuid_generate_v4(), v_name, v_cat_id, v_price,
                v_rest_id, v_photo, NULL, v_p_status, v_desc);
    END LOOP;

    -- 8. Заказы + позиции + оплаты + отзывы
    SELECT array_agg(courier_id) INTO v_couriers FROM courier;
    SELECT array_agg(restaurant_id) INTO v_restaurants FROM restaurant;
    SELECT array_agg(client_id), array_agg(address_id) INTO v_ca_client, v_ca_addr FROM client_address;

    v_base_ts := date_trunc('month', current_date - interval '5 months');

    FOR v_i IN 1..(value * 5) LOOP
        -- BR-7.4: адрес — из адресов клиента
        v_idx := 1 + floor(random() * array_length(v_ca_client, 1))::int;
        v_client_id := v_ca_client[v_idx];
        v_addr_id := v_ca_addr[v_idx];
        v_rest_id := v_restaurants[1 + floor(random() * array_length(v_restaurants, 1))::int];
        v_courier_id := v_couriers[1 + floor(random() * array_length(v_couriers, 1))::int];

        -- BR-7.3, BR-7.16: 1..5 разных блюд из ресторана заказа
        SELECT array_agg(product_id), array_agg(price) INTO v_prods, v_prices
        FROM product WHERE restaurant_id = v_rest_id;
        v_k := 1 + floor(random() * 5)::int;
        v_picked := '{}'::uuid[];
        v_pqty := '{}'::numeric[];
        v_amount := 0;
        v_first_price := 0;
        FOR v_j IN 1..v_k LOOP
            v_idx := 1 + floor(random() * array_length(v_prods, 1))::int;
            v_price := v_prices[v_idx];
            v_picked := array_append(v_picked, v_prods[v_idx]);
            v_prods := v_prods[1:v_idx-1] || v_prods[v_idx+1:array_length(v_prods, 1)];
            v_prices := v_prices[1:v_idx-1] || v_prices[v_idx+1:array_length(v_prices, 1)];
            v_qty := round((0.5 + random() * 2.5)::numeric, 2);         -- BR-7.15
            v_pqty := array_append(v_pqty, v_qty);
            v_amount := v_amount + v_price * v_qty;
            IF v_j = 1 THEN
                v_first_price := v_price;
            END IF;
        END LOOP;

        -- BR-1.8: сумма заказа >= 1000
        IF v_amount < 1000 THEN
            v_bump := ceil((1000 - v_amount) / v_first_price)::numeric;
            v_pqty[1] := v_pqty[1] + v_bump;
            v_amount := v_amount + v_bump * v_first_price;
        END IF;

        v_ts := v_base_ts + random() * (localtimestamp - v_base_ts);

        v_rnd := random();
        IF v_rnd < 0.6 THEN
            v_o_status := 'доставлен'::order_status;
            v_ts2 := v_ts + random() * interval '3 hours';
            IF v_ts2 > localtimestamp THEN
                v_ts2 := localtimestamp;
            END IF;
        ELSIF v_rnd < 0.75 THEN
            v_o_status := 'в_доставке'::order_status;
            v_ts2 := NULL;
        ELSIF v_rnd < 0.85 THEN
            v_o_status := 'готовится'::order_status;
            v_ts2 := NULL;
        ELSIF v_rnd < 0.95 THEN
            v_o_status := 'создан'::order_status;
            v_ts2 := NULL;
        ELSE
            v_o_status := 'отменён'::order_status;
            v_ts2 := NULL;
        END IF;

        -- BR-8.7: статус оплаты соответствует попытке
        v_rnd := random();
        IF v_rnd < 0.7 THEN
            v_pay_status := 'оплачен'::order_pay_status;
        ELSIF v_rnd < 0.85 THEN
            v_pay_status := 'ошибка'::order_pay_status;
        ELSE
            v_pay_status := 'ожидает'::order_pay_status;
        END IF;

        IF random() < 0.3 THEN
            v_desc := NULL;
        ELSE
            v_desc := concat('комментарий к заказу ', v_base + v_i);
        END IF;

        INSERT INTO "order" (order_id, courier_id, client_id, address_id, restaurant_id,
                             order_timestamp, delivery_timestamp, order_amount,
                             status, pay_status, description)
        VALUES (exts.uuid_generate_v4(), v_courier_id, v_client_id, v_addr_id, v_rest_id,
                v_ts, v_ts2, round(v_amount, 2), v_o_status, v_pay_status, v_desc)
        RETURNING order_id, total_amount INTO v_order_id, v_total;

        FOR v_j IN 1..array_length(v_picked, 1) LOOP
            INSERT INTO order_structure (order_id, product_id, quantity)
            VALUES (v_order_id, v_picked[v_j], v_pqty[v_j]);
        END LOOP;

        -- payment = value*5: одна попытка на заказ (BR-8.1, BR-8.4)
        v_pmt_type := (enum_range(NULL::payment_type))[1 + floor(random() * 3)::int]::payment_type;
        IF v_pay_status = 'оплачен' THEN
            v_pmt_status := 'успех'::payment_status;
        ELSIF v_pay_status = 'ошибка' THEN
            v_pmt_status := 'ошибка'::payment_status;
        ELSE
            v_pmt_status := 'в_обработке'::payment_status;
        END IF;
        v_ts2 := v_ts + random() * interval '2 hours';
        IF v_ts2 > localtimestamp THEN
            v_ts2 := localtimestamp;
        END IF;
        INSERT INTO payment (payment_id, order_id, payment_type, amount,
                             transaction_number, transaction_timestamp, status)
        VALUES (exts.uuid_generate_v4(), v_order_id, v_pmt_type, v_total,
                concat('txn_', exts.uuid_generate_v4()), v_ts2, v_pmt_status);

        -- review = value*5: один отзыв на заказ (BR-9.1, BR-9.2, BR-9.5)
        v_entity_type := (enum_range(NULL::review_entity_type))[1 + floor(random() * 3)::int]::review_entity_type;
        IF v_entity_type = 'заказ' THEN
            v_entity_id := v_order_id;
        ELSIF v_entity_type = 'ресторан' THEN
            v_entity_id := v_rest_id;
        ELSE
            v_entity_id := v_picked[1 + floor(random() * array_length(v_picked, 1))::int];
        END IF;
        v_ts2 := v_ts + random() * interval '5 days';
        IF v_ts2 > localtimestamp THEN
            v_ts2 := localtimestamp;
        END IF;
        v_rating := (1 + floor(random() * 5)::int)::numeric;            -- BR-9.4
        v_desc := concat('тестовый отзыв ', v_base + v_i);
        IF random() < 0.5 THEN
            v_photo := concat('фото_', v_base + v_i);
        ELSE
            v_photo := NULL;                                            -- BR-9.3
        END IF;
        INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type,
                            order_id, description, photo_url, rating)
        VALUES (exts.uuid_generate_v4(), v_client_id, v_ts2, v_entity_id, v_entity_type,
                v_order_id, v_desc, v_photo, v_rating);
    END LOOP;

    -- 9. Рейтинги по отзывам (BR-9.6, BR-9.7)
    UPDATE product p
    SET rating = round(s.avg_r, 2)
    FROM (
        SELECT entity_id, avg(rating) AS avg_r
        FROM review
        WHERE entity_type = 'блюдо'
        GROUP BY entity_id
    ) s
    WHERE p.product_id = s.entity_id;

    UPDATE restaurant r
    SET rating = round(s.avg_r, 2)
    FROM (
        SELECT entity_id, avg(rating) AS avg_r
        FROM review
        WHERE entity_type = 'ресторан'
        GROUP BY entity_id
    ) s
    WHERE r.restaurant_id = s.entity_id;

    -- 10. Выплаты за 6 месяцев (BR-10.2, BR-10.7); доставок < 151 -> коэффициент 0.1
    FOR v_i IN 1..array_length(v_couriers, 1) LOOP
        v_m := (date_trunc('month', current_date - interval '5 months'))::date;
        FOR v_j IN 1..6 LOOP
            SELECT coalesce(sum(o.commission), 0)
            INTO v_comm_sum
            FROM "order" o
            WHERE o.courier_id = v_couriers[v_i]
              AND o.status = 'доставлен'
              AND o.order_timestamp >= v_m
              AND o.order_timestamp < v_m + interval '1 month';
            INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
            VALUES (extract(year FROM v_m)::int, extract(month FROM v_m)::int,
                    v_couriers[v_i], round(v_comm_sum * 0.1, 2), 0.1)
            ON CONFLICT (year, month, courier_id) DO UPDATE
            SET amount = EXCLUDED.amount,
                coefficient_used = EXCLUDED.coefficient_used;
            v_m := v_m + interval '1 month';
        END LOOP;
    END LOOP;

    -- 11. Коэффициент на следующий месяц (BR-10.2); уволенным не назначается (BR-10.6)
    FOR v_i IN 1..array_length(v_couriers, 1) LOOP
        SELECT count(*) INTO v_del_count
        FROM "order" o
        WHERE o.courier_id = v_couriers[v_i]
          AND o.status = 'доставлен'
          AND o.order_timestamp >= date_trunc('month', current_date)
          AND o.order_timestamp < date_trunc('month', current_date) + interval '1 month';
        IF v_del_count <= 150 THEN
            v_coeff := 0.1;
        ELSIF v_del_count <= 250 THEN
            v_coeff := 0.2;
        ELSIF v_del_count <= 500 THEN
            v_coeff := 0.3;
        ELSE
            v_coeff := 0.5;
        END IF;
        UPDATE courier
        SET coefficient = v_coeff
        WHERE courier_id = v_couriers[v_i]
          AND status <> 'уволен';
    END LOOP;
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
