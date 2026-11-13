# Лабораторная работа №7 — отчёт

**Студент:** Исобаева Дарья Александровна, группа ПИ 4-1
**Дата:** 05.11.2026
**Среда:** PostgreSQL 18.6, PgBouncer 1.26.1, Windows x86_64

## Часть 1. Индексы

### 1.1. Запрос без индекса

| Метрика | Значение |
|---|---|
| Тип узла | `Parallel Seq Scan on orders` (`Workers Launched: 2`) |
| Execution Time | **42,296 мс** |
| Buffers: shared hit | **3 640** |
| `Rows Removed by Filter` | 65 359 **на процесс** (`loops=3`) → всего 65 359 × 3 ≈ **196 077** |

Прочитана вся таблица (3 640 страниц) ради 3 922 строк (2 %).

### 1.2. Обычный B-tree индекс

```sql
CREATE INDEX idx_orders_status ON orders(status);
```

| Метрика | Значение |
|---|---|
| Тип узла | `Bitmap Heap Scan` → `Bitmap Index Scan on idx_orders_status` |
| Execution Time | **6,293 мс** (ускорение **×6,7**) |
| Buffers | `hit=1639 read=6`, `Heap Blocks: exact=1639` |
| Размер индекса | **1 400 кБ** |

Планировщик выбрал bitmap-вариант, а не `Index Scan`: нужны 3 922 строки на 1 639 разных страницах,
и bitmap-скан открывает каждую страницу один раз.

### 1.3. Частичный индекс

После `DROP INDEX idx_orders_status`:

```sql
CREATE INDEX idx_orders_active ON orders(status) WHERE status IN ('pending','processing');
```

| Индекс | Размер | Отношение |
|---|---|---|
| полный `idx_orders_status` | 1 400 кБ | — |
| частичный `idx_orders_active` | **88 кБ** | **в 15,9 раз меньше** |

| Запрос | План | Execution Time |
|---|---|---|
| `status = 'pending'` | `Bitmap Heap Scan` → `Bitmap Index Scan on idx_orders_active` | **5,382 мс** |
| `status = 'delivered'` | `Seq Scan` (`Rows Removed by Filter: 29 967`) | 25,914 мс |

Частичный индекс так же ускоряет «активный» запрос, занимая в 16 раз меньше места; для `delivered`
(85 % строк) он неприменим — и полный индекс там тоже бесполезен.

### 1.4. Составной индекс: порядок столбцов

| Вариант | Узел и индекс | Buffers (hit + read) | Execution Time, мс |
|---|---|---|---|
| Шаг 1: одностолбцовые индексы | `BitmapAnd` (`idx_orders_active` 3 922 строки + `idx_orders_created_at` 7 854 строки) → `Bitmap Heap Scan` | 188 | **1,893** |
| Шаг 3: `(status, created_at)` | `Index Scan using idx_orders_status_created`, `Index Cond` по обоим условиям | 143 + 4 = **147** | **0,762** |

**Правило:** сначала столбцы с равенством, потом с диапазоном. В индексе `(status, created_at)`
записи `pending` за 30 дней лежат подряд — читаются только 143 нужные строки. В обратном порядке
`(created_at, status)` пришлось бы просматривать все 7 854 заказа за 30 дней и отбрасывать статусы.

### 1.5. CREATE INDEX CONCURRENTLY

| Метрика | Без индекса | С индексом `idx_order_items_product` |
|---|---|---|
| Тип узла | `Parallel Seq Scan` | `Bitmap Heap Scan` |
| Buffers (hit + read) | 4 350 + 650 = **5 000** | 529 + 43 = **572** (в 8,7 раза меньше) |
| Execution Time | **157,921 мс** | **2,288 мс** (×69) |
| `Rows Removed by Filter` | 199 801 × 3 | — |

Построение `CONCURRENTLY` заняло 0,57 с и не блокировало запись. Проверка:
`indisvalid = true`, `indisready = true`.

### 1.6. Функциональный индекс

| Шаг | Узел и индекс | Строк найдено | Execution Time |
|---|---|---|---|
| 1. `LOWER(email) = ...` без индекса по выражению | `Seq Scan on customers` (`Rows Removed by Filter: 19 999`) | 1 | 5,320 мс |
| 3. с `idx_customers_email_lower` | `Index Scan using idx_customers_email_lower` | 1 | **0,093 мс** |
| 4. `email = 'C42@Example.com'` | `Index Scan using customers_email_key` | **0** | 0,138 мс |

Шаг 4 находит 0 строк: в базе хранится `c42@example.com`, а сравнение идёт с заглавными буквами.
Индекс по `LOWER(email)` этому запросу не подходит — выражение в запросе должно точно совпадать
с выражением в индексе.

### 1.7. Неиспользуемые индексы

| Таблица | Индекс | Размер | idx_scan |
|---|---|---|---|
| order_items | `idx_order_items_order` | 9 640 кБ | **0** |

