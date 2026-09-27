param(
    [switch]$BuildWindows,
    [switch]$BuildAndroid,
    [string]$SupabaseUrl = '',
    [string]$SupabasePublishableKey = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Run-Step {
    param([string]$Label, [string]$Command, [string[]]$Arguments)
    Write-Host "`n$Label" -ForegroundColor Cyan
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

$Defines = @()
if ($SupabaseUrl -and $SupabasePublishableKey) {
    $Defines += "--dart-define=SUPABASE_URL=$SupabaseUrl"
    $Defines += "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SupabasePublishableKey"
}
elseif ($SupabaseUrl -or $SupabasePublishableKey) {
    throw 'Provide both SupabaseUrl and SupabasePublishableKey, or neither.'
}

Run-Step 'Repairing Android and Windows runners' 'flutter' @(
    'create', '--platforms=android,windows', '.'
)
Run-Step 'Applying Gahunda platform configuration' 'powershell' @(
    '-ExecutionPolicy', 'Bypass', '-File', 'tool/configure_platforms.ps1'
)
Run-Step 'Resolving dependencies' 'flutter' @('pub', 'get')
Run-Step 'Applying Gahunda launcher icons' 'dart' @(
    'run', 'flutter_launcher_icons', '-f', 'flutter_launcher_icons.yaml'
)
Run-Step 'Formatting source and tests' 'dart' @('format', 'lib', 'test')
Run-Step 'Running static analysis' 'flutter' @('analyze')
Run-Step 'Running automated tests' 'flutter' @('test')

if ($BuildWindows) {
    Run-Step 'Building Windows release' 'flutter' (@('build', 'windows', '--release') + $Defines)
}
if ($BuildAndroid) {
    Run-Step 'Building Android App Bundle' 'flutter' (@('build', 'appbundle', '--release') + $Defines)
}

Write-Host "`nGahunda release checks passed." -ForegroundColor Green
