#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
binary="$package_root/bin/migrator"
[ -x "$binary" ] || { echo "runtime entrypoint is missing or not executable: bin/migrator" >&2; exit 78; }
cd "$package_root"
exec "$binary" "$@"
