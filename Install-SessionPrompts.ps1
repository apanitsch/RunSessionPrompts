#Requires -Version 7.0
# Ver la nota de encoding de Run-SessionPrompts.ps1: este archivo tambien se mantiene en ASCII puro.

<#
.SYNOPSIS
    Instala (o actualiza) Run-SessionPrompts.ps1 y sus plantillas en otro repositorio.

.DESCRIPTION
    Copia el runner, las plantillas y -- la primera vez -- el series-estado.txt y el
    session-prompts.config.json de ejemplo, a la carpeta de series del repo destino
    (por defecto docs/session-prompts, o Docs/session-prompts si el repo ya usa esa).

    Deja un archivo .session-prompts-version con la version instalada y el hash del runner.
    Con eso, una actualizacion posterior puede distinguir tres situaciones:
      - el runner del destino es identico al que instalamos  -> se pisa sin preguntar,
      - esta MODIFICADO a mano                               -> avisa y no pisa (salvo -Force),
      - no hay marca de version (instalacion vieja, copiada
        y pegada a mano)                                     -> avisa y no pisa (salvo -Force).

    Lo que NUNCA se pisa: las series (las carpetas con los prompts), el series-estado.txt y
    el session-prompts.config.json que ya existan. Ahi vive el trabajo del repo destino.

.PARAMETER Repo
    Raiz del repo destino. Default: el directorio actual.

.PARAMETER SeriesRoot
    Carpeta de series del destino. Default: la que ya exista (docs/session-prompts o
    Docs/session-prompts), o docs/session-prompts si no hay ninguna.

.PARAMETER Force
    Pisa el runner aunque este modificado a mano o no tenga marca de version. Antes de
    pisarlo deja una copia al lado, con extension .bak.

.PARAMETER WhatIf
    Dice que haria y no toca nada.

.EXAMPLE
    # Instalar en el repo donde estas parado.
    pwsh -File C:\Users\andre\source\repos\RunSessionPrompts\Install-SessionPrompts.ps1

.EXAMPLE
    # Instalar en otro repo.
    .\Install-SessionPrompts.ps1 -Repo C:\Users\andre\source\repos\MiProyecto

.EXAMPLE
    # Ver que haria una actualizacion, sin tocar nada.
    .\Install-SessionPrompts.ps1 -Repo C:\...\MiProyecto -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repo,
    [string]$SeriesRoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$origen = $PSScriptRoot
$runnerOrigen = Join-Path $origen 'Run-SessionPrompts.ps1'

if (-not (Test-Path -LiteralPath $runnerOrigen)) {
    Write-Host "No encuentro Run-SessionPrompts.ps1 al lado de este instalador." -ForegroundColor Red
    exit 1
}

# Version del runner, leida del propio script (una sola fuente de verdad).
$versionOrigen = 'desconocida'
$m = [regex]::Match((Get-Content -LiteralPath $runnerOrigen -Raw -Encoding UTF8),
                    "(?m)^\s*\`$script:RunnerVersion\s*=\s*'([^']+)'")
if ($m.Success) { $versionOrigen = $m.Groups[1].Value }

# --- Destino ---------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Repo)) { $Repo = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Repo)) {
    Write-Host "No existe el repo destino: $Repo" -ForegroundColor Red
    exit 1
}

