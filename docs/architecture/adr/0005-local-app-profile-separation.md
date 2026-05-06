# ADR 0005: Local App Profile Separation

## Status
Accepted

## Context
Поля `shift`, `parent_phone_1`, `parent_phone_2` вводятся пользователем в приложении и не являются provider truth.

## Decision
Ввести отдельную модель `LocalAppProfile`:
- хранить отдельно от provider identity и academic identity;
- не смешивать с `student_profiles` и provider snapshot.

## Rules
- LocalAppProfile изменяется только mobile/app workflow.
- Provider ingest не должен перезаписывать local-app поля.
- Read DTO должен явно помечать origin (`provider` vs `local_app`).
