SET search_path TO shiryaev_food, exts, public;

CREATE OR REPLACE PROCEDURE add_product(
    p_restaurant_id       uuid,
    p_product_category_id uuid,
    p_name                varchar,
    p_price               numeric,
    p_rating              numeric,
    p_status              product_status,
    p_description         text,
    p_photo_url           text DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM restaurant WHERE restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'Ресторан с id % не существует', p_restaurant_id;   -- BR-5.1
    END IF;

    IF NOT EXISTS (SELECT 1 FROM product_category WHERE product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'Категория с id % не существует', p_product_category_id;
    END IF;

    IF p_price < 0 THEN
        RAISE EXCEPTION 'Цена не может быть отрицательной';                  -- BR-5.3
    END IF;

    IF p_rating IS NOT NULL AND (p_rating < 0 OR p_rating > 5) THEN
        RAISE EXCEPTION 'Рейтинг должен быть от 0 до 5';                     -- BR-5.4
    END IF;

    INSERT INTO product (product_id, product_name, product_category_id, price,
                         restaurant_id, photo_url, rating, status, description)
    VALUES (exts.uuid_generate_v4(), p_name, p_product_category_id, p_price,
            p_restaurant_id, p_photo_url, p_rating, p_status, p_description);
END;
$$;
