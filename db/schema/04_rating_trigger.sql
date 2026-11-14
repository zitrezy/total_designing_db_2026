SET search_path TO shiryaev_food, exts, public;

CREATE OR REPLACE FUNCTION rating_change()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.entity_type = 'блюдо' THEN
            UPDATE product
            SET rating = (SELECT round(avg(rating), 2)
                          FROM review
                          WHERE entity_type = 'блюдо' AND entity_id = OLD.entity_id)
            WHERE product_id = OLD.entity_id;
        ELSIF OLD.entity_type = 'ресторан' THEN
            UPDATE restaurant
            SET rating = (SELECT round(avg(rating), 2)
                          FROM review
                          WHERE entity_type = 'ресторан' AND entity_id = OLD.entity_id)
            WHERE restaurant_id = OLD.entity_id;
        END IF;
        RETURN NULL;
    END IF;

    IF NEW.entity_type = 'блюдо' THEN
        UPDATE product
        SET rating = (SELECT round(avg(rating), 2)
                      FROM review
                      WHERE entity_type = 'блюдо' AND entity_id = NEW.entity_id)
        WHERE product_id = NEW.entity_id;
    ELSIF NEW.entity_type = 'ресторан' THEN
        UPDATE restaurant
        SET rating = (SELECT round(avg(rating), 2)
                      FROM review
                      WHERE entity_type = 'ресторан' AND entity_id = NEW.entity_id)
        WHERE restaurant_id = NEW.entity_id;
    END IF;

    IF TG_OP = 'UPDATE'
       AND (NEW.entity_type <> OLD.entity_type OR NEW.entity_id <> OLD.entity_id) THEN
        IF OLD.entity_type = 'блюдо' THEN
            UPDATE product
            SET rating = (SELECT round(avg(rating), 2)
                          FROM review
                          WHERE entity_type = 'блюдо' AND entity_id = OLD.entity_id)
            WHERE product_id = OLD.entity_id;
        ELSIF OLD.entity_type = 'ресторан' THEN
            UPDATE restaurant
            SET rating = (SELECT round(avg(rating), 2)
                          FROM review
                          WHERE entity_type = 'ресторан' AND entity_id = OLD.entity_id)
            WHERE restaurant_id = OLD.entity_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rating_change ON review;
CREATE TRIGGER trg_rating_change
AFTER INSERT OR UPDATE OR DELETE ON review
FOR EACH ROW EXECUTE FUNCTION rating_change();