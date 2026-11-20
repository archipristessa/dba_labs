# Лабораторная работа №9 — отчёт

**Студент:** Исобаева Дарья Александровна, группа ПИ 4-1
**Дата:** 2026-11-05
**Flyway:** OSS Edition 10.22.0 (Windows x86_64), PostgreSQL 18.6
**Каталог проекта:** `dba/eshop-migrations`
**Версия лабы:** обновлённая редакция (с разбором жизненного цикла миграции и новым шаблоном Migration Plan)

---

## Часть 1. Установка и настройка

### 1.1. Установка Flyway CLI

Скачан официальный архив с Maven Central (публичный, без регистрации):
`flyway-commandline-10.22.0.zip` (190 МБ).

> Лаба предупреждает, что архив может содержать вложенную папку с номером версии.
> Так и было: внутри `flyway-10.22.0/`. После распаковки каталог переименован, чтобы
> `flyway.cmd` лежал **непосредственно** в `C:\tools\flyway-10`:

```powershell
Expand-Archive flyway-commandline-10.22.0.zip -DestinationPath C:\tools
Rename-Item C:\tools\flyway-10.22.0 C:\tools\flyway-10
& 'C:\tools\flyway-10\flyway.cmd' --version
```

```text
Flyway OSS Edition 10.22.0 by Redgate
```

**`PATH` не изменялся**, поэтому CLI вызывается полным путём
`C:\tools\flyway-10\flyway.cmd`. Это осознанное решение: изменение переменных окружения
затрагивает систему за пределами лабораторной. Вариант A из лабы (только текущий пользователь,
**без прав администратора**) при необходимости включается одной командой:

```powershell
$flywayPath = 'C:\tools\flyway-10'
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
[Environment]::SetEnvironmentVariable('PATH', (@($userPath, $flywayPath) | Where-Object { $_ }) -join ';', 'User')
```

После этого в **новом** окне PowerShell работает `flyway --version`.

### 1.2. Структура проекта

