param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter was not found. Install Flutter and reopen PowerShell.'
}

Write-Host 'Resolving Flutter packages...'
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

Write-Host 'Compiling the Drift database worker...'
dart compile js -O4 -o web/drift_worker.dart.js web/drift_worker.dart
if ($LASTEXITCODE -ne 0) { throw 'The Drift worker compilation failed.' }

$LockText = Get-Content .\pubspec.lock -Raw
$SqliteMatch = [regex]::Match(
  $LockText,
  '(?ms)^  sqlite3:\r?\n.*?^    version: "([^"]+)"'
)
if (-not $SqliteMatch.Success) {
  throw 'Could not find the resolved sqlite3 version in pubspec.lock.'
}

$SqliteVersion = $SqliteMatch.Groups[1].Value
$ReleaseUrl = "https://api.github.com/repos/simolus3/sqlite3.dart/releases/tags/sqlite3-$SqliteVersion"
$Headers = @{ 'User-Agent' = 'Gahunda-Web-Setup' }

Write-Host "Preparing sqlite3.wasm $SqliteVersion..."
$VersionFile = '.\web\sqlite3.version'
$CurrentVersion = if (Test-Path $VersionFile) {
  (Get-Content $VersionFile -Raw).Trim()
} else {
  ''
}

if (-not (Test-Path .\web\sqlite3.wasm) -or $CurrentVersion -ne $SqliteVersion) {
  $Release = Invoke-RestMethod -Uri $ReleaseUrl -Headers $Headers
  $Asset = $Release.assets |
    Where-Object { $_.name -eq 'sqlite3.wasm' } |
    Select-Object -First 1
  if ($null -eq $Asset) {
    throw "The sqlite3-$SqliteVersion release does not contain sqlite3.wasm."
  }
  Invoke-WebRequest `
    -Uri $Asset.browser_download_url `
    -Headers $Headers `
    -OutFile .\web\sqlite3.wasm `
    -UseBasicParsing
  Set-Content -Path $VersionFile -Value $SqliteVersion -Encoding ascii
} else {
  Write-Host 'The matching sqlite3.wasm is already present.'
}

if (-not (Test-Path .\web\sqlite3.wasm)) {
  throw 'sqlite3.wasm was not downloaded.'
}

Write-Host 'Gahunda Web setup is ready.'
