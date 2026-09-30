param(
  [Parameter(Mandatory = $true)]
  [string]$SupabaseUrl,

  [Parameter(Mandatory = $true)]
  [string]$SupabasePublishableKey,

  [Parameter(Mandatory = $true)]
  [string]$WebPushVapidPublicKey
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

powershell -ExecutionPolicy Bypass -File .\tool\configure_web.ps1
if ($LASTEXITCODE -ne 0) { throw 'Web setup failed.' }

dart format lib test web\drift_worker.dart
if ($LASTEXITCODE -ne 0) { throw 'Dart formatting failed.' }

flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }

flutter test
if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }

flutter build web --release `
  --dart-define="SUPABASE_URL=$SupabaseUrl" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SupabasePublishableKey" `
  --dart-define="WEB_PUSH_VAPID_PUBLIC_KEY=$WebPushVapidPublicKey"
if ($LASTEXITCODE -ne 0) { throw 'Flutter web release build failed.' }

$BuildRoot = (Resolve-Path .\build\web).Path
$AssetPaths = Get-ChildItem $BuildRoot -Recurse -File |
  Where-Object {
    $_.Name -ne 'gahunda_asset_manifest.js' -and
    -not $_.Name.StartsWith('_') -and
    $_.Extension -ne '.map'
  } |
  ForEach-Object {
    $Relative = $_.FullName.Substring($BuildRoot.Length).TrimStart([char[]]'\/')
    './' + $Relative.Replace('\', '/')
  } |
  Sort-Object -Unique

$AssetJson = ConvertTo-Json -InputObject (@('./') + @($AssetPaths)) -Compress
$ManifestSource = "self.GAHUNDA_ASSETS = $AssetJson;"
Set-Content `
  -Path .\build\web\gahunda_asset_manifest.js `
  -Value $ManifestSource `
  -Encoding utf8

Write-Host ''
Write-Host 'Release ready: build\web'
Write-Host 'Deploy that complete folder. Do not deploy the project source folder.'