$repoRoot = git -C $Repo rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    Write-Host "$Repo no esta dentro de un repo git." -ForegroundColor Red
    exit 1
}
$repoRoot = ([System.IO.Path]::GetFullPath($repoRoot.Trim())).TrimEnd('\')

if ([string]::IsNullOrWhiteSpace($SeriesRoot)) {
    # Respetamos la convencion que el repo destino ya tenga (algunos usan Docs/ con mayuscula).
    $SeriesRoot = $null
    foreach ($rel in @('docs/session-prompts', 'Docs/session-prompts',
                       'docs/session_prompts', 'Docs/session_prompts')) {
        $candidata = Join-Path $repoRoot $rel
        if (Test-Path -LiteralPath $candidata) { $SeriesRoot = $candidata; break }
    }
    if (-not $SeriesRoot) { $SeriesRoot = Join-Path $repoRoot 'docs/session-prompts' }
}

$esInstalacionNueva = -not (Test-Path -LiteralPath (Join-Path $SeriesRoot 'Run-SessionPrompts.ps1'))

Write-Host "Origen : $origen (version $versionOrigen)" -ForegroundColor DarkGray
Write-Host "Destino: $SeriesRoot" -ForegroundColor DarkGray
Write-Host ""

# --- Se puede pisar el runner del destino? --------------------------------
$marcaPath = Join-Path $SeriesRoot '.session-prompts-version'
$runnerDestino = Join-Path $SeriesRoot 'Run-SessionPrompts.ps1'

function Get-HashArchivo([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

$puedePisar = $true
$motivo = 'instalacion nueva'

if (-not $esInstalacionNueva) {
    if (Test-Path -LiteralPath $marcaPath) {
        $marca = Get-Content -LiteralPath $marcaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hashActual = Get-HashArchivo $runnerDestino

        if ($marca.runnerHash -eq $hashActual) {
            $motivo = "instalado por este instalador, version $($marca.version), sin modificar"
            if ($marca.version -eq $versionOrigen) { $motivo += " (ya esta en $versionOrigen)" }
        } else {
            $puedePisar = $false
            $motivo = "el runner del destino esta MODIFICADO respecto de la version $($marca.version) que se instalo"
        }
    } else {
        $puedePisar = $false
        $motivo = "hay un runner sin marca de version (copiado a mano); puede tener cambios propios del repo"
    }
}

if (-not $puedePisar -and -not $Force) {
    Write-Host "NO piso el runner: $motivo." -ForegroundColor Yellow
    Write-Host "Compara y decidi vos:" -ForegroundColor Yellow
    Write-Host "  code --diff `"$runnerDestino`" `"$runnerOrigen`"" -ForegroundColor DarkGray
    Write-Host "Cuando lo hayas mirado, corre de nuevo con -Force (deja un .bak al lado)." -ForegroundColor Yellow
    exit 2
}

if (-not $puedePisar -and $Force) {
    $bak = "$runnerDestino.bak"
    if ($PSCmdlet.ShouldProcess($bak, "guardar copia del runner actual")) {
        Copy-Item -LiteralPath $runnerDestino -Destination $bak -Force
        Write-Host "Copia del runner anterior: $bak" -ForegroundColor DarkGray
    }
}

# --- Copiar ----------------------------------------------------------------
if (-not (Test-Path -LiteralPath $SeriesRoot)) {
    if ($PSCmdlet.ShouldProcess($SeriesRoot, "crear la carpeta de series")) {
        New-Item -ItemType Directory -Path $SeriesRoot -Force | Out-Null
    }
}

if ($PSCmdlet.ShouldProcess($runnerDestino, "instalar Run-SessionPrompts.ps1 $versionOrigen ($motivo)")) {
    Copy-Item -LiteralPath $runnerOrigen -Destination $runnerDestino -Force
    Write-Host "Run-SessionPrompts.ps1 -> $versionOrigen" -ForegroundColor Green
}

# Plantillas: se actualizan siempre (son material de referencia, no trabajo del repo).
$plantillasOrigen = Join-Path $origen 'templates\_plantillas'
$plantillasDestino = Join-Path $SeriesRoot '_plantillas'
if (Test-Path -LiteralPath $plantillasOrigen) {
    if ($PSCmdlet.ShouldProcess($plantillasDestino, "actualizar las plantillas")) {
        New-Item -ItemType Directory -Path $plantillasDestino -Force | Out-Null
        # -Path, no -LiteralPath: el comodin tiene que expandirse.
        Copy-Item -Path (Join-Path $plantillasOrigen '*') -Destination $plantillasDestino -Recurse -Force
        Write-Host "_plantillas/ actualizadas" -ForegroundColor Green
    }
}

# Estos dos son del repo destino: se ponen si no estan, y no se pisan nunca.
foreach ($par in @(
    @{ Origen = 'templates\series-estado.txt';           Destino = 'series-estado.txt' },
    @{ Origen = 'templates\session-prompts.config.json'; Destino = 'session-prompts.config.json' }
)) {
    $src = Join-Path $origen $par.Origen
    $dst = Join-Path $SeriesRoot $par.Destino
    if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $dst)) {
        if ($PSCmdlet.ShouldProcess($dst, "crear")) {
            Copy-Item -LiteralPath $src -Destination $dst
            Write-Host "$($par.Destino) creado (no se vuelve a pisar)" -ForegroundColor Green
        }
    }
}

# --- Marca de version ------------------------------------------------------
if ($PSCmdlet.ShouldProcess($marcaPath, "escribir la marca de version")) {
    $marca = [pscustomobject]@{
        version     = $versionOrigen
        runnerHash  = Get-HashArchivo $runnerDestino
        instaladoEl = (Get-Date).ToString('yyyy-MM-dd')
        origen      = $origen
    }
    Set-Content -LiteralPath $marcaPath -Value ($marca | ConvertTo-Json) -Encoding UTF8
}

Write-Host ""
if ($esInstalacionNueva) {
    Write-Host "Listo. Para arrancar:" -ForegroundColor Cyan
    Write-Host "  1. Crea la carpeta de tu primera serie: $SeriesRoot\<mi-serie>\" -ForegroundColor DarkGray
    Write-Host "  2. Copia _plantillas\plantilla-session-prompt.md a <mi-serie>\01-....md y completala." -ForegroundColor DarkGray
    Write-Host "  3. pwsh -File `"$runnerDestino`"" -ForegroundColor DarkGray
} else {
    Write-Host "Actualizado a $versionOrigen. Revisa el CHANGELOG del runner por si cambio algo que uses." -ForegroundColor Cyan
}