```text
eshop-migrations/
├── flyway.toml
├── migration_plan_V003.md          # Migration Plan + Runbook (часть 4)
├── migration_plan_V004.md          # Migration Plan (самостоятельное задание 1)
├── test-task2/                     # отдельный проект для задания 2
│   ├── flyway.toml                 # → БД eshop_flyway_test
│   └── migrations/
│       └── V004__add_customer_loyalty_points.sql
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

> **Расхождение с текстом лабы.** В лабе (и в обновлённой редакции тоже) `locations` указан
> внутри `[environments.default]`. Flyway 10 этот параметр там **игнорирует** и ищет каталог
> `./sql`, выдавая `WARNING: No locations configured and default location 'sql' not found`.
> Проверено: `flyway info` показывал только baseline и не видел `V002`, хотя файл лежал в
> `migrations/`. После переноса `locations` в секцию `[flyway]` миграции находятся.
>
> Пароль в файле — только для локального стенда; в Git он не выкладывается
> (в публичном репозитории заменён на плейсхолдер). Штатный вариант — переменная окружения
> `FLYWAY_PASSWORD`, тогда строку `password` из конфига можно убрать.

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

Проверка `flyway info` после baseline: файл `V002` отображался как `Pending`, схема не менялась —
это подтверждает, что `baseline` только регистрирует начальную точку, а не выполняет SQL.

> **Важно (по обновлённой лабе).** `baseline` не проверяет соответствие существующей схемы
> версии 1 и **не делает резервную копию**. Одних V002–V008 недостаточно, чтобы развернуть базу
> с нуля: сначала нужна исходная схема (или восстановление из дампа).

### 2.2. V002 — категории товаров

```text
Successfully validated 2 migrations
Migrating schema "public" to version "002 - add products category"
Successfully applied 1 migration to schema "public", now at version v002   (execution time 00:00.151s)
```

Проверка результата:

```text
products_without_category = 0
Аксессуары  | 108
Периферия   | 413
Электроника | 479
```

### 2.3. V003 — промокоды

```text
Migrating schema "public" to version "003 - create promo codes"
Migrating schema "public" with repeatable migration "orders summary view"
Successfully applied 2 migrations to schema "public", now at version v003   (execution time 00:00.115s)
```

Применено **две** миграции, а не одна: `migrate` без `-target` выполняет всё ожидающее,
включая R-миграцию. Это ровно тот пункт плана деплоя, где нужно заранее смотреть список `Pending`.

| Проверка | Результат |
|---|---|
| `SELECT code, discount_pct, valid_until, is_active FROM promo_codes` | `SALE20 \| 20.00 \| 2024-10-01 \| t`, `WELCOME10 \| 10.00 \| 2025-12-31 \| t` |
| `orders.promo_code_id` | `integer`, `is_nullable = YES` |
| Внешний ключ | `orders_promo_code_id_fkey` → `promo_codes(id)` |
| `flyway_schema_history` по `script` | `003 \| create promo codes \| t` |
| Время выполнения V003 | **47 мс** (поле `execution_time`) |

---

## Часть 3. Специальные ситуации

### 3.1. Repeatable-миграция `R__orders_summary_view`

```text
Migrating schema "public" with repeatable migration "orders summary view"
```

Представление создано, `SELECT count(*) FROM orders_summary` → **44 464** строки.

Проверка правила «R-файл можно менять»: в лаб. 10 файл `R__orders_summary_view.sql` был изменён
(`c.name` → `c.full_name`), и при следующем `migrate` Flyway выполнил его повторно.
В `flyway info` старая запись получила статус **`Superseded`**, новая — `Success`.
Это подтверждает механизм: отслеживается контрольная сумма **файла**, а не состояние объектов в БД.

### 3.2. Validate: контроль checksum

| Действие | Результат |
|---|---|
| `flyway validate` (исходное состояние) | `Successfully validated 4 migrations` |
| в `V002__add_products_category.sql` добавлена строка-комментарий | `ERROR: Validate failed: Migrations have failed validation`<br>`Migration checksum mismatch for migration version 002` |
| файл восстановлен из копии | `Successfully validated 4 migrations` |

**Вывод:** применённые V-миграции редактировать нельзя. Если нужно изменить схему — новая
V-миграция; если файл изменили случайно — восстановить его из Git.

### 3.3. Repair

**Фактическое поведение PostgreSQL.** Сломанная миграция в основной БД (опечатка `ALTERTABLE`
в V004):

```text
ERROR: Migration of schema "public" to version "004 - add customer loyalty points" failed! Changes successfully rolled back.
Message : ERROR: syntax error at or near "ALTERTABLE"
```

Flyway выполнил миграцию в транзакции и **полностью откатил** её. Записи `success = false`
в `flyway_schema_history` **не осталось**, версия снова стала `Pending`. Это соответствует
обновлённой редакции лабы (раздел 4: «в истории может не быть строки `success = false`»)
и отличается от старого текста, где ожидался статус `Failed`.

Проверено отдельно: если неуспешная запись в истории всё же есть, `repair` её удаляет
и пересчитывает контрольные суммы. Для этого состояние «упавшей миграции» было воспроизведено
записью в историю — после `flyway repair` запись исчезла, а `migrate` применил V004 (`Success`).

**Вывод:** `repair` правит метаданные, а не схему, и **не является обязательным шагом** после
любой ошибки. Сначала нужно понять фактическое состояние объектов, и только потом решать,
нужен ли `repair`.

---

## Часть 4. Migration Plan и Runbook

В обновлённой лабе шаблон плана расширен. Оба документа переписаны под него:

| Файл | Что содержит |
|---|---|
| `eshop-migrations/migration_plan_V003.md` | Migration Plan V003 (по новому шаблону) + Runbook деплоя |
| `eshop-migrations/migration_plan_V004.md` | Migration Plan V004 + приложение с прогоном из задания 2 |

Структура плана V003 (как требует лаба): файл миграции, автор, целевая среда, окно деплоя,
ответственный → **Цель** → **Предусловия** → **Изменения и риски** (с влиянием и мерами) →
**Проверка после деплоя** (4 SQL-запроса с ожидаемыми и фактическими результатами) →
**Стратегия при сбое и откат** → **MR-чек-лист** (8 пунктов).

### Что в плане отмечено как невыполненное (честно)

Лаба требует не оставлять отметок о фактически не выполненных проверках, поэтому:

| Пункт | Статус |
|---|---|
| Резервная копия перед запуском | **не снималась**; доступен только дамп от 2026-09-24 (до лаб. 06) |
| Ревью вторым человеком | **не проводилось** (работа выполняется одним человеком) |
| Прогон V003 на отдельной БД | **не выполнялся** — V003 применялась сразу в `eshop` |
| Согласование backup/restore/ответственного | частично: ответственный указан |

При этом фактические данные для остальных разделов есть: время выполнения (47 мс для V003,
28 мс для V004), `lock_timeout = 5s` и `statement_timeout = 30s` как рекомендация для production
(на стенде не задавались — конкурентных сеансов не было).

### Runbook

Runbook (16 шагов: подготовка → выполнение → проверка → откат → уведомления) включён в
`migration_plan_V003.md`. Отличие от шаблона лабы: добавлены `lock_timeout`/`statement_timeout`
перед `migrate` и явное требование проверить список `Pending` (иначе `migrate` выполнит
не только V003 — что и произошло в учебном запуске).

---

## Самостоятельные задания

### 1. V004 — баллы лояльности + Migration Plan

```sql
-- V004__add_customer_loyalty_points.sql
ALTER TABLE customers ADD COLUMN loyalty_points INTEGER NOT NULL DEFAULT 0;
COMMENT ON COLUMN customers.loyalty_points IS 'Накопленные баллы лояльности';
```

Migration Plan оформлен отдельным файлом `migration_plan_V004.md` по тому же шаблону.

| Проверка | Результат |
|---|---|
| `column_name, data_type, column_default` | `loyalty_points \| integer \| 0` |
| `is_nullable` | `NO` |
| строк с `loyalty_points <> 0` | 0 |
| история | `004 \| add customer loyalty points \| t` |
| время выполнения | 28 мс на 20 000 строк |

> **Отклонение от краткого решения лабы.** В лабе предлагается `INTEGER DEFAULT 0`
> (столбец допускает `NULL`). Я добавила `NOT NULL DEFAULT 0`: баллы не должны быть `NULL`,
> иначе `SUM(loyalty_points)` и сравнения требуют `COALESCE`. Проверка из задания
> (`column_name, data_type, column_default`) проходит в обоих вариантах, а `is_nullable = NO`
> — более строгий результат. Замечание лабы «`DEFAULT` сам по себе не запрещает `NULL`»
> в плане отражено отдельным пунктом.

### 2. Синтаксическая ошибка в ещё не применённой V004 — в отдельной БД

Выполнено по обновлённой редакции: в **отдельной** базе, чтобы не трогать рабочую схему.

```sql
CREATE DATABASE eshop_flyway_test;
CREATE TABLE customers (id serial PRIMARY KEY, full_name text NOT NULL);
INSERT INTO customers (full_name) VALUES ('Тест 1'), ('Тест 2');
```

Проект `eshop-migrations/test-task2/` (свой `flyway.toml`, в `migrations/` только V004),
`baseline -baselineVersion=1 -baselineDescription=test_base`.

**Шаг 1. Сломанная миграция** (`ALTERX TABLE ...`):

```text
ERROR: Migration of schema "public" to version "004 - add customer loyalty points" failed! Changes successfully rolled back.
ERROR: Script V004__add_customer_loyalty_points.sql failed
```

| Проверка после сбоя | Результат |
|---|---|
| `flyway_schema_history` | только `1 \| test_base \| t` — **строки `success = false` нет** |
| столбец `loyalty_points` | отсутствует (`count(*) = 0` в `information_schema`) |
| `flyway info` | V004 — `Pending` |

**Шаг 2. Файл исправлен, повторный `migrate`:**

```text
Successfully applied 1 migration to schema "public", now at version v004 (execution time 00:00.021s)
```

| Проверка после исправления | Результат |
|---|---|
| `column_name, data_type, column_default` | `loyalty_points \| integer \| 0` |
| история | `004 \| V004__add_customer_loyalty_points.sql \| t` |
| данные | обе строки получили `loyalty_points = 0` |

**Вывод.** На PostgreSQL при обычном транзакционном выполнении неудачная V-миграция откатывается
целиком — и изменения схемы, и запись в истории. После исправления файла достаточно повторить
`migrate`; `repair` **не нужен**. Он понадобился бы, если бы миграция выполнялась вне транзакции
(например, `CREATE INDEX CONCURRENTLY`) и часть изменений осталась в БД.

### 3. Почему `V004_add_customer.sql` — ошибка

Проверено экспериментально: файл `V009_add_customer_note.sql` (одно подчёркивание) положен
в `migrations/`.

| Команда | Реакция Flyway |
|---|---|
| `flyway info` | `Set 'validateMigrationNaming' to true to fail fast and see a list of the invalid file names` |
| `flyway migrate` | `1 SQL migrations were detected but not run because they did not follow the filename convention` |
| колонка `note` в БД | **не создана** (`count(*) = 0`) |

**Причина:** формат имени — `V<версия>__<описание>.sql`, разделитель — **двойное** подчёркивание.
Flyway разбирает имя по этому шаблону: `V004_add_customer.sql` не даёт ни версии, ни описания,
поэтому файл считается невалидным и **молча пропускается** (по умолчанию он лишь предупреждает;
поведение зависит от настроек — в обновлённой лабе это указано как «может быть проигнорирован
или вызвать ошибку проверки имени»).

Последствия:

- миграция не применяется — схема на стенде и в production расходится (drift);
- ошибка не видна, если не включён `validateMigrationNaming = true`;
- версия `004` остаётся занятой другим файлом, порядок применения нарушается.

**Рекомендация:** включить `validateMigrationNaming = true` в `flyway.toml`, чтобы такой файл
останавливал пайплайн, а не игнорировался.

---

## Чек-лист

- [x] `flyway.toml` создан с `cleanDisabled = true`.
- [x] `flyway baseline` выполнен; `flyway_schema_history` содержит запись.
- [x] V002 и V003 применены; `flyway info` показывает Success для обоих.
- [x] `R__orders_summary_view` создан; view `orders_summary` существует.
- [x] `flyway validate` выявляет изменённый файл (checksum mismatch).
- [x] `migration_plan_V003.md` и runbook заполнены — по новому шаблону.
- [x] `migration_plan_V004.md` составлен (самостоятельное задание 1).
- [x] Задание 2 выполнено в отдельной БД `eshop_flyway_test`.
