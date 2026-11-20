# DBA labs — PostgreSQL 18, база `eshop`

**Студент:** Исобаева Дарья Александровна, группа ПИ 4-1

Репозиторий содержит отчёты по лабораторным работам 5–10 и проект миграций схемы `eshop` для Flyway.

## Отчёты по лабораторным работам

Каталог [`labs/reports/`](labs/reports/)

| Лаба | Тема | Отчёт |
|---|---|---|
| 5 | Мониторинг: `pg_stat_*`, блокировки, журналирование | [db_health_report.md](labs/reports/db_health_report.md) |
| 6 | Анализ запросов: `pg_stat_statements`, `EXPLAIN ANALYZE`, pgBadger | [lab06_report.md](labs/reports/lab06_report.md) |
| 7 | Индексы, autovacuum, PgBouncer | [lab07_report.md](labs/reports/lab07_report.md) · [pgbouncer_justification.md](labs/reports/pgbouncer_justification.md) |
| 8 | Информационная безопасность: pgAudit, TLS, pgcrypto | [lab08_report.md](labs/reports/lab08_report.md) · [ib_checklist.md](labs/reports/ib_checklist.md) |
| 9 | Flyway: миграции схемы, Migration Plan, Runbook | [lab09_report.md](labs/reports/lab09_report.md) |
| 10 | Rollback, zero-downtime, итоговая защита проекта | [lab10_report.md](labs/reports/lab10_report.md) · [eshop_project_report.md](labs/reports/eshop_project_report.md) |

Сводный отчёт по всем работам: [summary_report.md](labs/reports/summary_report.md)

## Проект миграций Flyway

Каталог [`eshop-migrations/`](eshop-migrations/)

| Файл | Что содержит |
|---|---|
| [migration_plan_V003.md](eshop-migrations/migration_plan_V003.md) | Migration Plan V003 (промокоды) + Runbook деплоя |
| [migration_plan_V004.md](eshop-migrations/migration_plan_V004.md) | Migration Plan V004 (баллы лояльности) + прогон из самостоятельного задания 2 |
| [flyway.toml](eshop-migrations/flyway.toml) | конфигурация Flyway (`cleanDisabled = true`) |
| [migrations/](eshop-migrations/migrations/) | V002 – V008, `R__orders_summary_view.sql`, отозванная `V005` |
| [test-task2/](eshop-migrations/test-task2/) | отдельный проект и БД `eshop_flyway_test` для проверки поведения при сбое миграции |

Миграции применяются так:

```powershell
cd eshop-migrations
$env:FLYWAY_PASSWORD = '<пароль роли postgres>'
& 'C:\tools\flyway-10\flyway.cmd' -configFiles=flyway.toml info
& 'C:\tools\flyway-10\flyway.cmd' -configFiles=flyway.toml migrate
```

> В `flyway.toml` пароль заменён на плейсхолдер: он передаётся через переменную окружения `FLYWAY_PASSWORD`.