Индекс создан в лаб. 06 и с момента последнего перезапуска сервера (статистика обнуляется)
не использовался ни одним запросом. **Удалять его не следует**: он нужен для FK-проверок при
удалении заказов (в лаб. 06 измерено: триггер 0,703 мс с индексом против 25,620 мс без него)
и для соединения `orders` ⨝ `order_items`. `idx_scan = 0` здесь означает «пока не было подходящих
запросов», а не «индекс не нужен».

---

## Часть 2. Autovacuum

### 2.1. Порог по умолчанию

| Момент | n_dead_tup | autovacuum_count |
|---|---|---|
| До обновлений | 0 | 1 |
| После 1 000 обновлений (`id % 200 = 0`) | **1 000** | **1** (не изменился) |

`threshold_default = 50 + 0,2 × 200 000 = **40 050**` — порог не достигнут, autovacuum не запускался.

### 2.2. Настройка для orders

```sql
ALTER TABLE orders SET (
    autovacuum_vacuum_scale_factor  = 0.01,
    autovacuum_analyze_scale_factor = 0.005
);
```

| Момент | n_dead_tup | autovacuum_count | Комментарий |
|---|---|---|---|
| После 1 000 обновлений (порог 20 % ≈ 40 050) | 1 000 | 1 | autovacuum не запускался |
| После ещё 4 000 обновлений (`id % 50 = 0`) | **0** | **2** | сработал новый порог **2 050** |

Прогресс autovacuum пойман через `pg_stat_progress_vacuum` (дополнительные 10 000 мёртвых строк):

```text
pid  | relid | phase           | heap_blks_scanned | heap_blks_total
-----+-------+-----------------+-------------------+----------------
1940 | orders| scanning heap   | 3350              | 3640
1940 | orders| vacuuming heap  | 3640              | 3640
```

### 2.3. Ручной VACUUM ANALYZE

```text
INFO:  vacuuming "eshop.public.orders"
INFO:  launched 2 parallel vacuum workers for index cleanup (planned: 2)
INFO:  finished vacuuming "eshop.public.orders": index scans: 0
INFO:  "orders": scanned 3640 of 3640 pages, containing 200000 live rows and 0 dead rows
```

`vacuumdb --analyze` завершился с кодом 0.

---

## Часть 3. PgBouncer

### 3.1–3.3. Установка и настройка

Установлен официальный релиз **PgBouncer 1.26.1 (Windows x86_64)** в `C:\pgbouncer`,
конфигурация — `pgbouncer.ini` из лабы (`pool_mode = transaction`, `default_pool_size = 10`,
`reserve_pool_size = 5`, `max_client_conn = 200`, `max_prepared_statements = 200`,
`ignore_startup_parameters = extra_float_digits`).
`userlist.txt` записан в кодировке ASCII без BOM, содержит SCRAM-хэш `app_backend` и `pgbouncer_admin`.

Запуск — вариант Б (фоновый процесс, без регистрации службы): `Start-Process pgbouncer.exe`.

### 3.5. Подключение и административная консоль

| Проверка | Результат |
|---|---|
| `SELECT count(*) FROM orders` через `:6432` | **200 000** |
| `SHOW POOLS` для `eshop`/`app_backend` | `cl_active = 1`, `sv_idle = 2`, `pool_mode = transaction` |

### 3.6. Нагрузочный тест: 50 клиентов → 10 соединений

| Подключение | Клиентов | Backend-процессов PostgreSQL | tps | latency average, мс |
|---|---|---|---|---|
| Через PgBouncer :6432 | 50 | **10** | 3 232,43 | 15,468 |
| Напрямую :5432 | 50 | **60** | 4 348,14 | 11,499 |

Во время теста через PgBouncer: `cl_active = 14`, `cl_waiting = 37`, `sv_active = 10`.
Через PgBouncer backend-процессов **10 ≤ 15** (проверка чек-листа выполнена).

> «60» напрямую — это 50 процессов `pgbench` плюс 10 простаивающих соединений, оставшихся
> в пуле PgBouncer от предыдущего опыта, а не 50: без пула было бы ровно 50.

### 3.7. Ограничения transaction mode

**Эксперимент 1. `SET` переходит к другому клиенту**

| Клиент | Действие | PID | work_mem |
|---|---|---|---|
| 1 | `SET work_mem='64MB'` | 11912 | 64MB |
| 2 | `SHOW work_mem` | **11912** (то же соединение) | **64MB** |

Настройка клиента 1 досталась клиенту 2: `SET` изменил параметр серверного соединения,
а соединение вернулось в пул.

**Эксперимент 2. SQL-команда `PREPARE`**

```text
клиент 1: PREPARE q(int) AS SELECT id, status FROM orders WHERE id = $1;   -> PREPARE
клиент 2: BEGIN;  (занимает соединение)
клиент 1: EXECUTE q(1);   -> ERROR: prepared statement "q" does not exist
```

