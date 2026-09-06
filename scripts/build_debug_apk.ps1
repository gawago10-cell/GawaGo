param(
  [string]$ApiBaseUrl = 'https://sustainer-retinal-coleslaw.ngrok-free.dev/api',
  [string]$LogPath = (Join-Path $PSScriptRoot 'build_debug_apk.log')
)

$ErrorActionPreference = 'Stop'

$projectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'mobile'
$flutterBat = 'C:\Users\HUAWEI\development\flutter\bin\flutter.bat'

$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

if (Test-Path $LogPath) {
  Remove-Item $LogPath -Force
}

$null = New-Item -ItemType File -Path $LogPath -Force
Add-Content -Path $LogPath -Value "Starting debug APK build at $(Get-Date -Format o)"
Add-Content -Path $LogPath -Value "Project root: $projectRoot"
Add-Content -Path $LogPath -Value "Flutter path: $flutterBat"

$buildArgs = @(
  'build'
  'apk'
  '--debug'
  '--no-pub'
  '-v'
  "--dart-define=GAWAGO_API_BASE_URL=$ApiBaseUrl"
)

Push-Location $projectRoot
try {
  Add-Content -Path $LogPath -Value "Invoking flutter build..."
  & $flutterBat @buildArgs 2>&1 | Tee-Object -FilePath $LogPath
  Add-Content -Path $LogPath -Value "Flutter exit code: $LASTEXITCODE"
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
