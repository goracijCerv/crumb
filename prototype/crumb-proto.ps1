# Prototipo de crumb para PowerShell. Uso: . .\crumb-proto.ps1
# Cambia el historial de PSReadLine segun la carpeta/proyecto. Sin Go, solo para validar el enfoque.

$script:CrumbHome = if ($env:CRUMB_HOME) { $env:CRUMB_HOME } else { Join-Path $HOME '.crumb-proto' }
$script:CrumbMarkers = '.git', '.crumb', 'package.json', 'go.mod', 'Cargo.toml', 'pyproject.toml'
$script:CrumbGlobal = (Get-PSReadLineOption).HistorySavePath
$script:CrumbLastPwd = $null
$script:CrumbReadLineReady = $false
New-Item -ItemType Directory -Force -Path (Join-Path $script:CrumbHome 'histories') | Out-Null

function Get-CrumbProjectRoot {
    $d = (Get-Location).ProviderPath
    while ($d) {
        if ($d -eq $HOME) { return $null }
        foreach ($m in $script:CrumbMarkers) {
            if (Test-Path -LiteralPath (Join-Path $d $m)) { return $d }
        }
        $parent = Split-Path $d -Parent
        if (-not $parent -or $parent -eq $d) { return $null }
        $d = $parent
    }
    $null
}

function Get-CrumbHistoryPath([string]$Key) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Key.ToLowerInvariant()))
    $hash = -join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') })
    $name = (Split-Path $Key -Leaf) -replace '[^\w\.-]', '_'
    Join-Path $script:CrumbHome "histories\$name-$hash.pwsh.txt"
}

function Get-CrumbChoice([string]$Key) {
    $f = Join-Path $script:CrumbHome 'choices-pwsh.tsv'
    if (-not (Test-Path $f)) { return $null }
    $mode = $null
    foreach ($line in Get-Content $f) {
        $p = $line -split "`t"
        if ($p[0] -eq $Key) { $mode = $p[1] }
    }
    $mode
}

function Read-CrumbAnswer([string]$Key, [bool]$HasProject) {
    $ans = $env:CRUMB_ANSWER
    if (-not $ans) {
        Write-Host "`n[crumb] Primera vez en: $Key"
        $opts = '  1) global   2) por carpeta'
        if ($HasProject) { $opts += '   3) por proyecto' }
        Write-Host $opts
        $ans = Read-Host '  Eleccion [1]'
    }
    switch ($ans) {
        { $_ -in '2', 'folder' }  { 'folder' }
        { $_ -in '3', 'project' } { if ($HasProject) { 'project' } else { 'folder' } }
        default                   { 'global' }
    }
}

function Resolve-CrumbHistory {
    $root = Get-CrumbProjectRoot
    $key = if ($root) { $root } else { (Get-Location).ProviderPath }
    $mode = Get-CrumbChoice $key
    # Fuera de un proyecto no se pregunta: se usa el global salvo eleccion guardada.
    if (-not $mode -and -not $root) { $mode = 'global' }
    elseif (-not $mode) {
        $mode = Read-CrumbAnswer $key $true
        Add-Content -Path (Join-Path $script:CrumbHome 'choices-pwsh.tsv') -Value "$key`t$mode"
    }
    switch ($mode) {
        'project' { Get-CrumbHistoryPath $key }
        'folder'  { Get-CrumbHistoryPath (Get-Location).ProviderPath }
        default   { $script:CrumbGlobal }
    }
}

# Une las lineas de un comando multilinea (PSReadLine las guarda con ` al final).
function Read-CrumbHistoryFile([string]$Path) {
    $acc = $null
    foreach ($line in [IO.File]::ReadLines($Path)) {
        if ($null -ne $acc) { $line = "$acc`n$line" }
        if ($line.EndsWith('`')) { $acc = $line.Substring(0, $line.Length - 1) }
        else { $acc = $null; $line }
    }
}

function Switch-CrumbHistory {
    $cwd = (Get-Location).ProviderPath
    if ($cwd -eq $script:CrumbLastPwd) { return }
    $script:CrumbLastPwd = $cwd
    $f = Resolve-CrumbHistory
    if ($f -eq (Get-PSReadLineOption).HistorySavePath) { return }

    # En el primer prompt PSReadLine aun no leyo su historial: basta con cambiar la ruta
    # y el propio PSReadLine cargara ese archivo al iniciar ReadLine.
    if (-not $script:CrumbReadLineReady) {
        $script:CrumbReadLineReady = $true
        Set-PSReadLineOption -HistorySavePath $f
        return
    }

    $style = (Get-PSReadLineOption).HistorySaveStyle
    # Durante la carga no se debe escribir nada en el archivo nuevo.
    Set-PSReadLineOption -HistorySaveStyle SaveNothing
    Set-PSReadLineOption -HistorySavePath $f
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
    if (Test-Path -LiteralPath $f) {
        foreach ($cmd in Read-CrumbHistoryFile $f) {
            [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($cmd)
        }
    }
    Set-PSReadLineOption -HistorySaveStyle $style
}

# No guardar comandos que empiezan con espacio.
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)
    if ($line.StartsWith(' ')) { return [Microsoft.PowerShell.AddToHistoryOption]::SkipAdding }
    [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
}

# Envuelve el prompt actual.
if (-not $script:CrumbOriginalPrompt) {
    $script:CrumbOriginalPrompt = (Get-Command prompt -CommandType Function).ScriptBlock
}
function global:prompt {
    try { Switch-CrumbHistory } catch { Write-Warning "crumb: $_" }
    & $script:CrumbOriginalPrompt
}

