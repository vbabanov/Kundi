# ADR 0004: Mood and Evidence Preservation

## Status
Accepted

## Context
`mood/quality` приходит из источника и может различаться между endpoint-ами.
Нужна и каноническая версия, и трассировка первоисточника.

## Decision
1. В canonical result хранить:
   - `resolved_mood`
2. В evidence хранить:
   - `source_mood_raw`
   - `source_endpoint`
   - `provider_mark_id/provider_work_id`

## Rules
- Никогда не терять source mood.
- Изменение `resolved_mood` допустимо только через dedup merge policy.
- При конфликте значений mood хранить оба (canonical + evidence), без удаления истории.
