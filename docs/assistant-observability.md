# Assistant production observability

The API's `prometheus` observability mode retains the existing structured logs and exposes only the six bounded Assistant metric families below on the configured loopback listener. Production uses `127.0.0.1:29090`; Caddy must not proxy that port or add a `/metrics` route.

- `assistant_requests_total`
- `assistant_latency_ms`
- `assistant_generation_requests_total`
- `assistant_generation_latency_ms`
- `assistant_generation_attempts_total`
- `assistant_generation_attempt_latency_ms`

The exporter accepts only fixed metric names, label names, and label values. Unknown label values become `unknown`; identifiers, content, credentials, endpoints, provider request IDs, and free-form errors are not exported. Prometheus listens on `127.0.0.1:29091`, scrapes every 15 seconds, retains at most 30 days or 1 GB, and persists its TSDB in `/var/lib/kundi-prod-prometheus`.

## Health and privacy checks

Run these commands on the production host. They produce only status, schema, or aggregates.

```bash
curl --fail --silent http://127.0.0.1:29090/healthz
curl --fail --silent http://127.0.0.1:29091/-/ready
curl --fail --silent http://127.0.0.1:29090/metrics | grep -E '^# (HELP|TYPE) assistant_'
curl --fail --silent https://api.kundi.lucartmax.kz/metrics -o /dev/null -w '%{http_code}\n'
```

The public request must not return `200`. Never copy raw series into a ticket before checking their label schema. The approved schema has no student, account, session, message, prompt, response, token, endpoint, or request-id labels.

## Bounded canary queries

Prometheus HTTP queries must URL-encode the expression. The expressions below contain aggregates only.

```promql
sum by (result) (increase(assistant_generation_requests_total[1h]))
sum(increase(assistant_generation_requests_total{result="success"}[1h])) / clamp_min(sum(increase(assistant_generation_requests_total[1h])), 1)
sum(increase(assistant_generation_requests_total{result=~"timeout|malformed|incomplete"}[1h]))
histogram_quantile(0.50, sum by (le, locale) (rate(assistant_generation_latency_ms_bucket{locale=~"ru|kk"}[1h])))
histogram_quantile(0.95, sum by (le, locale) (rate(assistant_generation_latency_ms_bucket{locale=~"ru|kk"}[1h])))
sum by (stage, result) (increase(assistant_generation_attempts_total[1h]))
sum(increase(assistant_generation_requests_total{fallback_attempted="true"}[1h]))
sum(increase(assistant_generation_requests_total{fallback_succeeded="true"}[1h]))
```

For a one-student cohort, narrow time ranges can reveal an individual's activity pattern even without identifiers. Limit access to root/SSH operators and report only sufficiently aggregated soak summaries.

## Rollback

Disable only the `40-assistant-observability.conf` API drop-in, restart the API, then disable `kundi-prod-prometheus.service`. This restores log-mode observability and does not change the Assistant allowlist, database, Alem configuration, Voice/TTS flags, or any worker.
