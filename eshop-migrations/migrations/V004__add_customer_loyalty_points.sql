-- V004: баллы лояльности клиента
-- DEFAULT 0 — безопасно: колонка добавляется со значением по умолчанию,
-- существующие 20 000 строк не переписываются (оптимизация PG 11+).
ALTER TABLE customers ADD COLUMN loyalty_points INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN customers.loyalty_points IS 'Накопленные баллы лояльности';
