-- V002: добавить категории товаров

CREATE TABLE categories (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

INSERT INTO categories (name) VALUES
    ('Электроника'),
    ('Периферия'),
    ('Аксессуары');

ALTER TABLE products ADD COLUMN category_id INTEGER REFERENCES categories(id);

-- Категория по цене: работает и для 3 товаров из лаб. 02,
-- и для 1000 товаров после перенаполнения в лаб. 06.
-- Так миграция не зависит от конкретных названий товаров.
UPDATE products SET category_id = CASE
    WHEN price >= 5000 THEN 1   -- Электроника
    WHEN price >= 1000 THEN 2   -- Периферия
    ELSE 3                       -- Аксессуары
END
WHERE category_id IS NULL;

COMMENT ON TABLE categories IS 'Категории товаров';
