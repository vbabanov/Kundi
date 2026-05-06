$ErrorActionPreference = "Stop"

$infraRoot = Join-Path $PSScriptRoot ".."
$composeFile = Join-Path $infraRoot "docker\docker-compose.staging.yml"
$envExample = Join-Path $infraRoot "env\backend.staging.env.example"
$envFile = Join-Path $infraRoot "env\backend.staging.env"

if (-not (Test-Path $envFile)) {
  Copy-Item $envExample $envFile
  Write-Host "Created $envFile from example. Fill secrets before real staging use."
}

Push-Location (Join-Path $infraRoot "docker")
docker compose --env-file "../env/backend.staging.env" -f "docker-compose.staging.yml" up -d --build
Pop-Location

Write-Host "Staging stack started (postgres, minio, migrator, api, workers)."
Write-Host "Health check: GET http://localhost:8080/readyz"
