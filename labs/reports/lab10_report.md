# Лабораторная работа №10 — отчёт

**Студент:** Исобаева Дарья Александровна, группа ПИ 4-1
**Дата:** 2026-11-05
**Flyway:** 10.22.0, PostgreSQL 18.6

---

## Часть 1. Rollback: forward rollback

### 1.1. Симуляция плохой миграции V005

```sql
-- V005__bad_migration.sql
ALTER TABLE orders ADD COLUMN manager_id INTEGER NOT NULL;
```

```text
ERROR: Migration of schema "public" to version "005 - bad migration" failed! Changes successfully rolled back.
Message : ERROR: column "manager_id" of relation "orders" contains null values
```

| Проверка | Результат |
|---|---|
| `flyway info` | `005 ... Pending` (а **не** `Failed`) |
| Колонка `manager_id` в `orders` | отсутствует (`count(*) = 0`) |

> **Отклонение от лабы.** Лаба ожидает статус `Failed`. PostgreSQL поддерживает транзакционный DDL,
> поэтому Flyway выполнил файл в транзакции и **полностью откатил** её — записи о неудаче не осталось.
> На СУБД без транзакционного DDL (MySQL, Oracle) в истории осталась бы строка `success = false`.
> С точки зрения результата это эквивалентно: изменения не применились, `migrate` можно повторить.

### 1.2. Forward rollback

1. Неудачная миграция отозвана: `V005__bad_migration.sql` → `V005__bad_migration.sql.bak`
   (пока файл в каталоге, `migrate` снова пытается его выполнить).
2. Создана корректирующая миграция V006:

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS manager_id INTEGER;
UPDATE orders SET manager_id = 0 WHERE manager_id IS NULL;
ALTER TABLE orders ALTER COLUMN manager_id SET NOT NULL;
```

3. `flyway repair` → `Repair of failed migration ... not necessary. No failed migration detected.`
4. `flyway migrate` → `Successfully applied 1 migration ... now at version v006`

Итог: в истории **V005 отсутствует**, `V006` — `Success`, `manager_id = 0` у всех 200 000 строк.

### 1.3. Undo-скрипт (альтернатива)

Flyway Undo доступен только в Teams-редакции. Ручной откат неудачной V005:

```sql
ALTER TABLE orders DROP COLUMN IF EXISTS manager_id;
```

На момент проверки V006 уже применена, поэтому скрипт был бы **no-op** (колонка нужна).
Смысл приёма: если корректирующая миграция ещё не выпущена, ручной undo возвращает схему
в исходное состояние, после чего `flyway repair` убирает запись о неудаче.

---

## Часть 2. Zero-downtime паттерны

### 2.1. ADD NOT NULL — 3 шага (V007)

```sql
ALTER TABLE orders ADD COLUMN confirmed_at TIMESTAMPTZ DEFAULT now();
UPDATE orders SET confirmed_at = created_at WHERE confirmed_at IS NULL;
ALTER TABLE orders ALTER COLUMN confirmed_at SET NOT NULL;
ALTER TABLE orders ALTER COLUMN confirmed_at DROP DEFAULT;
```

```text
Successfully applied 1 migration ... now at version v007   (execution time 00:00.080s)
```

| Проверка | Результат |
|---|---|
| `is_nullable` | `NO` |
| `column_default` | пусто (DEFAULT снят) |
| строк с `confirmed_at IS NULL` | 0 |
| `confirmed_at = created_at` | **0 строк** |
| `count(DISTINCT confirmed_at)` | **1** (`2026-11-05 21:46:12.537989+03`) |

> **Важное наблюдение.** `now()` — стабильная функция, поэтому PostgreSQL применил оптимизацию
> PG 11+: значение DEFAULT записано в каталог и подставлено существующим строкам **без перезаписи
> таблицы** (0,08 с на 200 000 строк). Побочный эффект: все старые строки получили **одну и ту же**
> метку — момент миграции, а шаг 2 (`UPDATE ... WHERE confirmed_at IS NULL`) не изменил ни одной строки.
>
> **Как правильно, если нужно заполнить историческим значением:**
> ```sql
> ALTER TABLE orders ADD COLUMN confirmed_at TIMESTAMPTZ;             -- без DEFAULT
> UPDATE orders SET confirmed_at = created_at WHERE confirmed_at IS NULL;  -- батчами в production
> ALTER TABLE orders ALTER COLUMN confirmed_at SET NOT NULL;
> ALTER TABLE orders ALTER COLUMN confirmed_at SET DEFAULT now();     -- DEFAULT уже после заполнения
> ```

### 2.2. RENAME COLUMN — 4 шага (V008)

`customers.name` → `customers.full_name`. Перед работой проверены зависимости — от колонки зависело
только представление `orders_summary`:

```sql
ALTER TABLE customers ADD COLUMN full_name TEXT;
UPDATE customers SET full_name = name;
ALTER TABLE customers ALTER COLUMN full_name SET NOT NULL;
CREATE OR REPLACE VIEW orders_summary AS
SELECT c.full_name AS customer_name, c.region, o.status,
       COUNT(*) AS order_count, SUM(o.total_amount) AS total_revenue
