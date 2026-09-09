#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
for entrypoint in api migrator worker_ai worker_jobs worker_whatsapp; do
  path="$package_root/bin/$entrypoint"
  [ -f "$path" ] || { echo "runtime entrypoint is missing: bin/$entrypoint" >&2; exit 78; }
  [ -x "$path" ] || { echo "runtime entrypoint is not executable: bin/$entrypoint" >&2; exit 78; }
done
for wrapper in run-api.sh run-migrator.sh run-worker-ai.sh run-worker-jobs.sh run-worker-whatsapp.sh verify-runtime.sh; do
  path="$package_root/scripts/$wrapper"
  [ -f "$path" ] || { echo "runtime wrapper is missing: scripts/$wrapper" >&2; exit 78; }
  [ -x "$path" ] || { echo "runtime wrapper is not executable: scripts/$wrapper" >&2; exit 78; }
done
printf '%s\n' 'runtime_package=ready'
