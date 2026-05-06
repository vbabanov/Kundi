# Connector Diagnostics and Safe Logging Rules

## Current diagnostic behavior
- Connector diagnostics events are typed (`code`, `level`, `details`).
- Raw payload repository applies:
  - key-based redaction (`password`, `token`, `cookie`, `authorization`, `secret`)
  - body truncation
  - TTL pruning
  - record count bounding

## Safe logging rules
1. Never log credentials.
2. Never log full cookies or auth headers.
3. Do not store unbounded full response bodies.
4. Keep diagnostic retention short and bounded.
5. Prefer structural summaries over raw dumps.

## QA usage
- Use diagnostics only in debug/internal builds.
- Export diagnostics after failed sync runs to local QA report.
- Clear diagnostics before handing device to another user.
