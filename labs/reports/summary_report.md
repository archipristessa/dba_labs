# Отчёт о выполненных лабораторных работах

**Студент:** Исобаева Дарья Александровна
**Группа:** ПИ 4-1
**Дата:** 2026-11-05
**Стенд:** Windows, PostgreSQL 18.6 (localhost:5432), база `eshop`

---

## Что сделано по работам

### Лабораторная №5 — Мониторинг, блокировки, журналирование

Отчёт: [`db_health_report.md`](db_health_report.md)

- Смоделирована блокировка: сессия в `idle in transaction` (pid 4064) держала строку `orders.id = 1`,
  вторая сессия (pid 12152) ждала с `wait_event_type = Lock`, `wait_event = transactionid`.
- `pg_cancel_backend(4064)` вернул `t`, но блокировка **осталась** (отменять нечего — запроса нет);
  снялась только `pg_terminate_backend(4064)`.
- Мёртвые строки: 10 циклов `UPDATE` по `products` дали 60 мёртвых версий (`dead_pct 95,2 %`).
  `VACUUM ANALYZE` обнулил `n_dead_tup`, размер не изменился (8192 → 8192 байт), `VACUUM FULL` — тот же размер.
- Cache hit ratio 98,33 %, медленный запрос (`pg_sleep(0.7)`, 712 мс) найден в журнале;
  `log_lock_waits = on` дал строку `process 4816 still waiting for ShareLock ... after 1002.919 ms`.

### Лабораторная №6 — Анализ запросов: pg_stat_statements, EXPLAIN, pgBadger

Отчёт: [`lab06_report.md`](lab06_report.md)

- Загружены данные: 20 000 / 1 000 / 200 000 / 600 000 строк (16,6 с), характеристики совпали с эталоном
  (1 007 клиентов MSK, 8 124 заказа за 30 дней).
- Топ запросов по `pg_stat_statements`: Q1 — 172,85 мс, Q3 — 143,14 мс, Q2 — 98,61 мс;
  все три читают таблицы целиком (2 008 / 5 045 / 1 791 страница за вызов).
- Индексы из п. 2.4: план запроса с двумя JOIN ускорился **128,2 → 19,3 мс (×6,7)**,
  `Parallel Hash Join` + `Parallel Seq Scan` сменились на `Nested Loop` + `Index Scan`.
- Проблемный запрос (Q1): `HashAggregate` с `Batches: 5` и записью 656 кБ на диск.
  После агрегации до JOIN — **170,9 → 98,6 мс (−42 %)**. Увеличение `work_mem` само по себе не помогло (173,5 мс).
- pgBadger 13.3: 6 нормализованных запросов, 12 выполнений, самый медленный — 964 мс (`pg_sleep`).
- Самостоятельные: `Batches: 8` при `work_mem = 64 кБ` (467 мс против 105 мс); FK-триггер
  `order_items_order_id_fkey` — **0,703 мс с индексом против 25,620 мс без него (×36)**.

### Лабораторная №7 — Индексы, autovacuum, PgBouncer

Отчёт: [`lab07_report.md`](lab07_report.md), обоснование: [`pgbouncer_justification.md`](pgbouncer_justification.md)

- Статусы перераспределены, числа совпали с эталоном (delivered 170 033 … pending 3 922).
- Полный индекс по `status`: 1 400 кБ, запрос 42,3 → 6,3 мс. Частичный — **88 кБ (в 16 раз меньше)**, 5,4 мс.
- Составной `(status, created_at)`: `BitmapAnd` 1,89 мс → `Index Scan` 0,76 мс.
- `CREATE INDEX CONCURRENTLY` на `order_items(product_id)`: 158 → 2,3 мс, страниц 5 000 → 572, `indisvalid = true`.
- Индекс по выражению `LOWER(email)`: 5,32 → 0,09 мс; запрос по `email` с заглавными буквами индексом не пользуется (0 строк).
- Autovacuum: дефолтный порог 40 050 не срабатывал на 1 000 мёртвых строк; после
  `scale_factor = 0.01` (порог 2 050) — сработал, `autovacuum_count` 1 → 2, `n_dead_tup` → 0.
