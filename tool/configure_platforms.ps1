param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Save-TextFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Insert-BeforeFirst {
    param([string]$Content, [string]$Needle, [string]$Insertion)
    $Index = $Content.IndexOf($Needle, [System.StringComparison]::Ordinal)
    if ($Index -lt 0) {
        throw "Could not find '$Needle' while configuring a platform file."
    }
    return $Content.Insert($Index, $Insertion)
}

$AndroidManifest = Join-Path $ProjectRoot 'android/app/src/main/AndroidManifest.xml'
if (Test-Path $AndroidManifest) {
    $Manifest = [System.IO.File]::ReadAllText($AndroidManifest)
    $Manifest = $Manifest.Replace('android:label="gahunda"', 'android:label="Gahunda"')
    if (-not $Manifest.Contains('android.permission.SCHEDULE_EXACT_ALARM')) {
        $Manifest = [regex]::Replace(
            $Manifest,
            '(<manifest[^>]*>)',
            '$1' + "`r`n    <uses-permission android:name=`"android.permission.POST_NOTIFICATIONS`" />" +
            "`r`n    <uses-permission android:name=`"android.permission.RECEIVE_BOOT_COMPLETED`" />" +
            "`r`n    <uses-permission android:name=`"android.permission.SCHEDULE_EXACT_ALARM`" />",
            1
        )
    }
    if (-not $Manifest.Contains('ScheduledNotificationReceiver')) {
        $Receivers = @"
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
            android:exported="false" />
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>

"@
        $Manifest = Insert-BeforeFirst $Manifest '</application>' $Receivers
    }
    if (-not $Manifest.Contains('android:scheme="io.gahunda.app"')) {
        $DeepLink = @"
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="io.gahunda.app" android:host="login-callback" />
            </intent-filter>
"@
        $Manifest = Insert-BeforeFirst $Manifest '</activity>' $DeepLink
    }
    Save-TextFile $AndroidManifest $Manifest
    Write-Host 'Configured Android notification permissions, reboot recovery, and auth deep link.'
}
else {
    Write-Warning 'Android runner was not found. Run flutter create --platforms=android,windows . first.'
}

$KotlinGradle = Join-Path $ProjectRoot 'android/app/build.gradle.kts'
$GroovyGradle = Join-Path $ProjectRoot 'android/app/build.gradle'
if (Test-Path $KotlinGradle) {
    $Gradle = [System.IO.File]::ReadAllText($KotlinGradle)
    if (-not $Gradle.Contains('isCoreLibraryDesugaringEnabled')) {
        $Gradle = $Gradle.Replace(
            'compileOptions {',
            "compileOptions {`r`n        isCoreLibraryDesugaringEnabled = true"
        )
    }
    if (-not $Gradle.Contains('multiDexEnabled = true')) {
        $Gradle = $Gradle.Replace(
            'defaultConfig {',
            "defaultConfig {`r`n        multiDexEnabled = true"
        )
    }
    if (-not $Gradle.Contains('coreLibraryDesugaring(')) {
        $Gradle += @"

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
"@
    }
    Save-TextFile $KotlinGradle $Gradle
    Write-Host 'Enabled Android core-library desugaring.'
}
elseif (Test-Path $GroovyGradle) {
    $Gradle = [System.IO.File]::ReadAllText($GroovyGradle)
    if (-not $Gradle.Contains('coreLibraryDesugaringEnabled true')) {
        $Gradle = $Gradle.Replace(
            'compileOptions {',
            "compileOptions {`r`n        coreLibraryDesugaringEnabled true"
        )
    }
    if (-not $Gradle.Contains('multiDexEnabled true')) {
        $Gradle = $Gradle.Replace(
            'defaultConfig {',
            "defaultConfig {`r`n        multiDexEnabled true"
        )
    }
    if (-not $Gradle.Contains("coreLibraryDesugaring '")) {
        $Gradle += @"

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
"@
    }
    Save-TextFile $GroovyGradle $Gradle
    Write-Host 'Enabled Android core-library desugaring.'
}

$KeepDirectory = Join-Path $ProjectRoot 'android/app/src/main/res/raw'
if (Test-Path (Join-Path $ProjectRoot 'android')) {
    [System.IO.Directory]::CreateDirectory($KeepDirectory) | Out-Null
    $KeepFile = Join-Path $KeepDirectory 'keep.xml'
    $KeepXml = @"
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@mipmap/ic_launcher" />
"@
    Save-TextFile $KeepFile $KeepXml
}

$InfoPlist = Join-Path $ProjectRoot 'ios/Runner/Info.plist'
if (Test-Path $InfoPlist) {
    $Plist = [System.IO.File]::ReadAllText($InfoPlist)
    if (-not $Plist.Contains('io.gahunda.app')) {
        $UrlType = @"
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>io.gahunda.app</string>
			</array>
		</dict>
	</array>
"@
        $Plist = Insert-BeforeFirst $Plist '</dict>' $UrlType
        Save-TextFile $InfoPlist $Plist
    }

    $AppDelegate = Join-Path $ProjectRoot 'ios/Runner/AppDelegate.swift'
    if (Test-Path $AppDelegate) {
        $Swift = [System.IO.File]::ReadAllText($AppDelegate)
        if (-not $Swift.Contains('import UserNotifications')) {
            $Swift = $Swift.Replace('import Flutter', "import Flutter`nimport UserNotifications")
        }
        if (-not $Swift.Contains('UNUserNotificationCenter.current().delegate')) {
            $Swift = $Swift.Replace(
                'GeneratedPluginRegistrant.register(with: self)',
                "UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate`n    GeneratedPluginRegistrant.register(with: self)"
            )
        }
        Save-TextFile $AppDelegate $Swift
    }
    Write-Host 'Configured iOS notification foreground delivery and auth deep link.'
}

$WindowsMain = Join-Path $ProjectRoot 'windows/runner/main.cpp'
if (Test-Path $WindowsMain) {
    $MainCpp = [System.IO.File]::ReadAllText($WindowsMain)
    $MainCpp = $MainCpp.Replace('L"gahunda"', 'L"Gahunda"')
    Save-TextFile $WindowsMain $MainCpp
}
$WindowsResources = Join-Path $ProjectRoot 'windows/runner/Runner.rc'
if (Test-Path $WindowsResources) {
    $RunnerRc = [System.IO.File]::ReadAllText($WindowsResources)
    $RunnerRc = $RunnerRc.Replace('"gahunda"', '"Gahunda"')
    Save-TextFile $WindowsResources $RunnerRc
}

Write-Host 'Gahunda platform configuration is complete.' -ForegroundColor Green
