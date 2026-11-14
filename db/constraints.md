# Обоснование ограничений

Схема: `shiryaev_food`. Источник истины — `docs/company-rules.md` (`BR-N.M`).

---

## Enum-типы

| Тип | Значения | BR |
|---|---|---|
| `restaurant_status` | `активен`, `неактивен` | BR-4.3 |
| `product_status` | `доступно`, `нет_в_наличии`, `архив` | BR-5.5 |
| `courier_status` | `свободен`, `занят`, `на_доставке`, `уволен` | BR-6.2 |
| `order_status` | `создан`, `готовится`, `в_доставке`, `доставлен`, `отменён` | BR-7.7 |
| `order_pay_status` | `ожидает`, `оплачен`, `ошибка` | BR-7.9 |
| `payment_status` | `успех`, `ошибка`, `в_обработке` | BR-8.2 |
| `payment_type` | `карта`, `наличные`, `безнал` | BR-8.2 |
| `review_entity_type` | `блюдо`, `ресторан`, `заказ` | BR-9.1 |

Значения взяты из BR дословно, ничего не добавлено и не изменено.

---

## Ловушки

### Ловушка 1: `payment` — неполная сущность

**Какие атрибуты добавил в `payment` и почему (BR-8.2):**

Добавил в `payment` все атрибуты попытки оплаты из BR-8.2:
- `payment_type` (enum `payment_type`) — тип оплаты;
- `amount` (numeric) — сумма попытки;
- `transaction_number` (varchar) — внешний идентификатор финансовой транзакции;
- `transaction_timestamp` (timestamp) — дата и время транзакции;
- `status` (enum `payment_status`) — статус попытки.

В ERD у `payment` был только `payment_id` и `order_id`; без этих полей BR-8 негде хранить.

**Где хранится тип оплаты — `payment` или `order` (BR-8.6):**

В `payment`. BR-8.6 прямо говорит: «тип оплаты относится к попытке оплаты, а не к заказу. У заказа может быть несколько попыток с разными типами». Если бы тип лежал в `order`, несколько попыток с разными типами было бы невозможно описать.

### Ловушка 2: `order.address_id` — принадлежность клиенту (BR-7.4)

**Как обеспечено, что адрес доставки принадлежит клиенту:**

Составным внешним ключом на таблице `order`:

```
CONSTRAINT order_client_address_fk
FOREIGN KEY (client_id, address_id)
REFERENCES client_address (client_id, address_id)
```

`client_address` — это таблица M:N «у клиента много адресов, адрес — у разных клиентов». Составной FK гарантирует, что пара `(client_id, address_id)` заказа реально существует как «адрес этого клиента». Это декларативное решение, без триггера.

