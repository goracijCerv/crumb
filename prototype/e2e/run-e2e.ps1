# Prueba e2e del prototipo con tui-test: abre un shell real, carga el prototipo y lo usa con teclado real.
# Uso:  .\run-e2e.ps1 -Shell powershell|pwsh|bash
# Todo usa carpetas temporales, incluido el historial global: no toca tu historial real.
param(
    [ValidateSet('powershell', 'pwsh', 'bash')][string]$Shell = 'powershell',
    [string]$PwshPath = "$env:LOCALAPPDATA\crumb-dev\pwsh7\pwsh.exe",
    [string]$BashPath = 'C:\Program Files\Git\bin\bash.exe'
)
$ErrorActionPreference = 'Stop'
$tui = if (Get-Command tui-test -ErrorAction SilentlyContinue) { 'tui-test' } else { "$env:LOCALAPPDATA\Programs\tui-test\bin\tui-test.exe" }
$protoDir = (Resolve-Path "$PSScriptRoot\..").Path -replace '\\', '/'

$T = Join-Path $env:LOCALAPPDATA ("crumb-dev\e2e-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory -Force "$T\demo\proyecto\.git", "$T\demo\proyecto\sub", "$T\demo\otra\.git", "$T\crumb"
$Tf = $T -replace '\\', '/'
$globalHist = "$Tf/global-history.txt"

# Cada shell arranca ya con el prototipo cargado y el historial global apuntando a un archivo temporal.
switch ($Shell) {
    'bash' {
        $clear = 'clear'
        "HISTFILE='$globalHist'`nsource '$protoDir/crumb-proto.sh'`n" | Set-Content "$T\rc.sh" -NoNewline -Encoding ascii
        $cmd = @($BashPath, '--rcfile', "$Tf/rc.sh", '-i')
    }
    default {
        $clear = 'cls'
        $exe = if ($Shell -eq 'pwsh') { $PwshPath } else { 'powershell.exe' }
        $init = "Set-PSReadLineOption -HistorySavePath '$globalHist'; Set-ExecutionPolicy -Scope Process Bypass -Force; . '$protoDir/crumb-proto.ps1'"
        $cmd = @($exe, '-NoProfile', '-NoLogo', '-NoExit', '-Command', $init)
    }
}

$session = "crumb-e2e-$Shell"
# CRUMB_E2E_TRACE=<archivo> registra cada llamada a tui-test (sirve para ver dónde se cuelga).
function Tui { if ($env:CRUMB_E2E_TRACE) { Add-Content $env:CRUMB_E2E_TRACE "$(Get-Date -f HH:mm:ss.fff) $args" }; & $tui --session $session @args; if ($LASTEXITCODE -ne 0) { throw "tui-test fallo ($LASTEXITCODE): $args" } }
# 'submit' espera marcadores de prompt que no hay mientras la pregunta bloquea: se escribe y se pulsa Enter.
# En Windows PowerShell 5.1 las comillas dobles dentro de argumentos a programas externos se pierden: usar comillas simples.
function Send($text) { Tui type $text; Tui key press Enter; Start-Sleep -Milliseconds 500 }
function Up($n) { foreach ($i in 1..$n) { Tui key press Up; Start-Sleep -Milliseconds 300 } }
function Step($m) { Write-Host "  - $m" }

$ok = $false
try {
    Write-Host "[$Shell] $T"
    Tui run --no-wait-ready --cwd "$T\demo" --env "CRUMB_HOME=$Tf/crumb" --env 'CRUMB_ANSWER=' --cols 120 --rows 30 -- @cmd | Out-Null
    Start-Sleep -Seconds 3
    Tui wait idle | Out-Null

    Step 'fuera de un proyecto no pregunta'
    Tui expect text 'Primera vez' --not --timeout 1500

    Step 'en un proyecto pregunta con 3 opciones'
    Send 'cd proyecto'
    Tui expect text '3) por proyecto' --timeout 8000
    Send '3'
    Send 'echo uno'

    Step 'subcarpeta: no repregunta y flecha arriba trae el historial del proyecto'
    Send 'cd sub'
    Send $clear
    Up 3   # clear, cd sub, echo uno
    Tui expect text 'echo uno' --timeout 5000
    Tui expect text 'Primera vez' --not --timeout 1000
    Tui key press Ctrl+C
    Start-Sleep -Milliseconds 400

    Step 'otro proyecto en modo carpeta: historial propio'
    Send 'cd ../../otra'
    Tui expect text 'Primera vez' --timeout 8000
    Send '2'
    Send $clear
    Up 3
    Tui expect text 'echo uno' --not --timeout 1000
    Tui key press Ctrl+C
    Start-Sleep -Milliseconds 400

    Step 'volver al proyecto: no pregunta y recupera su historial'
    Send 'cd ../proyecto'
    Send $clear
    Up 5   # clear, cd ../../otra, clear, cd sub, echo uno
    Tui expect text 'echo uno' --timeout 5000
    Tui expect text 'Primera vez' --not --timeout 1000
    Tui key press Ctrl+C
    Start-Sleep -Milliseconds 400

    Step 'comando con espacio inicial no se guarda'
    Send ' echo secreto'
    Send $clear
    Up 2
    Tui expect text 'secreto' --not --timeout 1000
    Tui key press Ctrl+C
    Start-Sleep -Milliseconds 400

    Tui screenshot -o "$PSScriptRoot\e2e-$Shell.svg" | Out-Null
    $ok = $true
}
catch {
    Write-Host "FALLO: $_"
    Write-Host '--- pantalla ---'
    & $tui --session $session text
}
finally {
    & $tui --session $session close 2>$null | Out-Null
}

if ($ok) {
    Step 'archivos: el del proyecto tiene echo uno y ninguno tiene secreto'
    $files = Get-ChildItem "$T\crumb\histories" -File
    $proj = $files | Where-Object Name -like 'proyecto-*'
    $all = (@($files.FullName) + "$T\global-history.txt") | Where-Object { Test-Path $_ }
    if (-not ($proj -and (Select-String -LiteralPath $proj.FullName -SimpleMatch 'echo uno' -Quiet))) { Write-Host 'FALLO: el archivo del proyecto no tiene echo uno'; $ok = $false }
    if (Select-String -LiteralPath $all -SimpleMatch 'secreto' -Quiet) { Write-Host 'FALLO: se guardo un comando secreto'; $ok = $false }
}

if ($ok) { Write-Host "[$Shell] OK"; exit 0 } else { Write-Host "[$Shell] FALLO"; exit 1 }
