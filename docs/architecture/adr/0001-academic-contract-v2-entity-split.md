# ADR 0001: Canonical Academic Contract v2 Entity Split

## Status
Accepted

## Context
Текущий контракт v1 смешивает event-level и aggregate-level данные в одном потоке ingest/read.
Это повышает риск конфликтов, особенно для dedup и эволюции под другие providers.

## Decision
Выбран **Variant B**:

1. `academic_results` хранит только event-level результаты:
   - `regular`
   - `sor`
   - `soch`
2. `academic_aggregates` хранит aggregate-level результаты:
   - `term`
   - `year`

Baseline v2 **не** включает speculative kinds, отсутствующие в текущих подтвержденных данных.

## Why
- Убирает неоднозначность полей `lesson_id/term_no/year_label`.
- Позволяет строго задать constraints для каждой сущности.
- Делает dedup проще и предсказуемее.
- Поддерживает расширяемость через справочник kinds без изменения контракта/DDL.

## Consequences
- Появляется дополнительная таблица `academic_aggregates`.
- Read DTO и ingest mapper должны явно разделять event vs aggregate.
- Текущий runtime не ломается: v1 путь продолжает работать параллельно.
