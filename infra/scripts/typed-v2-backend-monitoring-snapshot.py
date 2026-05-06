#!/usr/bin/env python3
"""Server-side typed v2 monitoring snapshot adapter.

Builds a truthful rollout snapshot from backend logs/events available on Linux server
without relying on mobile-only telemetry events.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _p95(values: list[int]) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    idx = int(math.ceil(len(ordered) * 0.95)) - 1
    idx = max(0, min(idx, len(ordered) - 1))
    return int(ordered[idx])


def _rate(numerator: int, denominator: int) -> float:
    if denominator <= 0:
        return 0.0
    return round(float(numerator) / float(denominator), 6)


def _to_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _parse_json_line(raw_line: str) -> dict[str, Any] | None:
    idx = raw_line.find("{")
    if idx < 0:
        return None
    blob = raw_line[idx:].strip()
    try:
        payload = json.loads(blob)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def _run_journalctl(unit: str, since: str) -> list[str]:
    cmd = [
        "journalctl",
        "-u",
        unit,
        "--since",
        since,
        "--no-pager",
        "-o",
        "cat",
    ]
    proc = subprocess.run(cmd, check=True, text=True, capture_output=True)
    return proc.stdout.splitlines()


def _load_lines(unit: str, since: str, input_log: str | None) -> tuple[list[str], str]:
    if input_log:
        data = Path(input_log).read_text(encoding="utf-8", errors="replace")
        return data.splitlines(), f"file:{input_log}"
    return _run_journalctl(unit=unit, since=since), f"journalctl:{unit}:{since}"


def _build_snapshot(
    lines: list[str],
    input_source: str,
    unit: str,
    since: str,
) -> dict[str, Any]:
    read_events: dict[str, list[dict[str, Any]]] = {
        "v2_read_profile": [],
        "v2_read_results": [],
        "v2_read_overview": [],
    }
    metric_counters: dict[tuple[str, str], int] = defaultdict(int)
    metric_hist_values: dict[tuple[str, str], list[int]] = defaultdict(list)

    parsed_events = 0
    for line in lines:
        payload = _parse_json_line(line)
        if payload is None:
            continue
        parsed_events += 1
        msg = str(payload.get("msg", "")).strip()
        if msg in read_events:
            read_events[msg].append(payload)
            continue

        if msg != "observability_metric":
            continue
        kind = str(payload.get("kind", "")).strip()
        name = str(payload.get("name", "")).strip()
        endpoint = str(payload.get("endpoint", "")).strip()
        key = (name, endpoint)

        if kind == "metric_counter":
            metric_counters[key] += 1
            continue
        if kind == "metric_histogram":
            raw_value = _to_int(payload.get("value"))
            if raw_value is not None:
                metric_hist_values[key].append(raw_value)

    endpoint_to_event = {
        "profile": "v2_read_profile",
        "results": "v2_read_results",
        "overview": "v2_read_overview",
    }
    endpoint_stats: dict[str, dict[str, Any]] = {}
    total_read_requests = 0
    total_read_failures = 0
    latency_buckets = {"profile": [], "results": [], "overview": []}

    for endpoint, event_name in endpoint_to_event.items():
        success_events = read_events[event_name]
        success_count_event = len(success_events)
        success_count_metric = metric_counters[("backend.read.success_total", endpoint)]
        failure_count_metric = metric_counters[("backend.read.failure_total", endpoint)]
        request_count_metric = metric_counters[("backend.read.requests_total", endpoint)]

        request_total = request_count_metric
        if request_total == 0:
            request_total = success_count_metric + failure_count_metric
        if request_total == 0:
            request_total = success_count_event + failure_count_metric

        latency_values = []
        for item in success_events:
            val = _to_int(item.get("latency_ms"))
            if val is not None:
                latency_values.append(val)
        latency_buckets[endpoint] = latency_values

        total_read_requests += request_total
        total_read_failures += failure_count_metric
        endpoint_stats[endpoint] = {
            "requests_total": request_total,
            "success_total": max(success_count_event, success_count_metric),
            "failure_total": failure_count_metric,
            "latency_p95_ms": _p95(latency_values),
        }

    # Fallback metric is emitted from backend read service (when available in logging mode).
    fallback_total = 0
    for (name, endpoint), count in metric_counters.items():
        if name == "backend.read.fallback_total":
            # endpoint may be "profile_overview" in current implementation.
            if endpoint in ("profile", "overview", "profile_overview", "results", ""):
                fallback_total += count

    ingest_requests = sum(
        count
        for (name, _), count in metric_counters.items()
        if name == "backend.ingest.requests_total"
    )
    ingest_success = sum(
        count
        for (name, _), count in metric_counters.items()
        if name == "backend.ingest.success_total"
    )
    ingest_failure = sum(
        count
        for (name, _), count in metric_counters.items()
        if name == "backend.ingest.failure_total"
    )
    ingest_latency_values = []
    for (name, _), values in metric_hist_values.items():
        if name == "backend.ingest.latency_ms":
            ingest_latency_values.extend(values)

    # Backend-only decision: truthful and conservative.
    samples = min(
        endpoint_stats["profile"]["requests_total"],
        endpoint_stats["results"]["requests_total"],
        endpoint_stats["overview"]["requests_total"],
    )
    failed_rate = _rate(total_read_failures, total_read_requests)
    fallback_rate = _rate(fallback_total, total_read_requests)
    degraded_rate = None  # mobile-side refresh concept is not emitted by backend runtime logs
    parity_mismatch_rate = None  # mobile parity shadow event is mobile-side
    severe_parity_mismatch_rate = None  # mobile-only signal
    snapshot_inconsistency_total = None  # mobile-only signal

    gate_outcome = "watch"
    gate_trigger = "missing_mobile_gate_signal_backend_adapter"
    watch_reasons: list[str] = ["mobile_only_gate_missing"]
    rollback_class = False

    if total_read_requests > 0 and failed_rate >= 0.08:
        gate_outcome = "rollback"
        gate_trigger = "backend_read_failure_rate_rollback"
        watch_reasons = []
        rollback_class = True
    elif samples < 20:
        gate_outcome = "hold"
        gate_trigger = "insufficient_window"
        if "insufficient_sample_window" not in watch_reasons:
            watch_reasons.append("insufficient_sample_window")

    hold_class = gate_outcome == "hold"
    watch_class = True if watch_reasons else False

    source_of_truth = {
        "primary": [
            "backend:v2_read_profile",
            "backend:v2_read_results",
            "backend:v2_read_overview",
        ],
        "secondary": [
            "backend:observability_metric backend.read.*",
            "backend:observability_metric backend.ingest.*",
        ],
        "missing_mobile_signals": [
            "typed_read_stage_gate_check",
            "typed_read_refresh_result",
            "typed_read_parity_shadow",
            "typed_read_v2_snapshot_inconsistency",
        ],
        "precedence": ["rollback", "hold", "promote"],
    }

    snapshot = {
        "generated_at_utc": _now_utc_iso(),
        "adapter_mode": "backend_server_side",
        "input_source": input_source,
        "unit": unit,
        "since": since,
        "totals": {
            "raw_lines_total": len(lines),
            "json_events_parsed_total": parsed_events,
            "profile_requests_total": endpoint_stats["profile"]["requests_total"],
            "results_requests_total": endpoint_stats["results"]["requests_total"],
            "overview_requests_total": endpoint_stats["overview"]["requests_total"],
            "read_requests_total": total_read_requests,
            "read_failures_total": total_read_failures,
            "fallback_total": fallback_total,
            "ingest_requests_total": ingest_requests,
            "ingest_success_total": ingest_success,
            "ingest_failure_total": ingest_failure,
            "snapshot_inconsistency_total": snapshot_inconsistency_total,
        },
        "rates": {
            "failed_rate": failed_rate,
            "degraded_rate": degraded_rate,
            "fallback_rate": fallback_rate,
            "parity_mismatch_rate": parity_mismatch_rate,
            "severe_parity_mismatch_rate": severe_parity_mismatch_rate,
        },
        "latency_p95_ms": {
            "profile": endpoint_stats["profile"]["latency_p95_ms"],
            "results": endpoint_stats["results"]["latency_p95_ms"],
            "overview": endpoint_stats["overview"]["latency_p95_ms"],
            "ingest": _p95(ingest_latency_values),
        },
        "gate": {
            "latest_outcome": gate_outcome,
            "latest_trigger": gate_trigger,
            "samples": samples,
            "decision_scope": "backend_only_adapter",
            "decision_note": (
                "Backend-side health adapter without mobile-only parity/snapshot signals; "
                "it can veto on backend rollback/hold signals, but mobile gate artifact remains "
                "the rollout decision source when backend health is clean."
            ),
        },
        "alert_delivery": {
            "rollback_class_active": rollback_class,
            "hold_class_active": hold_class,
            "watch_class_active": watch_class,
            "watch_reasons": watch_reasons,
        },
        "endpoint_stats": endpoint_stats,
        "source_of_truth": source_of_truth,
    }
    return snapshot


def _render_markdown(snapshot: dict[str, Any]) -> str:
    totals = snapshot["totals"]
    rates = snapshot["rates"]
    latency = snapshot["latency_p95_ms"]
    gate = snapshot["gate"]
    alerts = snapshot["alert_delivery"]

    def _fmt(v: Any) -> str:
        return "n/a" if v is None else str(v)

    lines = [
        "# Typed V2 Backend Monitoring Snapshot",
        "",
        f"- Generated (UTC): {snapshot['generated_at_utc']}",
        f"- Adapter mode: {snapshot['adapter_mode']}",
        f"- Input source: {snapshot['input_source']}",
        f"- Unit: {snapshot['unit']}",
        f"- Since: {snapshot['since']}",
        "",
        "## Gate (Backend Adapter)",
        f"- Outcome: {gate['latest_outcome']}",
        f"- Trigger: {gate['latest_trigger']}",
        f"- Samples: {gate['samples']}",
        f"- Scope: {gate['decision_scope']}",
        "",
        "## Read Totals",
        f"- profile_requests_total: {totals['profile_requests_total']}",
        f"- results_requests_total: {totals['results_requests_total']}",
        f"- overview_requests_total: {totals['overview_requests_total']}",
        f"- read_failures_total: {totals['read_failures_total']}",
        f"- fallback_total: {totals['fallback_total']}",
        "",
        "## Ingest Totals",
        f"- ingest_requests_total: {totals['ingest_requests_total']}",
        f"- ingest_success_total: {totals['ingest_success_total']}",
        f"- ingest_failure_total: {totals['ingest_failure_total']}",
        "",
        "## Rates",
        f"- failed_rate: {_fmt(rates['failed_rate'])}",
        f"- degraded_rate: {_fmt(rates['degraded_rate'])}",
        f"- fallback_rate: {_fmt(rates['fallback_rate'])}",
        f"- parity_mismatch_rate: {_fmt(rates['parity_mismatch_rate'])}",
        f"- severe_parity_mismatch_rate: {_fmt(rates['severe_parity_mismatch_rate'])}",
        "",
        "## P95 Latency (ms)",
        f"- profile: {latency['profile']}",
        f"- results: {latency['results']}",
        f"- overview: {latency['overview']}",
        f"- ingest: {latency['ingest']}",
        "",
        "## Alert Classes",
        f"- rollback_class_active: {alerts['rollback_class_active']}",
        f"- hold_class_active: {alerts['hold_class_active']}",
        f"- watch_class_active: {alerts['watch_class_active']}",
        f"- watch_reasons: {', '.join(alerts['watch_reasons']) if alerts['watch_reasons'] else 'none'}",
        "",
        "## Coverage Notes",
        "- This adapter is backend-truthful and does not fabricate mobile-only signals.",
        "- Missing mobile-only signals are explicitly marked in `source_of_truth.missing_mobile_signals`.",
        "- Promote decision still requires manual operator review across full rollout evidence.",
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate typed v2 backend monitoring snapshot from journald logs."
    )
    parser.add_argument("--workspace", default=".", help="Workspace root for default report paths.")
    parser.add_argument("--unit", default="kundi-prod-api.service", help="systemd unit to read.")
    parser.add_argument("--since", default="1 hour ago", help='journalctl --since value (e.g. "24 hours ago").')
    parser.add_argument("--input-log", default="", help="Optional local log file instead of journalctl.")
    parser.add_argument("--output-json", default="", help="Output snapshot JSON path.")
    parser.add_argument("--output-markdown", default="", help="Output snapshot markdown path.")
    args = parser.parse_args()

    workspace = Path(args.workspace).resolve()
    reports_dir = workspace / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)

    output_json = Path(args.output_json) if args.output_json else reports_dir / "typed_v2_backend_monitoring_snapshot.json"
    output_md = Path(args.output_markdown) if args.output_markdown else reports_dir / "typed_v2_backend_monitoring_snapshot.md"

    lines, input_source = _load_lines(
        unit=args.unit,
        since=args.since,
        input_log=args.input_log if args.input_log else None,
    )
    snapshot = _build_snapshot(
        lines=lines,
        input_source=input_source,
        unit=args.unit,
        since=args.since,
    )

    output_json.write_text(
        json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    output_md.write_text(_render_markdown(snapshot), encoding="utf-8")

    print(f"Backend monitoring snapshot JSON: {output_json}")
    print(f"Backend monitoring snapshot MD:   {output_md}")
    print(
        "Gate outcome: "
        f"{snapshot['gate']['latest_outcome']} "
        f"(trigger={snapshot['gate']['latest_trigger']}, samples={snapshot['gate']['samples']})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