FROM   customers c JOIN orders o ON o.customer_id = c.id
GROUP  BY c.full_name, c.region, o.status;
ALTER TABLE customers DROP COLUMN name;
```

```text
Successfully applied 1 migration ... now at version v008   (execution time 00:00.770s)
```

| Проверка | Результат |
|---|---|
| Колонки `customers` | `id, email, phone, region, created_at, phone_encrypted, loyalty_points, full_name` |
| `name` | отсутствует |
| `orders_summary` | работает, **44 464** строки |

Файл `R__orders_summary_view.sql` обновлён на `c.full_name`. При следующем `migrate` Flyway
перезапустил его (checksum изменился), прежняя запись получила статус **Superseded**.
Без этого обновления повторный запуск R__ упал бы на отсутствующей колонке `name`.

### 2.3. CREATE INDEX CONCURRENTLY

```text
CREATE INDEX CONCURRENTLY idx_orders_total_amount ON orders(total_amount DESC);
-- заняло < 1 с, запись в таблицу не блокировалась
```

| Проверка | Результат |
|---|---|
| `indisvalid` | **true** |
| Размер | 4 408 кБ |

### 2.4. Сводная таблица паттернов

| Операция | Опасный способ | Zero-downtime способ | Почему |
|---|---|---|---|
| ADD NOT NULL column | один `ALTER TABLE ... ADD ... NOT NULL` | ADD + UPDATE + SET NOT NULL (3 шага) | на PG ≤ 10 добавление с NOT NULL/DEFAULT переписывает таблицу под `ACCESS EXCLUSIVE` |
| RENAME COLUMN | `ALTER TABLE ... RENAME COLUMN` | ADD + FILL + NOT NULL + DROP (2 релиза) | старый и новый код приложения работают одновременно |
| CREATE INDEX | `CREATE INDEX` | `CREATE INDEX CONCURRENTLY` | обычный `CREATE INDEX` держит `SHARE`, запись ждёт |
| DROP TABLE | `DROP TABLE` | RENAME → убрать FK → DROP (3 релиза) | даёт окно для отката |
| ALTER COLUMN TYPE | `ALTER COLUMN TYPE` | ADD + migrate + DROP (контролируемая пауза) | переписывает таблицу |

---

## Часть 3. Обслуживание и итоговое состояние

### 3.1. VACUUM FULL + REINDEX

Перед `VACUUM FULL` остановлен PgBouncer: его простаивающие серверные соединения держали бы
таблицу под `ACCESS EXCLUSIVE` (проверено — соединений к `eshop` осталось 0).

```text
vacuumdb --full --analyze --verbose   -> код возврата 0
reindexdb --concurrently --verbose    -> код возврата 0
```

| Показатель | До | После |
|---|---|---|
| Размер БД `eshop` | **158 МБ** | **119 МБ** |

Освобождено 39 МБ: `VACUUM FULL` переписал раздутые таблицы (`orders`, `order_items`, `customers`)
и вернул место операционной системе — обычный `VACUUM` этого не делает.

### 3.2. Статус миграций

Файл: `labs/work/final_flyway_status.txt`

| Category | Version | Description | State |
|---|---|---|---|
| | 1 | initial_eshop_schema | Baseline |
| Versioned | 002 | add products category | Success |
| Versioned | 003 | create promo codes | Success |
| Repeatable | | orders summary view | Superseded |
| Versioned | 004 | add customer loyalty points | Success |
| Versioned | 006 | fix manager id | Success |
| Versioned | 007 | add confirmed at safe | Success |
| Versioned | 008 | rename customer name | Success |
| Repeatable | | orders summary view | Success |

Записей `Failed` нет, V005 отсутствует (отозвана).

### 3.3. Итоговый слепок схемы

```powershell
pg_dump -h localhost -U postgres --schema-only eshop -f eshop_final_schema.sql
```

Файл `labs/work/eshop_final_schema.sql` (19 701 байт) — актуальная DDL-схема без данных.

---

## Часть 4. Итоговая защита проекта

Отчёт: [`eshop_project_report.md`](eshop_project_report.md) — 9 разделов по структуре лабы
(описание БД и ERD, ролевая модель, резервное копирование, мониторинг, производительность,
ИБ, миграции, zero-downtime, выводы).

---

## Чек-лист

- [x] V006–V008 (исправление, ADD NOT NULL, RENAME COLUMN) — Success; V005 отозвана.
- [x] `idx_orders_total_amount` создан `CONCURRENTLY`; `indisvalid = true`.
- [x] `vacuumdb --full` выполнен; `reindexdb --concurrently` выполнен.
- [x] `flyway info` — все актуальные миграции Success, failed-записей нет.
- [x] `eshop_project_report.md` — все разделы заполнены.
