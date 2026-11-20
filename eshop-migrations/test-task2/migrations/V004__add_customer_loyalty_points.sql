-- V004: баллы лояльности клиента (исправленная версия по заданию 2)
ALTER TABLE customers
ADD COLUMN loyalty_points INTEGER DEFAULT 0;
