DROP SCHEMA IF EXISTS shiryaev_food CASCADE;
CREATE SCHEMA shiryaev_food;

SET search_path TO shiryaev_food, exts, public;

CREATE TYPE restaurant_status  AS ENUM ('активен', 'неактивен');                              -- BR-4.3
CREATE TYPE product_status     AS ENUM ('доступно', 'нет_в_наличии', 'архив');                -- BR-5.5
CREATE TYPE courier_status     AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');        -- BR-6.2
CREATE TYPE order_status       AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён'); -- BR-7.7
CREATE TYPE order_pay_status   AS ENUM ('ожидает', 'оплачен', 'ошибка');                      -- BR-7.9
CREATE TYPE payment_status     AS ENUM ('успех', 'ошибка', 'в_обработке');                    -- BR-8.2
CREATE TYPE payment_type       AS ENUM ('карта', 'наличные', 'безнал');                       -- BR-8.2
CREATE TYPE review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');                        -- BR-9.1

-- Клиенты
CREATE TABLE client (
    client_id    uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),  -- BR-11.1
    login        varchar(50) NOT NULL UNIQUE,                       -- BR-2.2
    password     varchar(32) NOT NULL,                              -- BR-2.3
    phone_number varchar(15) NOT NULL UNIQUE                        -- BR-2.2
);

-- Адреса
CREATE TABLE address (
    address_id       uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street           varchar(100) NOT NULL,
    house_number     varchar(20)  NOT NULL,
    apartment_office varchar(50)                                    -- BR-3.2
);

-- Адреса клиентов
CREATE TABLE client_address (
    client_id  uuid NOT NULL REFERENCES client (client_id),
    address_id uuid NOT NULL REFERENCES address (address_id),
    PRIMARY KEY (client_id, address_id)                             -- BR-2.5
);

-- Рестораны
CREATE TABLE restaurant (
    restaurant_id   uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL,
    address_id      uuid NOT NULL UNIQUE REFERENCES address (address_id),  -- BR-3.3
    description     text NOT NULL,
    work_start      time NOT NULL,
    work_end        time NOT NULL,
    company_details text NOT NULL,
    rating          numeric(3,2),                                          -- BR-9.7
    status          restaurant_status NOT NULL,
    CONSTRAINT restaurant_rating_check    CHECK (rating >= 0 AND rating <= 5),  -- BR-4.2
    CONSTRAINT restaurant_work_time_check CHECK (work_end > work_start)         -- BR-4.4
);

-- Курьеры
CREATE TABLE courier (
    courier_id     uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio            varchar(150) NOT NULL,
    phone_number   varchar(15)  NOT NULL,
    status         courier_status NOT NULL,
    hire_date      date NOT NULL,
    dismissal_date date,                                            -- BR-6.3
    coefficient    numeric(3,2) NOT NULL DEFAULT 0.1,               -- BR-6.5
    CONSTRAINT courier_coefficient_check CHECK (coefficient BETWEEN 0.1 AND 0.5),              -- BR-6.4
    CONSTRAINT courier_dates_check        CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date)  -- BR-6.3
);

-- Выплаты курьерам
CREATE TABLE courier_pay (
    year             int NOT NULL,
    month            int NOT NULL,
    courier_id       uuid NOT NULL REFERENCES courier (courier_id),
    amount           numeric(14,2) NOT NULL,
    coefficient_used numeric(3,2)  NOT NULL,
    PRIMARY KEY (year, month, courier_id),                          -- BR-10.3
    CONSTRAINT courier_pay_amount_check     CHECK (amount >= 0),                -- BR-10.4
    CONSTRAINT courier_pay_month_check      CHECK (month BETWEEN 1 AND 12),     -- BR-11.6
    CONSTRAINT courier_pay_coefficient_check CHECK (coefficient_used BETWEEN 0.1 AND 0.5) -- BR-10.2
);

-- Категории блюд
CREATE TABLE product_category (
    product_category_id   uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(50) NOT NULL
);

