-- V006: исправляем V005 — добавляем колонку и заполняем её безопасно
ALTER TABLE orders ADD COLUMN IF NOT EXISTS manager_id INTEGER;

-- 0 — служебное значение «менеджер не назначен»; в реальной схеме
-- здесь должен быть FK на таблицу managers.
UPDATE orders SET manager_id = 0 WHERE manager_id IS NULL;

ALTER TABLE orders ALTER COLUMN manager_id SET NOT NULL;
