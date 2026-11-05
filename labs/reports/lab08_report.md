# Лабораторная работа №8 — отчёт

**Студент:** Исобаева Дарья Александровна, группа ПИ 4-1
**Дата:** 2026-11-05
**СУБД:** PostgreSQL 18.6 (Windows x86_64)

---

## Часть 1. pgAudit — **заблокировано**

### 1.1. Что сделано

| Шаг | Результат |
|---|---|
| Проверка `share/extension/pgaudit.control` | **отсутствует** |
| Проверка `lib/pgaudit.dll` | **отсутствует** |
| Поиск готового пакета на диске | не найден |
| Попытка скачать бинарник с GitHub (`api.github.com/repos/pgaudit/pgaudit/releases`) | релиз `pgAudit 18.0` есть, но **только исходники**, бинарных assets нет |
| Сборка из исходников | невозможна: в системе нет MSVC (`cl.exe`, `nmake.exe`, `msbuild.exe` не найдены), а `pgaudit.dll` должен быть собран тем же MSVC 19.44, что и PostgreSQL |
| Запуск `stackbuilder.exe` | требует прав администратора (UAC); мастер — GUI, автоматизации не поддаётся |
| **Каталог Stack Builder 4.2.2 для PG 18** | **пакета `pgAudit` в списке нет** — проверено в мастере вручную (шаг «Add-ons, tools and utilities») |

**Вывод:** установить `pgaudit` на этом стенде **невозможно**:

- в поставке PostgreSQL 18 для Windows нет ни `pgaudit.dll`, ни `pgaudit.control`;
- на GitHub (`pgaudit/pgaudit`, релиз `pgAudit 18.0`) — **только исходники**, бинарных файлов нет;
- собрать из исходников нельзя: в системе нет MSVC (`cl.exe`, `nmake.exe`, `msbuild.exe`),
  а DLL должен быть собран тем же MSVC 19.44, что и сам PostgreSQL;
- в каталоге EDB Stack Builder 4.2.2 для PostgreSQL 18 пакета `pgAudit` **нет** —
  проверено вручную в мастере (раздел «Add-ons, tools and utilities»).

Единственный незакрытый пункт лабораторной.

### 1.2. Порядок включения (когда DLL появится)

```ini
shared_preload_libraries = 'pg_stat_statements,pgaudit'
pgaudit.log = 'write,ddl,role'
pgaudit.log_catalog = off
pgaudit.log_relation = on
pgaudit.log_statement_once = off
```

Затем перезапустить службу и выполнить `CREATE EXTENSION pgaudit;`.

### 1.3. Временная замена (проверена)

До установки `pgaudit` аудит ведётся встроенными средствами:

```sql
ALTER SYSTEM SET log_statement = 'all';     -- все операторы, включая SELECT
ALTER SYSTEM SET log_connections = on;
SELECT pg_reload_conf();
```

Проверка: `SELECT` от `analyst_ivanova` попал в журнал:

```text
2026-11-05 21:53:12 MSK [15092]: [1-1] ... LOG:  statement: SET ROLE analyst_ivanova;
2026-11-05 21:53:12 MSK [15092]: [3-1] ... LOG:  statement: SELECT customer_name, region, status, order_count FROM orders_summary LIMIT 5;
```

Ограничение по сравнению с `pgaudit`: нет метки `AUDIT:`, нет разделения `write/ddl/role`,
в префиксе `user=postgres` (роль `session_user`, а не действующая `current_user`),
журналируются **все** операторы, включая служебные запросы клиента.
После проверки `log_statement` возвращён в исходное состояние (`ALTER SYSTEM RESET`).

---

## Часть 2. TLS

### 2.1. Состояние до работы

```text
ssl = off
pg_stat_ssl: строки с ssl = true отсутствовали
```

### 2.2. Включение

Сертификат создан `openssl` в каталоге данных (служба работает под `NT AUTHORITY\NetworkService`,
у неё есть `FullControl` на `data`):

```bash
openssl req -new -x509 -days 365 -nodes -out server.crt -keyout server.key -subj '/CN=localhost'
```

```text
subject=CN=localhost
notBefore=Nov  4 18:21:34 2026 GMT
notAfter=Nov 4 18:21:34 2027 GMT
```

В `postgresql.conf`:

```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file  = 'server.key'
```

Параметры уровня postmaster — применены **перезапуском службы** (`pg_reload_conf()` их не применяет).

### 2.3. Принудительный TLS в pg_hba.conf

Правила добавлены **выше** общих `host`-правил (иначе сработало бы первое совпадение):

```text
hostssl    eshop  app_backend  127.0.0.1/32  scram-sha-256
hostnossl  eshop  app_backend  127.0.0.1/32  reject
...
host       all    all          127.0.0.1/32  scram-sha-256
```

После `SELECT pg_reload_conf()` текущее соединение:

| ssl | version | cipher |
|---|---|---|
| **t** | **TLSv1.3** | **TLS_AES_256_GCM_SHA384** |

### 2.4. Проверка через psql

| Команда | Результат |
|---|---|
| `sslmode=require` | подключается, `SELECT ssl FROM pg_stat_ssl` → **t** |
| `sslmode=disable` | `FATAL: pg_hba.conf rejects connection for host "127.0.0.1", user "app_backend", database "eshop", no encryption` |

Оба поведения соответствуют ожидаемым.

---

## Часть 3. pgcrypto

### 3.1. Установка

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- версия 1.4
```

### 3.2. Шифрование телефонов

```sql
ALTER TABLE customers ADD COLUMN IF NOT EXISTS phone_encrypted BYTEA;

