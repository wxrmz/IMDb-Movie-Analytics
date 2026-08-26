$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $projectRoot

$manifestPath = Join-Path $projectRoot 'data\processed\imdb\manifest.json'
$rawFiles = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'data\raw\imdb') `
    -Filter '*.tsv.gz' -File
$needsPreparation = -not (Test-Path -LiteralPath $manifestPath)

if (-not $needsPreparation) {
    $manifestTime = (Get-Item -LiteralPath $manifestPath).LastWriteTimeUtc
    $needsPreparation = $rawFiles.Where({ $_.LastWriteTimeUtc -gt $manifestTime }).Count -gt 0
}

if ($needsPreparation) {
    python .\scripts\prepare_imdb_subset.py
} else {
    Write-Host 'Processed IMDb snapshot is current; skipping preparation.'
}

docker compose up -d postgres

Write-Host 'Waiting for PostgreSQL...'
do {
    Start-Sleep -Seconds 2
    docker compose exec -T postgres pg_isready -U postgres -d movie_analytics | Out-Null
} while ($LASTEXITCODE -ne 0)

$sqlFiles = @(
    '00_schema.sql',
    '01_load_data.sql',
    '10_views.sql',
    '11_indexes.sql',
    '13_export_results.sql',
    '99_validation.sql'
)

foreach ($sqlFile in $sqlFiles) {
    Write-Host "Running $sqlFile"
    docker compose exec -T postgres `
        psql -v ON_ERROR_STOP=1 -U postgres -d movie_analytics `
        -f "/sql/$sqlFile"
}

Write-Host 'Project database is ready on localhost:5432/movie_analytics.'
