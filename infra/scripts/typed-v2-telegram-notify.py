#!/usr/bin/env python3
"""Linux-native Telegram notify sender for typed v2 rollout snapshot."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


def _fmt(value: Any) -> str:
    if value is None:
        return "n/a"
    return str(value)


def _build_message(snapshot: dict[str, Any], snapshot_json_path: str) -> str:
    gate = snapshot.get("gate", {})
    totals = snapshot.get("totals", {})
    rates = snapshot.get("rates", {})
    alerts = snapshot.get("alert_delivery", {})

    rollback = bool(alerts.get("rollback_class_active", False))
    hold = bool(alerts.get("hold_class_active", False))
    watch = bool(alerts.get("watch_class_active", False))

    alert_class = "watch"
    if rollback:
        alert_class = "rollback"
    elif hold:
        alert_class = "hold"
    elif watch:
        alert_class = "watch"
    elif str(gate.get("latest_outcome", "")).strip().lower() == "promote":
        alert_class = "promote"

    watch_reasons = alerts.get("watch_reasons") or []
    if not isinstance(watch_reasons, list):
        watch_reasons = []
    watch_reason_text = ", ".join(str(x) for x in watch_reasons) if watch_reasons else "none"

    lines = [
        "Kundi Typed V2 Rollout Alert (server)",
        f"class={alert_class} outcome={gate.get('latest_outcome', 'unknown')} trigger={gate.get('latest_trigger', 'none')}",
        f"samples={gate.get('samples', 0)} read_requests={totals.get('read_requests_total', 0)} failures={totals.get('read_failures_total', 0)} fallback_total={totals.get('fallback_total', 0)}",
        f"failed_rate={_fmt(rates.get('failed_rate'))} degraded_rate={_fmt(rates.get('degraded_rate'))} fallback_rate={_fmt(rates.get('fallback_rate'))}",
        f"parity_mismatch_rate={_fmt(rates.get('parity_mismatch_rate'))} snapshot_inconsistency_total={_fmt(totals.get('snapshot_inconsistency_total'))}",
        f"watch_reasons={watch_reason_text}",
        f"snapshot_json={snapshot_json_path}",
    ]
    return "\n".join(lines)


def _send_telegram(bot_token: str, chat_id: str, message: str) -> None:
    endpoint = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload = urllib.parse.urlencode({"chat_id": chat_id, "text": message}).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=payload,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(request, timeout=15) as resp:
        raw = resp.read().decode("utf-8", errors="replace")
        data = json.loads(raw)
        if not isinstance(data, dict) or data.get("ok") is not True:
            raise RuntimeError("Telegram API returned non-ok response")


def main() -> int:
    parser = argparse.ArgumentParser(description="Send typed v2 rollout alert to Telegram.")
    parser.add_argument("--snapshot-json", required=True, help="Path to generated snapshot JSON")
    parser.add_argument("--bot-token", default="", help="Telegram bot token (fallback env)")
    parser.add_argument("--chat-id", default="", help="Telegram chat id (fallback env)")
    parser.add_argument("--dry-run", action="store_true", help="Render message without sending")
    args = parser.parse_args()

    snapshot_path = Path(args.snapshot_json).resolve()
    if not snapshot_path.exists():
        raise FileNotFoundError(f"Snapshot JSON not found: {snapshot_path}")

    bot_token = args.bot_token.strip() or os.getenv("KUNDI_TYPED_V2_TELEGRAM_BOT_TOKEN", "").strip()
    chat_id = args.chat_id.strip() or os.getenv("KUNDI_TYPED_V2_TELEGRAM_CHAT_ID", "").strip()

    payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
    message = _build_message(payload, str(snapshot_path))

    if args.dry_run:
        print("Dry run enabled; notification not sent.")
        print("----- Notification payload -----")
        print(message)
        print("--------------------------------")
        return 0

    if not bot_token or not chat_id:
        raise RuntimeError(
            "Telegram config is missing. Set --bot-token/--chat-id "
            "or env vars KUNDI_TYPED_V2_TELEGRAM_BOT_TOKEN and KUNDI_TYPED_V2_TELEGRAM_CHAT_ID."
        )

    _send_telegram(bot_token=bot_token, chat_id=chat_id, message=message)
    print(f"Notification sent to Telegram chat: {chat_id}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - operational script
        print(f"Notification delivery failed: {exc}", file=sys.stderr)
        raise