Ошибка воспроизведена с первой попытки. Причина: `PREPARE` действует на серверное соединение,
а `EXECUTE` ушёл на другое.

---

## Часть 4. Обоснование архитектурного изменения

Документ: [`pgbouncer_justification.md`](pgbouncer_justification.md) — заполнен измеренными числами
(60 → 10 backend-процессов, 4,4 МБ приватной памяти на процесс, 264 МБ → 55 МБ).

---

## Самостоятельные задания

### 1. Функциональный индекс на products

```sql
CREATE INDEX idx_products_name_lower ON products(LOWER(name));
```

| Режим | План | Execution Time |
|---|---|---|
| `SET enable_seqscan = off` | `Index Scan using idx_products_name_lower`, `Index Cond: lower(name) = 'товар 42'` | **0,096 мс** |
| обычный режим | тот же `Index Scan` | 0,062 мс |

Индекс используется даже без `enable_seqscan = off`: после `ANALYZE` планировщик оценивает
результат в 1 строку, а таблица занимает всего 10 страниц — индекс дешевле.
Обычный индекс по `name` здесь не помог бы: в нём лежат исходные значения `'Товар 42'`,
а запрос ищет результат `LOWER(name) = 'товар 42'`.

### 2. Режим `session`

| Эксперимент | `transaction` | `session` |
|---|---|---|
| 1. `SET work_mem` | клиент 2 видит `64MB` | клиент 2 видит **`4MB`** |
| 2. `PREPARE` + `EXECUTE` в одном клиентском сеансе | может упасть | **работает** (`PREPARE`, затем `id \| status`) |
| 2. `PREPARE` в одном сеансе, `EXECUTE` в другом | падает | падает (`q2 does not exist`) |
| backend-процессов при 50 клиентах | 10 | **15** |
| `cl_waiting` | 37 | **35** |
| tps | 3 232,43 | **4 758,46** |
| latency average, мс | 15,468 | **10,508** |

**Почему в session mode `SET` не переходит к другому клиенту:** соединение закреплено за клиентом
на весь сеанс и при отключении проходит `server_reset_query` (`DISCARD ALL`), который сбрасывает
сессионные параметры. По той же причине `PREPARE` не переживает смену клиента, хотя внутри одного
сеанса работает.

**Почему tps в session mode выше:** нет накладных расходов на выдачу/возврат соединения на каждую
транзакцию, и в пуле было задействовано 15 соединений вместо 10. Но одновременно обслуживаются
только 15 клиентов из 50 — для веб-приложения с короткими транзакциями это неприемлемо.

### 3. Сравнение режимов пула

| Режим | Когда соединение возвращается в пул | Что работает | Что не работает | Типичное применение |
|---|---|---|---|---|
| **session** | при отключении клиента (закрытии сеанса) | всё, включая `SET`, `PREPARE`, `LISTEN/NOTIFY`, advisory-блокировки, временные таблицы | масштабирование: соединение занято всё время жизни клиента | legacy-приложения, ORM с курсорами, долгие сеансы, отладка |
| **transaction** | сразу после `COMMIT`/`ROLLBACK` | большинство OLTP-запросов, protocol-level prepared statements при `max_prepared_statements > 0` | SQL `PREPARE/EXECUTE`, `SET` (переходит к другим), `LISTEN/NOTIFY`, сессионные advisory-блокировки, временные таблицы вне транзакции | веб-приложения и микросервисы с короткими транзакциями (наш выбор) |
| **statement** | после каждого запроса | только одиночные запросы без транзакций | многооператорные транзакции (каждый `BEGIN...COMMIT` может попасть на разные соединения), всё из transaction mode | простые stateless-сервисы, пулы только для чтения |

---

## Чек-лист

- [x] Статусы перераспределены, числа совпали с эталоном, `VACUUM ANALYZE orders` выполнен.
- [x] `idx_orders_active` создан; размер сравнён с полным (88 кБ против 1 400 кБ); `EXPLAIN` показывает `Bitmap Index Scan`.
- [x] `idx_orders_status_created` создан; планы до/после сравнены по Buffers; правило порядка столбцов объяснено.
- [x] `idx_order_items_product` создан через `CONCURRENTLY`, `indisvalid = true`; планы сравнены.
- [x] Показано, что `idx_customers_email_lower` используется только для `LOWER(email) = ...`.
- [x] `autovacuum_vacuum_scale_factor = 0.01` выставлен; рост `autovacuum_count` 1 → 2 показан.
- [x] PgBouncer запущен на 6432; `SELECT count(*)` через 6432 работает.
- [x] `SHOW POOLS` показывает пул `eshop` с `cl_active > 0`.
- [x] Таблица 3.6 заполнена; backend-процессов через PgBouncer ≤ 15 (10).
- [x] `pgbouncer_justification.md` создан с измеренными числами.
