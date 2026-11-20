## Migration Plan: V004 — Баллы лояльности клиента

**Файл миграции:** V004__add_customer_loyalty_points.sql
**Автор:** Исобаева Д. А., группа ПИ 4-1
**Целевая среда / БД / схема:** учебный стенд (localhost:5432) / eshop / public
**Дата и окно деплоя:** 2026-11-05, 21:44 (+03). Окно обслуживания не требовалось
**Ответственный за запуск и решение об остановке:** Исобаева Д. А.
**Тип:** DDL (ADD COLUMN + COMMENT)

### Цель

Хранить накопленные баллы лояльности клиента в `customers.loyalty_points`.
Начисление и списание баллов, история операций и расчёт скидок в эту миграцию не входят —
только место для хранения значения.

### Предусловия

- [x] Подключение к `eshop`, схема `public`.
- [x] Baseline версии 1 зарегистрирован; V002 и V003 применены (`Success`).
- [x] Таблица `customers` существует (20 000 строк, 1 736 кБ на момент запуска).
- [x] Столбца `loyalty_points` в `customers` не было.
- [x] `flyway validate` проходит; `flyway info` показывал V004 как `Pending`.
- [x] Список ожидающих миграций проверен: ожидала только V004.
- [ ] Резервная копия непосредственно перед запуском **не снималась** (учебный стенд).
      Для production — `pg_dump -Fc eshop -f backup_pre_v004.dump` с проверкой восстановления.

### Изменения и риски

| Объект | Операция | Влияние и меры |
|---|---|---|
| `customers` | `ADD COLUMN loyalty_points INTEGER NOT NULL DEFAULT 0` | В PostgreSQL 11+ `DEFAULT` хранится в каталоге, таблица **не переписывается**; `NOT NULL` проверяется по тому же значению. Операция быстрая, но берёт `ACCESS EXCLUSIVE` на короткое время — нужен `lock_timeout`. |
| `customers` | `COMMENT ON COLUMN` | Только метаданные, блокировок на данные нет. |

- Существующие 20 000 строк получают `0` без физической перезаписи.
- **Допустимое время ожидания блокировки:** `SET lock_timeout = '5s'` (для production).
  На стенде не задавалось — конкурентных сеансов не было.
- **Допустимая длительность:** измерено **28 мс**. Порог — единицы секунд.
- `NOT NULL` добавлен намеренно: баллы не должны быть `NULL`, иначе `SUM(loyalty_points)` и
  сравнения потребуют `COALESCE`. Само по себе `DEFAULT 0` **не запрещает** `NULL` —
  это важно учитывать, если столбец добавляют без `NOT NULL`.
- При превышении лимитов или ошибке проверки: остановиться, вызвать ответственного.

### Проверка после деплоя

```sql
-- Ожидается одна строка: integer, значение по умолчанию 0.
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'customers'
  AND column_name = 'loyalty_points';

-- Дополнительно (в задании не требуется, но проверяет выбранный NOT NULL).
SELECT is_nullable FROM information_schema.columns
WHERE table_name = 'customers' AND column_name = 'loyalty_points';

-- Все существующие строки получили значение по умолчанию.
SELECT count(*) AS nonzero FROM public.customers WHERE loyalty_points <> 0;

-- Успешная запись именно для файла V004.
SELECT version, description, success
FROM public.flyway_schema_history
WHERE script = 'V004__add_customer_loyalty_points.sql';
```

**Фактические результаты (учебный запуск):**

| Проверка | Результат |
|---|---|
| `column_name, data_type, column_default` | `loyalty_points \| integer \| 0` |
| `is_nullable` | `NO` (в миграции указан `NOT NULL`) |
| `count(*) WHERE loyalty_points <> 0` | **0** |
| `flyway_schema_history` по `script` | `004 \| add customer loyalty points \| t` |
| `flyway info` | V004 — `Success` |

Время выполнения: 28 мс (на 20 000 строк, без перезаписи таблицы).

### Стратегия при сбое и откат