-- Блюда
CREATE TABLE product (
    product_id          uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name        varchar(100) NOT NULL,
    product_category_id uuid NOT NULL REFERENCES product_category (product_category_id), -- BR-5.1
    price               numeric(12,2) NOT NULL,
    restaurant_id       uuid NOT NULL REFERENCES restaurant (restaurant_id),            -- BR-5.1
    photo_url           text,                                         -- BR-5.6
    rating              numeric(3,2),                                  -- BR-9.7
    status              product_status NOT NULL,
    description         text NOT NULL,
    CONSTRAINT product_price_check  CHECK (price >= 0),              -- BR-5.3
    CONSTRAINT product_rating_check CHECK (rating >= 0 AND rating <= 5) -- BR-5.4
);

-- Заказы
CREATE TABLE "order" (
    order_id           uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id         uuid NOT NULL REFERENCES courier (courier_id),
    client_id          uuid NOT NULL REFERENCES client (client_id),
    address_id         uuid NOT NULL REFERENCES address (address_id),
    restaurant_id      uuid NOT NULL REFERENCES restaurant (restaurant_id),
    order_timestamp    timestamp NOT NULL,
    delivery_timestamp timestamp,                                          -- BR-7.12
    order_amount       numeric(14,2) NOT NULL,
    commission         numeric(14,2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,                    -- BR-1.4
    total_amount       numeric(14,2) GENERATED ALWAYS AS (round(order_amount + round(order_amount * 0.10, 2), 2)) STORED, -- BR-7.10
    status             order_status     NOT NULL,
    pay_status         order_pay_status NOT NULL,
    description        text,
    CONSTRAINT order_client_address_fk FOREIGN KEY (client_id, address_id)
        REFERENCES client_address (client_id, address_id),                 -- BR-7.4
    CONSTRAINT order_amount_check    CHECK (order_amount > 0),             -- BR-1.8
    CONSTRAINT order_total_min_check CHECK (total_amount >= 1000),         -- BR-1.8
    CONSTRAINT order_delivery_check  CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp) -- BR-7.13
);

-- Попытки оплаты
CREATE TABLE payment (
    payment_id            uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id              uuid NOT NULL REFERENCES "order" (order_id),
    payment_type          payment_type NOT NULL,                            -- BR-8.6
    amount                numeric(14,2) NOT NULL,
    transaction_number    varchar(64) NOT NULL UNIQUE,                      -- BR-8.3
    transaction_timestamp timestamp NOT NULL,
    status                payment_status NOT NULL
);

-- Позиции заказа
CREATE TABLE order_structure (
    order_id   uuid NOT NULL REFERENCES "order" (order_id),
    product_id uuid NOT NULL REFERENCES product (product_id),
    quantity   numeric(10,2) NOT NULL,                                     -- BR-7.15
    PRIMARY KEY (order_id, product_id),                                    -- BR-7.16
    CONSTRAINT order_structure_quantity_check CHECK (quantity > 0)         -- BR-7.15
);

-- Отзывы
CREATE TABLE review (
    review_id        uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id        uuid NOT NULL REFERENCES client (client_id),
    review_timestamp timestamp NOT NULL,
    entity_id        uuid NOT NULL,
    entity_type      review_entity_type NOT NULL,                          -- BR-9.1
    order_id         uuid NOT NULL REFERENCES "order" (order_id),
    description      text NOT NULL,
    photo_url        text,                                                 -- BR-9.3
    rating           numeric(3,2) NOT NULL,
    CONSTRAINT review_rating_check     CHECK (rating >= 1 AND rating <= 5),      -- BR-9.4
    CONSTRAINT review_unique_per_order UNIQUE (order_id, entity_type, entity_id) -- BR-9.5
);

-- BR-7.3: все блюда заказа — из ресторана заказа (составным FK не выразить без денормализации)
CREATE FUNCTION check_order_structure_restaurant()
RETURNS trigger AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM "order" o
        JOIN product p ON p.product_id = NEW.product_id
        WHERE o.order_id = NEW.order_id
          AND p.restaurant_id <> o.restaurant_id
    ) THEN
        RAISE EXCEPTION 'Блюдо % принадлежит другому ресторану, чем заказ %',
            NEW.product_id, NEW.order_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_structure_restaurant
BEFORE INSERT OR UPDATE OF product_id, order_id ON order_structure
FOR EACH ROW EXECUTE FUNCTION check_order_structure_restaurant();
