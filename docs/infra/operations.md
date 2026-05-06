# Infra Operations Notes

- Local dev stack: PostgreSQL + object storage via Docker compose.
- App binaries are stateless and horizontally scalable.
- Migrations are executed as deployment pre-step.
- Workers use DB leases and idempotent job semantics.
