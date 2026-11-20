-- V007: 3-шаговый zero-downtime ADD NOT NULL
-- Шаг 1: добавить колонку с DEFAULT (быстро, без перезаписи всех строк)
ALTER TABLE orders ADD COLUMN confirmed_at TIMESTAMPTZ DEFAULT now();

-- Шаг 2: заполнить существующие строки (в production — батчами)
UPDATE orders SET confirmed_at = created_at WHERE confirmed_at IS NULL;

-- Шаг 3: добавить ограничение NOT NULL (быстро, т.к. данные уже заполнены)
ALTER TABLE orders ALTER COLUMN confirmed_at SET NOT NULL;
ALTER TABLE orders ALTER COLUMN confirmed_at DROP DEFAULT;
