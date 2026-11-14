SET search_path TO shiryaev_food, exts, public;

CREATE OR REPLACE PROCEDURE courier_salary()
LANGUAGE plpgsql
AS $$
DECLARE
    v_year       int;
    v_month      int;
    v_courier    RECORD;
    v_del_count  int;
    v_comm_sum   numeric(9,2);
    v_coeff_used numeric(3,2);
    v_new_coeff  numeric(3,2);
BEGIN
    v_year  := extract(year FROM current_date)::int;
    v_month := extract(month FROM current_date)::int;

    FOR v_courier IN SELECT courier_id, coefficient, status FROM courier LOOP
        SELECT count(*), coalesce(sum(o.commission), 0)
        INTO v_del_count, v_comm_sum
        FROM "order" o
        WHERE o.courier_id = v_courier.courier_id
          AND o.status = 'доставлен'
          AND o.order_timestamp >= date_trunc('month', current_date)
          AND o.order_timestamp < date_trunc('month', current_date) + interval '1 month';

        -- повторный вызов: коэффициент берём из уже сохранённой записи
        SELECT cp.coefficient_used INTO v_coeff_used
        FROM courier_pay cp
        WHERE cp.year = v_year
          AND cp.month = v_month
          AND cp.courier_id = v_courier.courier_id;

        IF v_coeff_used IS NULL THEN
            v_coeff_used := v_courier.coefficient;
        END IF;

        -- BR-10.2: новый коэффициент на следующий месяц
        IF v_del_count <= 150 THEN
            v_new_coeff := 0.1;
        ELSIF v_del_count <= 250 THEN
            v_new_coeff := 0.2;
        ELSIF v_del_count <= 500 THEN
            v_new_coeff := 0.3;
        ELSE
            v_new_coeff := 0.5;
        END IF;

        -- BR-10.2: зарплата = коэффициент месяца * сумма commission; BR-10.3: одна запись за месяц
        INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
        VALUES (v_year, v_month, v_courier.courier_id,
                round(v_coeff_used * v_comm_sum, 2), v_coeff_used)
        ON CONFLICT (year, month, courier_id) DO UPDATE
        SET amount = EXCLUDED.amount,
            coefficient_used = EXCLUDED.coefficient_used;

        -- BR-10.6: уволенным коэффициент не обновляется
        IF v_courier.status <> 'уволен' THEN
            UPDATE courier
            SET coefficient = v_new_coeff
            WHERE courier_id = v_courier.courier_id;
        END IF;
    END LOOP;
END;
$$;
