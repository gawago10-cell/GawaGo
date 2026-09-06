param(
  [ValidateRange(48, 720)]
  [int]$AfterHours = 72
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$backendPath = Join-Path $projectRoot 'backend'
$pythonPath = (Get-Command python -ErrorAction Stop).Source
$taskName = 'GawaGo Assign Default Worker Ratings'
$taskCommand = 'cmd.exe /c "cd /d ""{0}"" && ""{1}"" manage.py assign_default_worker_ratings --after-hours {2}"' -f $backendPath, $pythonPath, $AfterHours

schtasks /Create /TN $taskName /TR $taskCommand /SC HOURLY /MO 1 /F /RL LIMITED /ST 00:00 | Out-Host
Write-Host "Installed '$taskName'. It runs hourly and assigns the default rating only after $AfterHours hours."
