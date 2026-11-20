-- R__orders_summary_view: сводное представление заказов (пересоздаётся при изменении)
-- Обновлено в V008: customers.name переименована в full_name.

CREATE OR REPLACE VIEW orders_summary AS
SELECT c.full_name AS customer_name,
       c.region,
       o.status,
       COUNT(*)        AS order_count,
       SUM(o.total_amount) AS total_revenue
FROM   customers c
JOIN   orders o ON o.customer_id = c.id
GROUP  BY c.full_name, c.region, o.status;
