[CmdletBinding()]
param(
    [ValidateSet('full', 'incremental')]
    [string]$Mode = 'incremental'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runnerPath = Join-Path $projectRoot '03_scripts\etl\run_pipeline.py'
$logDirectory = Join-Path $projectRoot 'logs'
$logPath = Join-Path $logDirectory ("pipeline-{0}-{1}.log" -f $Mode, (Get-Date -Format 'yyyyMMdd-HHmmss'))

if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "Pipeline runner is missing: $runnerPath"
}
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$python = Get-Command 'py' -ErrorAction SilentlyContinue
if ($null -ne $python) {
    $pythonArguments = @('-3', $runnerPath, '--mode', $Mode)
} else {
    $python = Get-Command 'python' -ErrorAction Stop
    $pythonArguments = @($runnerPath, '--mode', $Mode)
}

Write-Output "Starting SQL warehouse pipeline in $Mode mode."
$output = & $python.Source @pythonArguments 2>&1
$runnerExitCode = $LASTEXITCODE
$output | Tee-Object -FilePath $logPath
Write-Output "Pipeline log: $logPath"
exit $runnerExitCode
