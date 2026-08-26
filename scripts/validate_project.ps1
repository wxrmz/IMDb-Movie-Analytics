$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $projectRoot

python -m py_compile `
    .\scripts\prepare_imdb_subset.py `
    .\scripts\profile_imdb_raw.py `
    .\scripts\render_charts.py

docker compose config --quiet

docker compose exec -T postgres `
    psql -v ON_ERROR_STOP=1 -U postgres -d movie_analytics `
    -f /sql/99_validation.sql

Write-Host 'Static and database validation completed successfully.'
