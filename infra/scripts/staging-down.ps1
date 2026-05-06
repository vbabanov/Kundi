$ErrorActionPreference = "Stop"

$composeDir = Join-Path $PSScriptRoot "..\docker"
Push-Location $composeDir
docker compose -f "docker-compose.staging.yml" down
Pop-Location

Write-Host "Staging stack stopped."
