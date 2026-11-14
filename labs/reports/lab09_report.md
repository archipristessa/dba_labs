# Лабораторная работа №9 — отчёт

**Студент:** Исобаева Дарья Александровна, группа ПИ 4-1
**Дата:** 2026-11-05
**Flyway:** OSS Edition 10.22.0 (Windows x86_64), PostgreSQL 18.6
**Каталог проекта:** `dba/eshop-migrations`

---

## Часть 1. Установка и настройка

### 1.1. Установка Flyway CLI

Скачан: `flyway-commandline-10.22.0.zip` (190 МБ) → распакован в **`C:\tools\flyway-10`**.

```text
Flyway OSS Edition 10.22.0 by Redgate
```

### 1.2. Структура проекта

```text
eshop-migrations/
├── flyway.toml
├── migration_plan_V003.md
├── migration_plan_V004.md
└── migrations/
    ├── V002__add_products_category.sql
    ├── V003__create_promo_codes.sql
    ├── V004__add_customer_loyalty_points.sql
    ├── V006__fix_manager_id.sql
    ├── V007__add_confirmed_at_safe.sql
    ├── V008__rename_customer_name.sql
    ├── V005__bad_migration.sql.bak
    └── R__orders_summary_view.sql
```

Файла `V001` нет: существующая схема зафиксирована командой `baseline -baselineVersion=1`.

### 1.3. flyway.toml

```toml
[environments.default]
url       = "jdbc:postgresql://localhost:5432/eshop"
user      = "postgres"
password  = "<пароль роли postgres>"

[flyway]
locations         = ["filesystem:./migrations"]
cleanDisabled     = true
validateOnMigrate = true
outOfOrder        = false
```

---

## Часть 2. Baseline и миграции

### 2.1. Baseline

```text
Creating Schema History table "public"."flyway_schema_history" with baseline ...
Successfully baselined schema with version: 1
```

| installed_rank | version | description | type | success |
|---|---|---|---|---|
| 1 | 1 | initial_eshop_schema | BASELINE | t |

### 2.2. V002 — категории товаров

```text
Successfully validated 2 migrations
Migrating schema "public" to version "002 - add products category"
Successfully applied 1 migration to schema "public", now at version v002
```

Проверка:

```text
products_without_category = 0
Аксессуары  | 108
Периферия   | 413
Электроника | 479
```

### 2.3. V003 — промокоды

| Проверка | Результат |
|---|---|
| `SELECT count(*) FROM promo_codes` | **2** |
| `orders.promo_code_id` существует | да |
| `flyway_schema_history` V003 | **Success** |

---

## Часть 3. Специальные ситуации

### 3.1. Repeatable-миграция `R__orders_summary_view`

```text
Migrating schema "public" with repeatable migration "orders summary view"
Successfully applied 2 migrations to schema "public", now at version v003
```

Представление создано, `SELECT count(*) FROM orders_summary` → **44 464** строки.

После изменения файла `R__` Flyway при следующем `migrate` выполнил её повторно, а старая запись получила статус **Superseded** —
это и есть механизм repeatable-миграций.

### 3.2. Validate: контроль checksum

| Действие | Результат |
|---|---|
| `flyway validate` (исходное состояние) | `Successfully validated 4 migrations` |
| в `V002__add_products_category.sql` добавлена строка-комментарий | `ERROR: Validate failed: Migrations have failed validation`<br>`Migration checksum mismatch for migration version 002` |
| файл восстановлен | `Successfully validated 4 migrations` |

**Вывод:** применённые миграции редактировать нельзя — Flyway хранит контрольную сумму.

### 3.3. Repair

**Фактическое поведение PostgreSQL.** Сломанная миграция (опечатка `ALTERTABLE` в V004):

```text
ERROR: Migration of schema "public" to version "004 - add customer loyalty points" failed! Changes successfully rolled back.
Message : ERROR: syntax error at or near "ALTERTABLE"
```