Дополнительно оставлен обычный FK `order.address_id -> address` (связь из ERD «ADDRESS ||--o{ ORDER»): заказ доставляется по одному адресу.

### Ловушка 3: `order_structure` — один ресторан в заказе (BR-7.3)

**Как обеспечено, что все блюда из `order.restaurant_id`:**

Триггером `trg_order_structure_restaurant` (функция `check_order_structure_restaurant()`) на `BEFORE INSERT OR UPDATE OF product_id, order_id`. Триггер проверяет, что `product.restaurant_id` вставляемого блюда совпадает с `order.restaurant_id` заказа; при несовпадении бросает ошибку.

Почему не составной FK: чтобы связать `order_structure` с рестораном заказа, пришлось бы добавить `restaurant_id` в `order_structure` — это денормализация (значение выводится и из `order_id`, и из `product_id`). Триггер проще и не нарушает 3НФ.

Допущение: `order.restaurant_id` после создания заказа не меняется (нет процедуры, которая его меняет), поэтому триггер только на `order_structure`.

### Ловушка 4: `review` — полиморфизм (BR-9.1)

**Как реализована валидность `review.entity_id`:**

Полиморфизм: `entity_type` (enum `review_entity_type`) + `entity_id` (uuid). Обычный FK на `entity_id` поставить нельзя, потому что он указывает на одну из трёх разных таблиц (`product`, `restaurant`, `"order"`) в зависимости от `entity_type`.

Поэтому:
- целостность `entity_id` на уровне БД гарантируется только генерацией (в `insert_test_data` `entity_id` всегда берётся из реально существующей сущности);
- связь отзыва с заказом зафиксирована обычным FK `review.order_id -> "order"` (BR-9.2);
- запрет дублей отзывов — `UNIQUE (order_id, entity_type, entity_id)` (BR-9.5).

---

## CHECK-ограничения

| Таблица | Столбец | Условие | BR | Обоснование |
|---|---|---|---|---|
| `restaurant` | `rating` | `>= 0 AND <= 5` | BR-4.2 | задаёт диапазон рейтинга ресторана |
| `restaurant` | `work_end`, `work_start` | `work_end > work_start` | BR-4.4 | время закрытия позже времени открытия |
| `courier` | `coefficient` | `BETWEEN 0.1 AND 0.5` | BR-6.4 | диапазон коэффициента курьера |
| `courier` | `dismissal_date`, `hire_date` | `dismissal_date IS NULL OR >= hire_date` | BR-6.3 | дата увольнения не раньше найма |
| `product` | `price` | `>= 0` | BR-5.3 | цена блюда неотрицательна |
| `product` | `rating` | `>= 0 AND <= 5` | BR-5.4 | диапазон рейтинга блюда |
| `order` | `order_amount` | `> 0` | BR-1.8, BR-7.10 | сумма без комиссии (стоимость блюд) положительна |
| `order` | `total_amount` | `>= 1000` | BR-1.8, BR-7.11 | минимальная сумма заказа |
| `order` | `delivery_timestamp`, `order_timestamp` | `delivery_timestamp IS NULL OR >= order_timestamp` | BR-7.13 | доставка не раньше создания |
| `order_structure` | `quantity` | `> 0` | BR-7.15 | количество положительное |
| `courier_pay` | `amount` | `>= 0` | BR-10.4 | зарплата неотрицательна |
| `courier_pay` | `month` | `BETWEEN 1 AND 12` | BR-11.6 | техническое: месяц в допустимом диапазоне |
| `courier_pay` | `coefficient_used` | `BETWEEN 0.1 AND 0.5` | BR-10.2, BR-6.4 | применяемый коэффициент берётся из допустимого диапазона |
| `review` | `rating` | `>= 1 AND <= 5` | BR-9.4 | рейтинг отзыва от 1 до 5 |

---

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.2 | логин уникален |
| `client` | `phone_number` | BR-2.2 | телефон уникален |
| `restaurant` | `address_id` | BR-3.3 | два ресторана не могут делить один адрес |
| `payment` | `transaction_number` | BR-8.3 | идентификатор транзакции уникален |
| `review` | `(order_id, entity_type, entity_id)` | BR-9.5 | не более одного отзыва на объект в рамках заказа |
| `client_address` | `(client_id, address_id)` — PK | BR-2.5 | один адрес нельзя привязать к клиенту дважды |
| `order_structure` | `(order_id, product_id)` — PK | BR-7.16 | одно блюдо не встречается в заказе дважды |
| `courier_pay` | `(year, month, courier_id)` — PK | BR-10.3 | ровно одна выплата за месяц на курьера |

---

## FK-ограничения

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| `client_address` | `client_id` | `client` | BR-2.4 | адрес принадлежит клиенту |
| `client_address` | `address_id` | `address` | BR-2.4 | связь указывает на реальный адрес |
| `restaurant` | `address_id` | `address` | BR-3.3, BR-3.4 | у ресторана ровно один адрес |
| `product` | `product_category_id` | `product_category` | BR-5.1 | блюдо принадлежит категории |
| `product` | `restaurant_id` | `restaurant` | BR-5.1 | блюдо принадлежит ресторану |
| `courier_pay` | `courier_id` | `courier` | BR-10.2 | выплата относится к курьеру |
| `order` | `courier_id` | `courier` | BR-7.5 | доставку выполняет курьер |
| `order` | `client_id` | `client` | BR-7.2 | заказ оформляет клиент |
| `order` | `address_id` | `address` | BR-7.4 | заказ доставляется по адресу |
| `order` | `restaurant_id` | `restaurant` | BR-7.2 | заказ привязан к ресторану |
| `order` | `(client_id, address_id)` | `client_address` | BR-7.4 | адрес доставки — один из адресов клиента |
| `payment` | `order_id` | `order` | BR-8.1 | попытка оплаты относится к заказу |
| `order_structure` | `order_id` | `order` | BR-7.14 | позиция относится к заказу |
| `order_structure` | `product_id` | `product` | BR-7.14 | позиция — это блюдо |
| `review` | `client_id` | `client` | BR-9.2 | отзыв оставляет клиент |
| `review` | `order_id` | `order` | BR-9.2 | отзыв связан с конкретным заказом |

Итого 16 FK (в `acceptance.md` требуется «не менее 15»).

---

## NOT NULL (только бизнес-обязательные)

Очевидные случаи (PK, FK на NOT NULL-поле, поля с явным «есть» в BR) не дублирую. Здесь — то, что могло бы показаться необязательным, но по BR обязательно:

| Таблица | Столбец | BR | Обоснование |
|---|---|---|---|
| `restaurant` | `description` | BR-4.1 | «у ресторана есть … описание» — перечислено в обязательных атрибутах |
| `restaurant` | `inn` | BR-4.5 | реквизиты — обязательный атрибут ресторана (ИНН) |
| `restaurant` | `ogrn` | BR-4.5 | реквизиты — обязательный атрибут ресторана (ОГРН) |
| `restaurant` | `settlement_account` | BR-4.5 | реквизиты — обязательный атрибут ресторана (расчётный счёт) |
| `product` | `description` | BR-5.2 | «у блюда есть … описание» |
| `review` | `description` | BR-9.3 | «у отзыва есть текст …» |
| `payment` | `payment_type`, `amount`, `transaction_number`, `transaction_timestamp`, `status` | BR-8.2 | каждая попытка оплаты имеет все эти атрибуты |

---

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| `address` | `apartment_office` | BR-3.2 | бывают частные дома без квартиры/офиса |
| `courier` | `dismissal_date` | BR-6.3 | работающий курьер не имеет даты увольнения |
| `order` | `delivery_timestamp` | BR-7.12 | заполняется только при статусе `доставлен` |
| `product` | `photo_url` | BR-5.6 | фотография блюда необязательна |
| `review` | `photo_url` | BR-9.3 | фотография отзыва необязательна |
| `restaurant` | `rating` | BR-9.7 | нет отзывов → рейтинг NULL |
| `product` | `rating` | BR-9.7 | нет отзывов → рейтинг NULL |
| `order` | `description` | ERD | в BR не описано; оставлено из ERD как необязательный комментарий |

---

## DEFAULT и GENERATED

| Таблица | Столбец | Что | Обоснование |
|---|---|---|---|
| все таблицы | `*_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1: все ID — UUID, генерируются на сервере |
| `courier` | `coefficient` | `DEFAULT 0.1` | BR-6.5: изначальный коэффициент нового курьера — 0.1 |
| `order` | `commission` | `NOT NULL GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED` | BR-1.4 |
| `order` | `total_amount` | `NOT NULL GENERATED ALWAYS AS (round(order_amount + round(order_amount * 0.10, 2), 2)) STORED` | BR-7.10: сумма без комиссии + комиссия |

Почему `commission` и `total_amount` сделаны `GENERATED ALWAYS AS`, а не обычными полями с CHECK:
- вычисляемые значения не должны расходиться с `order_amount` — БД считает их сама;
- в PostgreSQL сгенерированная колонка не может ссылаться на другую сгенерированную, поэтому `total_amount` записан как `round(order_amount + round(order_amount * 0.10, 2), 2)` — это в точности `round(order_amount + commission, 2)`, как требует BR-7.10 и проверка в `tests.md`.

---

## Нормализация (3НФ)

- **1НФ.** Составные атрибуты разбиты на атомарные: `courier.last_name/first_name/middle_name` (вместо ФИО одним полем) и `restaurant.inn/ogrn/settlement_account` (вместо реквизитов одной строкой).

Все таблицы в 3НФ: каждый неключевой атрибут зависит от полного первичного ключа (2НФ), транзитивных зависимостей нет (3НФ).

Особые случаи:

- **`order.commission` и `order.total_amount`** — вычисляемые поля (`GENERATED ALWAYS AS`). Они не хранятся как независимые данные, а выводятся из `order_amount`, поэтому не создают транзитивной зависимости и не нарушают 3НФ.
- **`product.rating` и `restaurant.rating`** — агрегаты по отзывам. Это осознанная денормализация для скорости чтения (BR-9.6 требует автоматический пересчёт). Поддерживаются триггером `rating_change` (FOOD-105), а не хранятся вручную.
- **`review.entity_id` + `entity_type`** — полиморфизм (см. Ловушку 4). Не нарушает 3НФ, но требует отдельного обоснования (приведено выше).
- **`order.description`** — поле из ERD, не покрыто ни одним BR; оставлено как необязательный комментарий (NULL-able), на 3НФ не влияет.

---

## Генератор тестовых данных (FOOD-102/103)

**Генерация строк (паттерны `samples/all_examples.sql`, раздел 2).** Все символьные значения генерируются по паттерну 2a — `substring(repeat(substring(алфавит, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int), 1, N)` — и имеют длину от 1 до `N` символов, где `N` — размер `varchar(N)`. Пустых строк не бывает: `1 + floor(...)` никогда не даёт 0 (ловушка `ceil(random() * N)` обойдена). Длинные значения (`inn`, `ogrn`, `settlement_account`, `transaction_number`, `login`) генерируются по паттерну 2b — `substring(md5(random()::text), 1, 1 + floor(random() * N)::int)`. Фотографии — по паттерну 2d: `'https://cdn.foodexpress.ru/img/' || md5(random()) || '.jpg'`, в ~50% случаев `NULL` (BR-5.6, BR-9.3).

**Уникальность при повторных вызовах (проверка C.9).** `insert_test_data` **добавляет** строки. Уникальные поля защищены счётчиками-смещениями от текущего количества строк: `login` = md5-префикс + `lpad(client_count + i, 5, '0')`; телефоны клиентов/курьеров — номер из счётчика; `transaction_number` — md5 + номер. Новые рестораны получают только что созданные адреса. `courier_pay` пересчитывается через `ON CONFLICT (year, month, courier_id) DO UPDATE`, дублей не появляется.

**Связность.** `client_address` — у клиента 1..3 разных адреса (индексная формула, без повторов, BR-2.5). `order_structure` — 1..5 разных блюд одного ресторана (выбранное блюдо удаляется из массива, BR-7.3 и BR-7.16). Заказ берёт адрес только из `client_address` своего клиента (BR-7.4).

**Один платёж на заказ.** Проверка C.3 (tests.md) требует ровно `value * 5` строк в `payment` — столько же, сколько заказов. Поэтому на каждый заказ создаётся одна попытка со статусом `'успех'` и суммой `order.total_amount` (BR-8.1, BR-8.4), а `order.pay_status` = `'оплачен'` (BR-8.7 при единственной успешной попытке).

**Один отзыв на заказ.** Проверка C.3 требует ровно `value * 5` строк в `review`; по одному отзыву на заказ соблюдается `UNIQUE (order_id, entity_type, entity_id)` (BR-9.5). Тип отзыва выбирается через `enum_range()`: для `блюдо` — блюдо из позиций этого заказа, для `ресторан` — ресторан заказа, для `заказ` — сам заказ (BR-9.1, BR-9.2). `client_id` отзыва = `client_id` заказа (BR-9.2).

**Рейтинги (BR-9.6, BR-9.7).** После вставки отзывов `product.rating` и `restaurant.rating` пересчитываются прямым `UPDATE ... SET rating = round(avg(...), 2)` по отзывам. Триггер `rating_change` не вызывается — генератор не зависит от бизнес-логики (раздел 10 samples). У сущностей без отзывов рейтинг остаётся `NULL`.

**История выплат `courier_pay` (BR-10.2, BR-10.7).** Через `generate_series` по 6 месяцам × всем курьерам: `amount = коэффициент × сумма комиссий доставленных заказов курьера за месяц` (`coalesce(..., 0)` — у курьера без доставок 0, ловушка 13). В тестовых данных доставок меньше 151, поэтому по правилу BR-10.2 `coefficient_used` = 0.1. После генерации `courier.coefficient` = коэффициент на следующий месяц по BR-10.2; уволенным не назначается (BR-10.6).

**Прочие гарантии.** Enum — через `enum_range()` (индекс 1..N, ловушка 0 обойдена); пароли — `md5(random()::text)` (BR-2.3); все ID — `exts.uuid_generate_v4()` (BR-11.1); `work_end` = `work_start` + 8..13 часов (BR-4.4); `dismissal_date` ≥ `hire_date` и ≤ сегодня (BR-6.3); минимальная сумма заказа достигается увеличением количества первого блюда (BR-1.8); ≥ 20% курьеров уволены, остальные активны, поэтому хотя бы один активный курьер есть всегда (BR-6.6). Процедура не вызывает другие функции/процедуры схемы.