- PgBouncer 1.26.1 (transaction mode): 50 клиентов обслуживают **10** backend-процессов вместо **60**,
  tps 3 232 против 4 348, задержка 15,5 против 11,5 мс. Ограничения подтверждены: `SET` утекает
  к другому клиенту (PID 11912, `work_mem = 64MB`), SQL `PREPARE` не работает
  (`prepared statement "q" does not exist`).

### Лабораторная №8 — Информационная безопасность

Отчёт: [`lab08_report.md`](lab08_report.md), чек-лист: [`ib_checklist.md`](ib_checklist.md)

- **TLS:** `ssl = on`, самоподписанный `CN=localhost`, соединение `TLSv1.3 / TLS_AES_256_GCM_SHA384`;
  в `pg_hba.conf` — `hostssl` + `hostnossl ... reject` для `app_backend`:
  `sslmode=require` подключается, `sslmode=disable` получает отказ `no encryption`.
- **pgcrypto:** 20 000 телефонов зашифрованы (`pgp_sym_encrypt`), расшифровка совпала в 20 000 из 20 000,
  неверный ключ → `Wrong key or corrupt data`; аналитик видит 1 007 строк (RLS), `phone = '***'`,
  зашифрованные байты не читаются.
- **pgAudit:** единственный незакрытый пункт. Расширения нет в поставке PostgreSQL 18 для Windows,
  бинарников на GitHub нет (только исходники), MSVC в системе отсутствует, а в каталоге
  EDB Stack Builder 4.2.2 для PG 18 пакета `pgAudit` **нет** — установка на этом стенде невозможна.
  Варианты: офлайн-пакет от преподавателя или сборка MSVC 19.44 (инструкция в отчёте).
  Временная замена (`log_statement = 'all'`) проверена — `SELECT` аналитика попадает в журнал.

### Лабораторная №9 — Flyway: миграции схемы

Отчёт: [`lab09_report.md`](lab09_report.md), проект: `dba/eshop-migrations/`

- Flyway 10.22.0 установлен в `C:\tools\flyway-10`, создан `flyway.toml` с `cleanDisabled = true`.
- `baseline -baselineVersion=1` → в истории запись `initial_eshop_schema`.
- V002 (категории: 479 / 413 / 108 товаров, 0 без категории) и V003 (2 промокода) — Success.
- `R__orders_summary_view` создан, представление на 44 464 строки; после правки файла Flyway
  применил его повторно, старая запись стала `Superseded`.
- `flyway validate` поймал `checksum mismatch` после правки V002; файл восстановлен.
- Найдено расхождение с текстом лабы: `locations` в `[environments.default]` Flyway 10 игнорирует —
  перенесено в `[flyway]`.
- Самостоятельные: V004 (баллы лояльности) + Migration Plan по новому шаблону; «сломанная» V004
  прогнана в **отдельной БД** `eshop_flyway_test`: PostgreSQL откатил миграцию целиком
  (записи `success = false` нет, статус снова `Pending`), после исправления файла `migrate`
  применил её за 0,021 с; имя файла с одним подчёркиванием молча пропускается
  (`1 SQL migrations were detected but not run because they did not follow the filename convention`).
- Оба Migration Plan (`migration_plan_V003.md`, `migration_plan_V004.md`) переписаны под новый шаблон:
  цель, предусловия, влияние и риски, проверки с фактическими результатами, стратегия при сбое,
  MR-чек-лист; невыполненные проверки (backup, ревью) помечены как невыполненные.

### Лабораторная №10 — Rollback, zero-downtime, итоговая защита

Отчёт: [`lab10_report.md`](lab10_report.md), итоговый отчёт: [`eshop_project_report.md`](eshop_project_report.md)

