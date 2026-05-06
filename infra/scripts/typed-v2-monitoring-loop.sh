#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${KUNDI_TYPED_V2_MONITOR_WORKSPACE:-/root/kundi-prod/shared/ops/typed-v2}"
UNIT="${KUNDI_TYPED_V2_MONITOR_UNIT:-kundi-prod-api.service}"
SINCE="${KUNDI_TYPED_V2_MONITOR_SINCE:-1 hour ago}"
OUTPUT_JSON="${KUNDI_TYPED_V2_MONITOR_OUTPUT_JSON:-$WORKSPACE/reports/typed_v2_backend_monitoring_snapshot.json}"
OUTPUT_MD="${KUNDI_TYPED_V2_MONITOR_OUTPUT_MD:-$WORKSPACE/reports/typed_v2_backend_monitoring_snapshot.md}"

mkdir -p "$(dirname "$OUTPUT_JSON")"

python3 "$WORKSPACE/typed-v2-backend-monitoring-snapshot.py" \
  --workspace "$WORKSPACE" \
  --unit "$UNIT" \
  --since "$SINCE" \
  --output-json "$OUTPUT_JSON" \
  --output-markdown "$OUTPUT_MD"

python3 "$WORKSPACE/typed-v2-telegram-notify.py" \
  --snapshot-json "$OUTPUT_JSON"

echo "typed_v2_monitoring_loop completed: snapshot + telegram notify"
