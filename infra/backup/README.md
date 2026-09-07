# Production backup contract

`kundi-prod-backup.sh` creates a root-only PostgreSQL custom-format dump through the existing production container. It validates the archive with `pg_restore --list`, publishes the dump and checksum by atomic rename, and deletes only its own `kundi-prod-daily-*` files after the configured local retention period.

The systemd timer runs daily and catches up after downtime. Successful creation is not sufficient restore evidence: before a release or cohort decision, restore the latest dump into an isolated temporary PostgreSQL 16 container, run the canonical migrator to migration 11, verify required constraints, and remove only that temporary container.

Local backup protects against a bad release and many operator errors, but not host loss. Off-host encrypted custody remains an external production decision.
