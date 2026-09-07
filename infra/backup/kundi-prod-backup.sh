#!/usr/bin/env bash
set -euo pipefail

umask 077

backup_dir="${KUNDI_BACKUP_DIR:-/root/kundi-prod/shared/backups}"
container="${KUNDI_POSTGRES_CONTAINER:-kundi-prod-postgres}"
retention_days="${KUNDI_BACKUP_RETENTION_DAYS:-14}"
state_file="${KUNDI_BACKUP_STATE_FILE:-/var/lib/kundi-prod-backup/last-success}"

case "$backup_dir" in
  /*) ;;
  *) echo "backup directory must be absolute" >&2; exit 1 ;;
esac
case "$backup_dir" in
  /|/root|/root/kundi-prod|/root/kundi-prod/shared)
    echo "backup directory is too broad" >&2
    exit 1
    ;;
esac
case "$retention_days" in
  ''|*[!0-9]*) echo "retention days must be a positive integer" >&2; exit 1 ;;
esac
if [ "$retention_days" -lt 1 ]; then
  echo "retention days must be a positive integer" >&2
  exit 1
fi

install -d -m 0700 "$backup_dir" "$(dirname "$state_file")"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
final_path="$backup_dir/kundi-prod-daily-$timestamp.dump"
checksum_path="$final_path.sha256"
temporary_path="$(mktemp "$backup_dir/.kundi-prod-daily.XXXXXX.dump")"
temporary_checksum="$(mktemp "$backup_dir/.kundi-prod-daily.XXXXXX.sha256")"

cleanup() {
  rm -f -- "$temporary_path" "$temporary_checksum"
}
trap cleanup EXIT

docker exec "$container" sh -c \
  'exec pg_dump -Fc --no-owner --no-acl -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  >"$temporary_path"
test -s "$temporary_path"
docker exec -i "$container" sh -c 'exec pg_restore --list >/dev/null' \
  <"$temporary_path"
chmod 0600 "$temporary_path"
mv -T -- "$temporary_path" "$final_path"
(cd "$backup_dir" && sha256sum "$(basename "$final_path")") >"$temporary_checksum"
chmod 0600 "$temporary_checksum"
mv -T -- "$temporary_checksum" "$checksum_path"

find "$backup_dir" -maxdepth 1 -type f \
  \( -name 'kundi-prod-daily-*.dump' -o -name 'kundi-prod-daily-*.dump.sha256' \) \
  -mtime "+$retention_days" -delete

state_tmp="$(mktemp "$(dirname "$state_file")/.last-success.XXXXXX")"
printf 'completed_at_utc=%s\nbackup_file=%s\n' "$timestamp" "$(basename "$final_path")" >"$state_tmp"
chmod 0600 "$state_tmp"
mv -T -- "$state_tmp" "$state_file"
trap - EXIT
