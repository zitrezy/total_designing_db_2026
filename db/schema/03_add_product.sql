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
LANGUAGE sql
AS $$
    INSERT INTO product (product_name, product_category_id, price, restaurant_id,
                         photo_url, rating, status, description)
    VALUES (p_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_rating, p_status, p_description);
$$;