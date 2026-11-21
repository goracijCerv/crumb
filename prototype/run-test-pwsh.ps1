# Lanza una consola real, carga el prototipo y ejecuta la prueba.
$dir = $PSScriptRoot
$log = Join-Path $dir 'test-pwsh.log'
Remove-Item $log -ErrorAction SilentlyContinue
$env:CRUMB_ANSWER = '1'
$env:CRUMB_HOME = Join-Path $env:TEMP 'crumb-proto-run'
$cmd = ". '$dir\crumb-proto.ps1'; . '$dir\test-pwsh.ps1'"
$p = Start-Process powershell -ArgumentList '-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-Command',$cmd -PassThru
if (-not $p.WaitForExit(60000)) { $p.Kill(); 'TIMEOUT' }
Remove-Item Env:CRUMB_ANSWER, Env:CRUMB_HOME -ErrorAction SilentlyContinue
if (Test-Path $log) { Get-Content $log } else { 'sin log' }

