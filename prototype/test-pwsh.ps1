# Prueba del prototipo PowerShell en una consola interactiva real (PSReadLine activo).
# Se ejecuta con:  .\run-test-pwsh.ps1
# Los pasos corren desde el evento OnIdle, es decir, con ReadLine ya iniciado como en uso normal.
$ErrorActionPreference = 'Stop'
$global:T = Join-Path $env:TEMP ("crumb-test-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory -Force "$T\projA\.git", "$T\projA\sub", "$T\projB\.git", "$T\plain", "$T\crumb"
$global:TestDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:TestLog = Join-Path $global:TestDir 'test-pwsh.log'
$global:out = New-Object System.Collections.Generic.List[string]
function global:Log($m) { $global:out.Add([string]$m) }
# Lee la lista interna de historial de PSReadLine (no hay API publica para leerla).
function Get-MemHistory {
    $t = [Microsoft.PowerShell.PSConsoleReadLine]
    $s = $t.GetField('_singleton', 'NonPublic,Static').GetValue($null)
    $h = $t.GetField('_history', 'NonPublic,Instance').GetValue($s)
    if ($h.Count -eq 0) { return @() }; @(0..($h.Count - 1) | ForEach-Object { ($h[$_].CommandLine) -replace "`n", '\n' })
}

function global:Invoke-CrumbTest {
try {
    Log "PSReadLine: $((Get-Module PSReadLine).Version)  PS: $($PSVersionTable.PSVersion)"
    $gfile = "$T\crumb\global-original.txt"
    Set-PSReadLineOption -HistorySavePath $gfile
    $global:CrumbGlobal = $gfile

    # --- Experimento 1: AddToHistory escribe al archivo con SaveIncrementally?
    $x = "$T\exp1.txt"
    Set-PSReadLineOption -HistorySavePath $x
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory('exp-uno')
    Log "Exp1 archivo tras AddToHistory (SaveIncrementally): $(if (Test-Path $x) { (Get-Content $x) -join '|' } else { '(no existe)' })"
    Set-PSReadLineOption -HistorySavePath $gfile
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()

    # --- Flujo real: sembrar archivos de historial y cambiar de carpeta
    $env:CRUMB_ANSWER = '3'; Set-Location "$T\projA"; prompt | Out-Null
    $fA = (Get-PSReadLineOption).HistorySavePath
    Log "projA -> $(Split-Path $fA -Leaf)"
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory('echo A1')
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory("multi `` `n linea")
    Log "projA memoria: $((Get-MemHistory) -join ' | ')"
    Log "projA archivo: $(if (Test-Path $fA) { (Get-Content $fA) -join ' | ' } else { '(no existe)' })"

    Set-Location "$T\projA\sub"; prompt | Out-Null
    Log "projA\sub usa el mismo archivo: $((Get-PSReadLineOption).HistorySavePath -eq $fA)"

    $env:CRUMB_ANSWER = '2'; Set-Location "$T\projB"; prompt | Out-Null
    $fB = (Get-PSReadLineOption).HistorySavePath
    Log "projB -> $(Split-Path $fB -Leaf)  memoria: [$((Get-MemHistory) -join ' | ')]"
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory('echo B1')

    $env:CRUMB_ANSWER = '1'; Set-Location "$T\plain"; prompt | Out-Null
    Log "plain -> global: $((Get-PSReadLineOption).HistorySavePath -eq $gfile)"

    # Volver a projA: debe recargar lo que hubo en projA desde el archivo
    Set-Location "$T\projA"; prompt | Out-Null
    Log "vuelta a projA memoria: [$((Get-MemHistory) -join ' | ')]"
    Log "vuelta a projA archivo: $(if (Test-Path $fA) { (Get-Content $fA) -join ' | ' } else { '(no existe)' })"

    # Handler: comando con espacio inicial
    $opt = (Get-PSReadLineOption).AddToHistoryHandler
    Log "Handler ' secreto' -> $($opt.Invoke(' secreto'))   'normal' -> $($opt.Invoke('normal'))"
    Log 'RESULTADO: terminado sin errores'
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Log $_.ScriptStackTrace
}
$global:out | Set-Content $global:TestLog -Encoding UTF8
}

$global:CrumbTestDone = $false
Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    if (-not $global:CrumbTestDone) {
        $global:CrumbTestDone = $true
        try { Invoke-CrumbTest } catch { $global:out.Add("FATAL: $_"); $global:out | Set-Content $global:TestLog -Encoding UTF8 }
        [Environment]::Exit(0)
    }
} | Out-Null




