param(
    [string]$NgrokApiUrl = "http://127.0.0.1:4040/api/tunnels",
    [string]$FlutterProjectPath = "mobile",
    [string]$OutputApkPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobilePath = Join-Path $repoRoot $FlutterProjectPath

if (-not (Test-Path -LiteralPath $mobilePath)) {
    throw "Flutter project path not found: $mobilePath"
}

try {
    $tunnelResponse = Invoke-RestMethod -Uri $NgrokApiUrl -Method Get
} catch {
    throw "Unable to read ngrok tunnels from $NgrokApiUrl. Make sure ngrok is running and its local web interface is enabled."
}

$httpsTunnel = $tunnelResponse.tunnels |
    Where-Object { $_.public_url -like "https://*" } |
    Select-Object -First 1

if (-not $httpsTunnel) {
    throw "No HTTPS ngrok tunnel found at $NgrokApiUrl."
}

$apiBaseUrl = $httpsTunnel.public_url.TrimEnd("/")
if (-not $apiBaseUrl.EndsWith("/api")) {
    $apiBaseUrl = "$apiBaseUrl/api"
}

Write-Host "Building GawaGo APK with API base URL: $apiBaseUrl"

Push-Location $mobilePath
try {
    flutter build apk --dart-define="GAWAGO_API_BASE_URL=$apiBaseUrl"
} finally {
    Pop-Location
}

$builtApk = Join-Path $mobilePath "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path -LiteralPath $builtApk)) {
    throw "Flutter build finished but APK was not found at $builtApk"
}

if ($OutputApkPath.Trim()) {
    $resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputApkPath)) {
        $OutputApkPath
    } else {
        Join-Path $repoRoot $OutputApkPath
    }
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    Copy-Item -LiteralPath $builtApk -Destination $resolvedOutput -Force
    Write-Host "Copied APK to: $resolvedOutput"
} else {
    Write-Host "APK ready at: $builtApk"
}
