# Production Prometheus pin

Production uses Prometheus `v3.13.2` LTS for Linux amd64. The release archive is pinned to the official GitHub asset:

```text
prometheus-3.13.2.linux-amd64.tar.gz
sha256:0e8c4d46101bd025ea8265e377d2caabc57f488fc1be1c367f37db69ea41be6f
```

Install into a versioned `/opt/kundi/prometheus-v3.13.2` directory only after the archive checksum matches, then atomically point `/opt/kundi/prometheus` at that directory. The systemd unit never downloads or upgrades a binary. Keep the previous versioned directory until the new service has passed readiness, query, and restart-persistence checks.

The upstream LTS line is supported through July 2027. Patch upgrades require the same checksum, loopback binding, config validation, restart-persistence, and rollback checks.
