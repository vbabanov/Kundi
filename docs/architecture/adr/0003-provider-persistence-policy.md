# ADR 0003: Provider Persistence as First-Class Field

## Status
Accepted

## Context
Система Kundelik-first, но должна расширяться до новых providers без миграции всей модели.

## Decision
Поле `provider` обязательно для всех академических фактов и source metadata:
- lessons
- academic_results
- academic_aggregates
- attendance events
- ingest batches
- result evidence
- provider identity snapshots

## Rules
- `provider` хранится как нормализованный lowercase code (`kundelik`, `dnevnikru`, `edupage`).
- Никакой академический факт не считается валидным без provider.
- Для новых providers добавляется adapter + маппинг, а не новый контур таблиц.