- **Ошибка SQL.** PostgreSQL откатит миграцию вместе с записью в истории: `info` снова покажет
  `Pending`, столбца не будет. Исправить файл (он ещё не применён — это разрешено) и повторить
  `migrate`. `repair` не требуется. Именно так и произошло при отладке — см. отчёт по лаб. 9.
- **Миграция применена, но обнаружен дефект.** Выпустить корректирующую V-миграцию
  (например, изменить тип или добавить ограничение), не редактируя применённый файл.
- **Откат `DROP COLUMN loyalty_points`** уничтожает накопленные баллы — перед откатом выгрузить
  значения (`COPY (SELECT id, loyalty_points FROM customers) TO 'loyalty_backup.csv' CSV HEADER;`)
  и согласовать с ответственным. Удаление столбца не отменяет запись V004 в истории Flyway.
- **Возврат из резервной копии** — восстановление базы вместе с `flyway_schema_history`,
  иначе история и схема разойдутся.

### MR-чек-лист

- [x] Имя файла корректно: `V004__add_customer_loyalty_points.sql`.
- [ ] Ревью вторым человеком — **не выполнялось** (учебная работа).
- [x] Миграция проверена на **отдельной БД** (`eshop_flyway_test`) с исходным состоянием
      и на основной БД `eshop`.
- [x] Учтены блокировки (`lock_timeout`), права и совместимость приложения
      (новый столбец со значением по умолчанию не ломает `INSERT` без списка столбцов,
      если он допускает `NULL`; при `NOT NULL DEFAULT` — тоже не ломает).
- [x] `cleanDisabled = true`; реальные пароли не попали в Git.
- [x] `flyway validate` прошёл; список ожидающих миграций проверен.
- [x] Заданы проверяемые критерии успеха и действия при сбое.
- [ ] Согласованы резервное копирование и восстановление — **частично**: ответственный указан,
      копия перед запуском не снималась.

---

## Приложение: прогон из самостоятельного задания 2 (отдельная БД)

Проверка поведения при синтаксической ошибке выполнена в отдельной базе, чтобы не трогать
рабочую схему `eshop`.

**Подготовка:**

```sql
CREATE DATABASE eshop_flyway_test;
-- минимальная схема, достаточная для V004
CREATE TABLE customers (id serial PRIMARY KEY, full_name text NOT NULL);
INSERT INTO customers (full_name) VALUES ('Тест 1'), ('Тест 2');
```

Проект: `eshop-migrations/test-task2/` (`flyway.toml` → `eshop_flyway_test`, каталог `migrations/`
содержит только V004). `baseline -baselineVersion=1 -baselineDescription=test_base`.

**1. Сломанная миграция** (`ALTERX TABLE ...`):

```text
Migrating schema "public" to version "004 - add customer loyalty points"
ERROR: Migration of schema "public" to version "004 - add customer loyalty points" failed! Changes successfully rolled back.
ERROR: Script V004__add_customer_loyalty_points.sql failed
```

Состояние после сбоя:

| Проверка | Результат |
|---|---|
| `flyway_schema_history` | только `1 \| test_base \| t` — **строки `success = false` нет** |
| столбец `loyalty_points` | отсутствует |
| `flyway info` | V004 — `Pending` |

**2. Исправление и повтор:**

```text
Migrating schema "public" to version "004 - add customer loyalty points"
Successfully applied 1 migration to schema "public", now at version v004 (execution time 00:00.021s)
```

| Проверка | Результат |
|---|---|
| `column_name, data_type, column_default` | `loyalty_points \| integer \| 0` |
| история | `004 \| V004__add_customer_loyalty_points.sql \| t` |
| данные | обе существующие строки получили `loyalty_points = 0` |

**Вывод.** На PostgreSQL при обычном транзакционном выполнении неудачная V-миграция откатывается
целиком: ни изменений схемы, ни записи `Failed` не остаётся. Поэтому после исправления файла
достаточно повторить `migrate`; `repair` нужен только если неуспешная запись в истории всё же
появилась (миграция выполнялась вне транзакции) — и только после разбора фактического состояния БД.