Flyway выполнил миграцию в транзакции и **полностью откатил** её. Записи `success = false`
в `flyway_schema_history` **не осталось** — версия снова стала `Pending`.

Чтобы всё же показать механизм `repair`, состояние «упавшей миграции» было воспроизведено
записью в историю:

```sql
INSERT INTO flyway_schema_history (installed_rank, version, description, type, script,
                                   checksum, installed_by, execution_time, success)
VALUES (5, '004', 'add customer loyalty points', 'SQL',
        'V004__add_customer_loyalty_points.sql', 0, 'postgres', 0, false);
```

| Шаг | Результат |
|---|---|
| `flyway info` | `004 ... Failed` |
| `flyway repair` | `Successfully repaired schema history table` (запись удалена) |
| `flyway migrate` | `Successfully applied 1 migration ... now at version v004` |
| `flyway info` | `004 ... Success` |

**Что делает `repair`:** удаляет записи о неудачных миграциях и пересчитывает checksums.
Он **не откатывает** уже выполненные SQL и **не исправляет** данные — файл миграции должен быть
исправлен вручную (в нашем случае — опечатка в `ALTER TABLE`).

---

## Часть 4. Migration Plan и Runbook

- [`migration_plan_V003.md`](../eshop-migrations/migration_plan_V003.md) — Migration Plan и Runbook деплоя V003.
- [`migration_plan_V004.md`](../eshop-migrations/migration_plan_V004.md) — Migration Plan V004 (самостоятельное задание).

Оба документа содержат: изменения и риски, скрипт отката, SQL проверки после деплоя, MR-чек-лист
(для V003 — ещё и Runbook из 14 шагов: подготовка → выполнение → проверка → откат → уведомления).

---

## Самостоятельные задания

### 1. V004 — баллы лояльности

```sql
-- V004__add_customer_loyalty_points.sql
ALTER TABLE customers ADD COLUMN loyalty_points INTEGER NOT NULL DEFAULT 0;
COMMENT ON COLUMN customers.loyalty_points IS 'Накопленные баллы лояльности';
```

Проверка: `column_default = 0`, `is_nullable = NO`, ни одной строки с `loyalty_points <> 0`.
Migration Plan оформлен отдельным файлом `migration_plan_V004.md`.

`ADD COLUMN ... NOT NULL DEFAULT 0` безопасен: в PG 11+ значение по умолчанию хранится в каталоге и
таблица не переписывается (на PG 10 это была бы блокирующая операция на 20 000 строк).

### 2. «Сломанная» V004 → `repair`

Выполнено, см. п. 3.3. Ключевой результат: **на PostgreSQL запись `success = false` не появляется** —
Flyway откатывает транзакцию. После исправления файла `migrate` применил V004 успешно.
Дополнительно механизм `repair` показан на восстановленной «проваленной» записи.

### 3. Почему `V004_add_customer.sql` — ошибка

Проверено экспериментально: файл `V009_add_customer_note.sql` (одно подчёркивание) положен в `migrations/`.

| Команда | Реакция Flyway |
|---|---|
| `flyway info` | `Set 'validateMigrationNaming' to true to fail fast and see a list of the invalid file names` |
| `flyway migrate` | `1 SQL migrations were detected but not run because they did not follow the filename convention` |
| колонка `note` в БД | **не создана** (`count(*) = 0`) |

**Причина:** формат имени — `V<версия>__<описание>.sql`, разделитель **двойное** подчёркивание.
Flyway разбирает имя по этому шаблону: `V004_add_customer.sql` не даёт ни версии, ни описания,
поэтому файл считается невалидным и **молча пропускается** (по умолчанию он лишь предупреждает).
Последствия:

- миграция не применяется — схема на стенде и в production расходится (drift);
- ошибка не видна, если не включён `validateMigrationNaming = true`;
- версия `004` остаётся «занятой» другим файлом, и порядок применения нарушается.

Рекомендация: включить `validateMigrationNaming = true` в `flyway.toml`, чтобы такие файлы
останавливали пайплайн, а не игнорировались.