- V005 (`ADD COLUMN manager_id INTEGER NOT NULL`) упала с `contains null values`, изменения откатаны;
  миграция отозвана, исправление выпущено как V006 — `manager_id = 0` у 200 000 строк.
- V007 (ADD NOT NULL в 3 шага): 0,08 с на 200 000 строк. Наблюдение: `DEFAULT now()` — стабильная
  функция, поэтому все старые строки получили одну метку, а шаг `UPDATE` стал no-op (в отчёте дан
  правильный вариант).
- V008 (`name` → `full_name`, 4 шага): `orders_summary` переключено, R__ обновлён, `name` удалена.
- `CREATE INDEX CONCURRENTLY idx_orders_total_amount` — 4 408 кБ, `indisvalid = true`.
- `vacuumdb --full --analyze` + `reindexdb --concurrently`: размер БД **158 → 119 МБ**.
- `flyway info` — все миграции Success, failed-записей нет; `pg_dump --schema-only` → `eshop_final_schema.sql`.

---

## Артефакты

| Файл | Что это |
|---|---|
| `labs/reports/db_health_report.md` | отчёт лаб. 5 |
| `labs/reports/lab06_report.md` | отчёт лаб. 6 |
| `labs/reports/lab07_report.md` | отчёт лаб. 7 |
| `labs/reports/pgbouncer_justification.md` | обоснование PgBouncer (лаб. 7, ч. 4) |
| `labs/reports/lab08_report.md` | отчёт лаб. 8 |
| `labs/reports/ib_checklist.md` | ИБ-чек-лист (лаб. 8, ч. 4) |
| `labs/reports/lab09_report.md` | отчёт лаб. 9 |
| `labs/reports/lab10_report.md` | отчёт лаб. 10 |
| `labs/reports/eshop_project_report.md` | итоговый отчёт по проекту + подготовка к защите |
| `dba/eshop-migrations/` | Flyway-проект: `flyway.toml`, 7 миграций, 2 Migration Plan |
| `labs/work/final_flyway_status.txt` | вывод `flyway info` (лаб. 10, п. 3.2) |
| `labs/work/eshop_final_schema.sql` | слепок схемы `pg_dump --schema-only` (лаб. 10, п. 3.3) |
| `labs/work/eshop_report.txt` | отчёт pgBadger (лаб. 6, ч. 3) |

---

## Изменения в окружении и их возврат

### Что изменялось

| Объект | Изменение | Состояние сейчас |
|---|---|---|
| `postgresql.conf` | параметры журналирования (лаб. 5/6), `ssl = on` (лаб. 8), `shared_preload_libraries` (лаб. 6) | **возвращён в исходный вид** |
| `pg_hba.conf` | правила `hostssl`/`hostnossl` для `app_backend` (лаб. 8) | **возвращён в исходный вид** |
| `postgresql.auto.conf` | `log_min_duration_statement`, `log_statement` через `ALTER SYSTEM` | **сброшено** (`ALTER SYSTEM RESET`) |
| Служба `postgresql-x64-18` | два перезапуска (применение `ssl` и `shared_preload_libraries`) | **работает**, состояние `Running` |
| `data/server.crt`, `data/server.key` | созданы для TLS (лаб. 8) | **удалены** |
| `C:\pgbouncer` + процесс PgBouncer | установлен и запущен (лаб. 7) | **остановлен**, файлы оставлены |
| `C:\pgbadger` | pgBadger 13.3 (лаб. 6) | оставлен |
| `C:\tools\flyway-10` | Flyway CLI 10.22.0 (лаб. 9) | оставлен |
| `PATH` | **не изменялся** — CLI вызывались по полному пути | — |

### Проверка восстановления

```text
ssl                        = off
shared_preload_libraries   = ''            (в файле; в текущем процессе библиотека
                                            остаётся загруженной до следующего перезапуска)
log_min_duration_statement = -1
log_lock_waits             = off
lc_messages                = Russian_Russia.1251
log_line_prefix            = '%t '
TLS на новом соединении    = f
```