UPDATE customers
SET    phone = '+7-900-' || lpad((id % 10000000)::text, 7, '0')
WHERE  phone IS NULL;                                  -- 20 000 строк

UPDATE customers
SET    phone_encrypted = pgp_sym_encrypt(phone, 'secret_key_2024')
WHERE  phone IS NOT NULL;                              -- 20 000 строк
```

Зашифрованные данные выглядят как байты:

```text
 id |     phone      |                                        phone_encrypted
----+----------------+--------------------------------------------------------------------------------------------
  1 | +7-900-0000001 | \xc30d0407030258289cfa42e1a8f864d23f0127e6c3b53183146a6cbd3ade8b6e8ee8ecfe0ef961abb14f313eeaed...
  2 | +7-900-0000002 | \xc30d040703029bf406fb752f86166fd23f017d57086d2b58de579c377d65afddcc574060a45771a7657117a188...
  3 | +7-900-0000003 | \xc30d04070302e22f8544366792c46ed23f0108b29724da136992b2c752a45c8d8832b76e4ab353bcbb4bad4f...
```

### 3.3. Расшифровка

| Проверка | Результат |
|---|---|
| `pgp_sym_decrypt(phone_encrypted,'secret_key_2024')` | `+7-900-0000001`, `+7-900-0000002`, `+7-900-0000003` — исходные номера |
| Сверка всех строк: расшифровка = `phone` | **20 000 из 20 000** совпали |
| Неверный ключ | `ERROR: Wrong key or corrupt data` |

### 3.4. Права доступа

```sql
UPDATE customers SET phone = '***';

SET ROLE analyst_ivanova;
SET app.current_region = 'MSK';
SELECT count(*) FROM customers;   -- 1 007
SELECT full_name, phone, phone_encrypted FROM customers LIMIT 3;
```

| Что видит аналитик | Значение |
|---|---|
| Строк | **1 007** из 20 000 (RLS-политика `customers_by_region` по `app.current_region`) |
| `phone` | `***` (маскирован) |
| `phone_encrypted` | байты `\xc30d04...` — без ключа не читаются |

Без `SET app.current_region` аналитик видит **0 строк** — это работающая RLS-защита, а не ошибка прав.

---

## Часть 4. ИБ-чек-лист

Документ: [`ib_checklist.md`](ib_checklist.md) — 8 пунктов из 13 выполнено, 5 оформлены как
организационные меры или заблокированы (`pgaudit`).

---

## Самостоятельные задания

### 1. Аудит `SELECT` для `customers`

`pgaudit` не установлен, поэтому аудит `SELECT` проверен встроенным `log_statement = 'all'`.
Результат: запрос аналитика попал в журнал (см. п. 1.3). При установленном `pgaudit` для этого нужно:

```sql
GRANT SELECT ON customers TO eshop_auditor;   -- объектный аудит
-- + pgaudit.role = 'eshop_auditor' в postgresql.conf
```

Тогда каждая выборка из `customers` любым пользователем даёт строку
`AUDIT: SESSION,...,READ,SELECT,TABLE,public.customers,...` независимо от `pgaudit.log`.
Сессионный аудит включается иначе: `pgaudit.log = 'read'` (или `'all'`).

### 2. Уровень защищённости ПДн для eshop

Обрабатываются **общие** категории ПДн (ФИО, email, телефон), специальные категории и биометрия — нет.
Объём субъектов — менее 100 000. Актуальные угрозы — 2-го типа (по ПП РФ № 1119).

**Уровень защищённости — УЗ-3** (3-й уровень).

Почему не УЗ-2: УЗ-2 требуется при наличии угроз 2-го типа **вместе** со специальными категориями
или биометрией, либо при >100 000 субъектов общих ПДн. Ни одно условие не выполняется.

Организационные меры для УЗ-3:

1. Приказ о назначении ответственного за обработку ПДн и замещающего лица.
2. Акт определения уровня защищённости + модель угроз.
3. Политика обработки ПДн, правила разграничения доступа (реализованы ролями и RLS).
4. Журналирование доступа к ПДн (после установки `pgaudit`), контроль сроков хранения.
5. Согласия субъектов ПДн, порядок отзыва согласия и удаления данных.
6. Регламент резервного копирования с шифрованием копий.
7. Ознакомление сотрудников с правилами обработки ПДн.

### 3. Компрометация ключа шифрования

Порядок действий:

1. **Немедленно сменить ключ**: расшифровать старым ключом и зашифровать новым, одной транзакцией:

```sql
BEGIN;
ALTER TABLE customers ADD COLUMN phone_encrypted_v2 BYTEA;
UPDATE customers
SET    phone_encrypted_v2 = pgp_sym_encrypt(pgp_sym_decrypt(phone_encrypted,'OLD'), 'NEW');
COMMIT;
-- затем в отдельной транзакции: DROP COLUMN phone_encrypted; RENAME phone_encrypted_v2 -> phone_encrypted;
```

2. Выяснить источник утечки (код приложения, логи, дампы, git-история) и устранить.
3. Считать скомпрометированными **все** данные, зашифрованные старым ключом, — уведомить
   ответственного за ПДн; при утечке ПДн — уведомить Роскомнадзор в течение 24 ч (ч. 3.1 ст. 21 152-ФЗ).
4. Перевыпустить резервные копии: старые копии содержат данные под старым ключом — их перешифровать
   или уничтожить.
5. Перевести хранение ключа из SQL-текста в Vault/HSM с аудитом доступа к ключу и ротацией.
