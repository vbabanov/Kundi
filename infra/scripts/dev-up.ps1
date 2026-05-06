$ErrorActionPreference = "Stop"

Push-Location "$PSScriptRoot/../docker"
docker compose up -d
Pop-Location

Write-Host "Kundi dev infra is up (Postgres + MinIO)."