> Осталось одно «косметическое» отличие: библиотека `pg_stat_statements` продолжает быть
> загруженной в уже работающий процесс. На данные и на конфигурацию это не влияет;
> исчезнет при следующем перезапуске службы или компьютера. Если нужно сразу:
> `Restart-Service postgresql-x64-18` в PowerShell от имени администратора.

### Что осталось в базе (результаты лабораторных)

Данные и объекты схемы **не удалялись** — это результат работ:
20 000 / 200 000 / 600 000 / 1 000 строк, таблицы `categories`, `promo_codes`, `flyway_schema_history`,
представление `orders_summary`, 10 индексов из лаб. 6–10, колонки `loyalty_points`, `confirmed_at`,
`manager_id`, `phone_encrypted`, `full_name`, расширения `pg_stat_statements` и `pgcrypto`.

### Как вернуть «лабораторное» состояние конфигов

Копии сохранены в `labs/work/`:

```powershell
# конфигурация PostgreSQL с настройками всех лаб
Copy-Item "labs\work\postgresql.conf.lab_state" "C:\Program Files\PostgreSQL\18\data\postgresql.conf"
# правила pg_hba для принудительного TLS (лаб. 8)
Copy-Item "labs\work\pg_hba.conf.tls_state"    "C:\Program Files\PostgreSQL\18\data\pg_hba.conf"   # если нужно
Restart-Service postgresql-x64-18
```

Для TLS понадобится заново создать сертификат:

```bash
cd "/c/Program Files/PostgreSQL/18/data"
openssl req -new -x509 -days 365 -nodes -out server.crt -keyout server.key -subj '/CN=localhost'
```

---

## Итоги

| Лаба | Статус | Незакрытые пункты |
|---|---|---|
| 5 | ✅ выполнена | — |
| 6 | ✅ выполнена | — |
| 7 | ✅ выполнена | — |
| 8 | ⚠️ выполнена частично | `pgaudit` (нужен EDB Stack Builder, GUI) |
| 9 | ✅ выполнена | — |
| 10 | ✅ выполнена | — |

**Единственный заблокированный пункт** — установка `pgaudit` (лаб. 8, ч. 1). Расширения нет
ни в поставке PostgreSQL 18 для Windows, ни в каталоге EDB Stack Builder 4.2.2 для PG 18
(проверено в мастере), ни в виде бинарной сборки на GitHub; собрать из исходников нечем —
в системе нет MSVC. Нужен офлайн-пакет `pgaudit.dll` под PG 18 x64 (или машина с Visual Studio 2022).
Всё остальное в лаб. 8 (TLS, pgcrypto, RLS, чек-лист) выполнено и проверено.

**Найденные расхождения в текстах лабораторных** (описаны в соответствующих отчётах):

1. Лаб. 5: `\sleep` — не команда `psql`; для состояния `idle in transaction` нужен открытый stdin.
2. Лаб. 6: схема из лаб. 02 не содержала PK/identity/FK у `order_items` — скрипт наполнения не работал.
3. Лаб. 6: индекс по `status` при 20 % строк **используется** (Bitmap Heap Scan), а не игнорируется.
4. Лаб. 9: `locations` в `[environments.default]` Flyway 10 игнорирует — нужна секция `[flyway]`.
5. Лаб. 9/10: на PostgreSQL неудачная миграция откатывается целиком, статус `Failed` в истории
   не появляется (в обновлённой редакции лаб. 9 это уже описано верно); `repair` нужен для СУБД
   без транзакционного DDL или для записей, уже попавших в историю.
6. Лаб. 10: 3-шаговый `ADD NOT NULL` с `DEFAULT now()` не заполняет строки из `created_at` —
   все получают одну метку; правильный порядок — ADD без DEFAULT → UPDATE → SET NOT NULL → SET DEFAULT.
