-- V008: 4-шаговый zero-downtime RENAME COLUMN customers.name -> full_name

-- Шаг 1: добавить новую колонку
ALTER TABLE customers ADD COLUMN full_name TEXT;

-- Шаг 2: заполнить
UPDATE customers SET full_name = name;

-- Шаг 3: добавить NOT NULL
ALTER TABLE customers ALTER COLUMN full_name SET NOT NULL;

-- Шаг 4: переключить зависимое представление с name на full_name
-- (иначе DROP COLUMN name упадёт: представление orders_summary из лаб. 09
--  зависит от старой колонки)
CREATE OR REPLACE VIEW orders_summary AS
SELECT c.full_name AS customer_name,
       c.region,
       o.status,
       COUNT(*)            AS order_count,
       SUM(o.total_amount) AS total_revenue
FROM   customers c
JOIN   orders o ON o.customer_id = c.id
GROUP  BY c.full_name, c.region, o.status;

-- Шаг 5: убрать старую колонку (когда все клиенты перешли на full_name)
ALTER TABLE customers DROP COLUMN name;
