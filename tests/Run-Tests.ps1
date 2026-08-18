#Requires -Version 7.0
<#
.SYNOPSIS
    Suite de tests de Run-SessionPrompts.ps1. Sin dependencias: PowerShell 7 y git, nada mas.

.DESCRIPTION
    Cada caso arma un repo git de juguete en una carpeta temporal, con su raiz de series y sus
    prompts, y corre el runner de verdad contra un DOBLE de 'claude' (un .ps1 que anota en un
    log lo que recibio: argumentos y directorio de trabajo). Asi se verifica lo que el runner
    promete -- orden, modelo por sesion, texto del prompt intacto, cwd, exit codes -- sin
    lanzar ninguna sesion real.

    pwsh -File .\tests\Run-Tests.ps1

.PARAMETER KeepTemp
    No borra las carpetas temporales al terminar (para inspeccionar un caso que fallo).
#>

[CmdletBinding()]
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

$script:Runner     = Join-Path (Split-Path -Parent $PSScriptRoot) 'Run-SessionPrompts.ps1'
$script:Instalador = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-SessionPrompts.ps1'
$script:Pasados   = 0
$script:Fallados  = 0
$script:Temporales = @()

# --- Mini framework -------------------------------------------------------

function Assert-True([bool]$condicion, [string]$mensaje) {
    if (-not $condicion) { throw $mensaje }
}

function Assert-Equal($esperado, $actual, [string]$mensaje) {
    if ("$esperado" -ne "$actual") {
        throw "$mensaje`n    esperado: <$esperado>`n    obtenido: <$actual>"
    }
}

function Assert-Match([string]$patron, [string]$texto, [string]$mensaje) {
    if ($texto -notmatch $patron) {
        throw "$mensaje`n    patron no encontrado: <$patron>`n    en:`n$texto"
    }
}

function Assert-NotMatch([string]$patron, [string]$texto, [string]$mensaje) {
    if ($texto -match $patron) {
        throw "$mensaje`n    patron que NO debia aparecer: <$patron>`n    en:`n$texto"
    }
}

function Test-Case([string]$nombre, [scriptblock]$cuerpo) {
    try {
        & $cuerpo
        $script:Pasados++
        Write-Host "  OK   $nombre" -ForegroundColor Green
    } catch {
        $script:Fallados++
        Write-Host "  FALLA $nombre" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

# --- Fixture --------------------------------------------------------------

# Repo git de juguete con su raiz de series y el runner adentro, como en una instalacion real.
function New-Fixture {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $script:Temporales += $dir

    git -C $dir init -q --initial-branch=main 2>&1 | Out-Null
    git -C $dir config user.email "test@example.com"
    git -C $dir config user.name "Test"

    $seriesRoot = Join-Path $dir 'docs\session-prompts'
    New-Item -ItemType Directory -Path $seriesRoot -Force | Out-Null
    Copy-Item -LiteralPath $script:Runner -Destination $seriesRoot

    Set-Content -LiteralPath (Join-Path $dir 'README.md') -Value 'repo de prueba' -Encoding UTF8
    git -C $dir add -A 2>&1 | Out-Null
    git -C $dir commit -qm "inicial" 2>&1 | Out-Null

    # Doble de 'claude': anota una linea JSON por invocacion con lo que recibio.
    $fake = Join-Path $dir 'fake-claude.ps1'
    Set-Content -LiteralPath $fake -Encoding UTF8 -Value @'
$log = $env:FAKE_CLAUDE_LOG
$registro = [pscustomobject]@{
    Cwd       = (Get-Location).Path
    Args      = @($args)
}
Add-Content -LiteralPath $log -Value ($registro | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
if ($env:FAKE_CLAUDE_EXIT) { exit [int]$env:FAKE_CLAUDE_EXIT }
exit 0
'@

    return [pscustomobject]@{
        Repo       = $dir
        SeriesRoot = $seriesRoot
        Runner     = Join-Path $seriesRoot 'Run-SessionPrompts.ps1'
        FakeClaude = $fake
        Log        = Join-Path $dir 'fake-claude.log'
    }
}

function New-Serie($fixture, [string]$nombre, [hashtable]$prompts) {
    $dir = Join-Path $fixture.SeriesRoot $nombre
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($archivo in $prompts.Keys) {
        Set-Content -LiteralPath (Join-Path $dir $archivo) -Value $prompts[$archivo] -Encoding UTF8
    }
    return $dir
}

# Corre el runner en un pwsh hijo (asi el exit code y los Read-Host quedan aislados).
function Invoke-Runner($fixture, [string[]]$argumentos, [string]$stdin, [int]$fakeExit) {
    $env:FAKE_CLAUDE_LOG = $fixture.Log
    if ($fakeExit) { $env:FAKE_CLAUDE_EXIT = "$fakeExit" } else { Remove-Item Env:\FAKE_CLAUDE_EXIT -ErrorAction SilentlyContinue }

    $todos = @('-NoProfile', '-File', $fixture.Runner) + $argumentos

    Push-Location -LiteralPath $fixture.Repo
    try {
        if ($null -ne $stdin) {
            $salida = $stdin | & pwsh @todos 2>&1
        } else {
            $salida = & pwsh @todos 2>&1
        }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
        Remove-Item Env:\FAKE_CLAUDE_EXIT -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Salida   = ($salida | ForEach-Object { "$_" }) -join "`n"
        ExitCode = $code
    }
}

# Lo que el doble de claude registro, una entrada por sesion.
function Get-Sesiones($fixture) {
    if (-not (Test-Path -LiteralPath $fixture.Log)) { return @() }
    return @(Get-Content -LiteralPath $fixture.Log -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

# El prompt es el ultimo argumento; los flags estan antes.
function Get-ArgValue($sesion, [string]$flag) {
    $a = @($sesion.Args)
    for ($i = 0; $i -lt $a.Count - 1; $i++) {
        if ($a[$i] -eq $flag) { return $a[$i + 1] }
    }
    return $null
}

function Get-PromptArg($sesion) {
    $a = @($sesion.Args)
    return $a[$a.Count - 1]
}

# El prompt tal cual, sin el salto de linea final que Set-Content le agrega al fixture.
function Get-PromptTexto($sesion) {
    return (Get-PromptArg $sesion).TrimEnd("`r", "`n")
}

# Repo git de juguete SIN nada instalado, para probar el instalador.
function New-RepoVacio {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-inst-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $script:Temporales += $dir

    git -C $dir init -q --initial-branch=main 2>&1 | Out-Null
    git -C $dir config user.email "test@example.com"
    git -C $dir config user.name "Test"
    Set-Content -LiteralPath (Join-Path $dir 'README.md') -Value 'repo de prueba' -Encoding UTF8
    git -C $dir add -A 2>&1 | Out-Null
    git -C $dir commit -qm "inicial" 2>&1 | Out-Null
    return $dir
}

function Invoke-Instalador([string]$repo, [string[]]$argumentos) {
    $todos = @('-NoProfile', '-File', $script:Instalador, '-Repo', $repo) + $argumentos
    $salida = & pwsh @todos 2>&1
    return [pscustomobject]@{
        Salida   = ($salida | ForEach-Object { "$_" }) -join "`n"
        ExitCode = $LASTEXITCODE
    }
}

# --- Casos ----------------------------------------------------------------

Write-Host "Run-SessionPrompts -- suite de tests" -ForegroundColor Cyan
Write-Host "Runner: $script:Runner`n" -ForegroundColor DarkGray

Test-Case "-Version imprime la version y sale 0" {
    $f = New-Fixture
    $r = Invoke-Runner $f @('-Version')
    Assert-Equal 0 $r.ExitCode "exit code"
    Assert-Match 'Run-SessionPrompts \d+\.\d+\.\d+' $r.Salida "no imprimio la version"
}

Test-Case "corre los prompts en orden numerico (10 despues de 2) y con el nombre de sesion" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-orden' @{
        '01-uno.md'   = 'prompt uno'
        '02-dos.md'   = 'prompt dos'
        '10-diez.md'  = 'prompt diez'
    }
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal 3 $s.Count "cantidad de sesiones"
    Assert-Equal 'prompt uno'  (Get-PromptTexto $s[0]) "primera sesion"
    Assert-Equal 'prompt dos'  (Get-PromptTexto $s[1]) "segunda sesion"
    Assert-Equal 'prompt diez' (Get-PromptTexto $s[2]) "tercera sesion (10 va ultimo, no despues de 1)"
    Assert-Equal 'serie-orden/01-uno' (Get-ArgValue $s[0] '--name') "nombre de sesion"
    Assert-Equal 'serie-orden/01-uno' (Get-ArgValue $s[0] '--rc') "nombre de Remote Control"
}

Test-Case "las sesiones corren paradas en la raiz del repo, no en la carpeta de series" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-cwd' @{ '01-uno.md' = 'x' }
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    $esperado = (Get-Item -LiteralPath $f.Repo).FullName
    Assert-Equal $esperado (Get-Item -LiteralPath $s[0].Cwd).FullName "directorio de trabajo"
}

Test-Case "-StartFrom saltea los anteriores y, si llega al ultimo, marca la serie terminada" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-desde' @{
        '01-uno.md'  = 'uno'
        '02-dos.md'  = 'dos'
        '03-tres.md' = 'tres'
    }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Encoding UTF8 -Value @(
        '# estado',
        'pendiente 1 serie-desde'
    )

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '2', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal 2 $s.Count "cantidad de sesiones"
    Assert-Equal 'dos' (Get-PromptTexto $s[0]) "arranca en el 02"

    $estado = Get-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Raw -Encoding UTF8
    Assert-Match 'terminada - serie-desde' $estado "una corrida que llego al ultimo prompt marca terminada aunque haya empezado por el 02"
}

Test-Case "una corrida que no llega al ultimo prompt deja la serie pendiente" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-parcial' @{
        '01-uno.md' = 'uno'
        '02-dos.md' = 'dos'
    }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Encoding UTF8 -Value @('pendiente 1 serie-parcial')

    # Solo el 01: se logra borrando el 02 despues de armar el plan no se puede, asi que
    # corremos una serie de dos y cortamos con un exit code != 0 en la primera.
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude) $null 7
    Assert-Equal 7 $r.ExitCode "el exit code de la sesion se propaga"

    $s = Get-Sesiones $f
    Assert-Equal 1 $s.Count "corta en la primera que falla"

    $estado = Get-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Raw -Encoding UTF8
    Assert-Match 'pendiente 1 serie-parcial' $estado "la serie sigue pendiente"
}

Test-Case "el texto del prompt llega intacto: comillas, acentos y backslashes" {
    $f = New-Fixture
    $texto = 'El legacy loguea "Session ended" y la ruta es C:\temp\x. Acentos: sesion terminada, anio.'
    $serie = New-Serie $f 'serie-comillas' @{ '01-cita.md' = $texto }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    $recibido = (Get-PromptArg $s[0]).TrimEnd("`r", "`n")
    Assert-Equal $texto $recibido "el prompt tiene que llegar sin escapado extra"
    Assert-NotMatch '\\"' $recibido "no debe llegar con las comillas escapadas"
}

Test-Case "modelo-sugerido menor que el base baja el modelo de esa sesion, sin preguntar" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-modelo' @{
        '01-juzga.md'   = 'sin marca'
        '02-escribe.md' = "<!-- modelo-sugerido: sonnet -->`n`nescribe nomas"
    }
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal 'claude-opus-5'   (Get-ArgValue $s[0] '--model') "la sesion sin marca usa el modelo base"
    Assert-Equal 'claude-sonnet-5' (Get-ArgValue $s[1] '--model') "la sesion con marca menor baja a Sonnet"
    Assert-Match 'baja desde Opus 5' $r.Salida "el plan tiene que decir por que bajo"
}

Test-Case "modelo-sugerido mayor que el base pregunta, y la respuesta por defecto usa el sugerido" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-sube' @{
        '01-juzga.md' = "<!-- modelo-sugerido: opus -->`n`njuzga"
    }
    # Enter en la pregunta del modelo (= usar el sugerido).
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'sonnet', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude) "`n"
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'sugiere Opus 5 y la corrida esta en Sonnet 5' $r.Salida "tiene que avisar antes de arrancar"

    $s = Get-Sesiones $f
    Assert-Equal 'claude-opus-5' (Get-ArgValue $s[0] '--model') "con Enter usa el sugerido"
}

Test-Case "los flags de permisos y effort van en todas las sesiones" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-flags' @{ '01-uno.md' = 'x' }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'max', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    $s = Get-Sesiones $f
    Assert-Equal 'max' (Get-ArgValue $s[0] '--effort') "effort"
    Assert-Equal 'acceptEdits' (Get-ArgValue $s[0] '--permission-mode') "por defecto acceptEdits"

    Remove-Item -LiteralPath $f.Log
    $r2 = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-FullAuto', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r2.ExitCode "exit code (FullAuto). Salida:`n$($r2.Salida)"
    $s2 = Get-Sesiones $f
    Assert-True (@($s2[0].Args) -contains '--dangerously-skip-permissions') "-FullAuto tiene que pasar --dangerously-skip-permissions"
    Assert-True (-not (@($s2[0].Args) -contains '--permission-mode')) "-FullAuto no lleva --permission-mode"
}

Test-Case "el menu lista solo las series pendientes, en el orden propuesto, y saltea las que empiezan con _" {
    $f = New-Fixture
    New-Serie $f 'zeta-pendiente'   @{ '01-a.md' = 'a' } | Out-Null
    New-Serie $f 'alfa-pendiente'   @{ '01-a.md' = 'a' } | Out-Null
    New-Serie $f 'vieja-terminada'  @{ '01-a.md' = 'a' } | Out-Null
    New-Serie $f '_serie-de-ejemplo' @{ '01-a.md' = 'a' } | Out-Null

    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Encoding UTF8 -Value @(
        '# estado',
        'pendiente 1 zeta-pendiente',
        'pendiente 2 alfa-pendiente',
        'terminada - vieja-terminada'
    )

    # Elegimos la [1] del menu, Enter para empezar desde el primero.
    $r = Invoke-Runner $f @('-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude) "1`n`n"
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    Assert-Match '\[1\] zeta-pendiente' $r.Salida "la [1] es la de orden 1, no la alfabeticamente primera"
    Assert-Match '\[2\] alfa-pendiente' $r.Salida "la [2] es la de orden 2"
    Assert-NotMatch 'vieja-terminada' $r.Salida "las terminadas no se listan"
    Assert-NotMatch '_serie-de-ejemplo' $r.Salida "las carpetas con _ no son series"
    Assert-Match '1 terminadas, ocultas' $r.Salida "avisa cuantas oculto"

    $s = Get-Sesiones $f
    Assert-Equal 'zeta-pendiente/01-a' (Get-ArgValue $s[0] '--name') "corrio la serie elegida"
}

Test-Case "-Todas muestra tambien las terminadas" {
    $f = New-Fixture
    New-Serie $f 'vieja-terminada' @{ '01-a.md' = 'a' } | Out-Null
    New-Serie $f 'nueva' @{ '01-a.md' = 'a' } | Out-Null
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Encoding UTF8 -Value @(
        'terminada - vieja-terminada',
        'pendiente 1 nueva'
    )

    $r = Invoke-Runner $f @('-Todas', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude, '-DryRun') "1`n`n"
    Assert-Match 'vieja-terminada' $r.Salida "-Todas tiene que listar las terminadas"
}

Test-Case "-DryRun imprime el plan y no lanza ninguna sesion" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-seca' @{ '01-uno.md' = 'uno'; '02-dos.md' = 'dos' }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude, '-DryRun')
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'no se lanza ninguna sesion' $r.Salida "tiene que decir que no lanza nada"
    Assert-Equal 0 (Get-Sesiones $f).Count "no puede haber corrido ninguna sesion"
}

Test-Case "un prompt mas largo que el maximo corta con error, no se trunca en silencio" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-larga' @{ '01-gigante.md' = ('x' * 31000) }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "tiene que fallar"
    Assert-Match 'no entra en la linea de comandos' $r.Salida "con un mensaje que diga que hacer"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza la sesion truncada"
}

Test-Case "la configuracion del repo fija modelo y effort sin preguntar nada" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-config' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 -Value @'
{
  "model": "sonnet",
  "effort": "low",
  "fullAuto": true
}
'@

    # Sin -Model ni -Effort: si la config no se leyera, el script se quedaria esperando el menu.
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal 'claude-sonnet-5' (Get-ArgValue $s[0] '--model') "modelo de la configuracion"
    Assert-Equal 'low' (Get-ArgValue $s[0] '--effort') "effort de la configuracion"
    Assert-True (@($s[0].Args) -contains '--dangerously-skip-permissions') "fullAuto de la configuracion"
}

Test-Case "un parametro explicito le gana a la configuracion" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-config2' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 -Value '{ "model": "sonnet", "effort": "low" }'

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    $s = Get-Sesiones $f
    Assert-Equal 'claude-opus-5' (Get-ArgValue $s[0] '--model') "el parametro manda"
    Assert-Equal 'low' (Get-ArgValue $s[0] '--effort') "lo que no se paso sale de la configuracion"
}

Test-Case "-Worktree crea el worktree de la serie y corre las sesiones adentro" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-aislada' @{ '01-uno.md' = 'uno' }
    git -C $f.Repo add -A 2>&1 | Out-Null
    git -C $f.Repo commit -qm "serie" 2>&1 | Out-Null

    $wtRoot = Join-Path (Split-Path -Parent $f.Repo) ("wt-" + (Split-Path -Leaf $f.Repo))
    $script:Temporales += $wtRoot

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high',
                            '-Worktree', '-WorktreeRoot', $wtRoot, '-BaseBranch', 'main', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $esperado = Join-Path $wtRoot 'serie-aislada'
    Assert-True (Test-Path -LiteralPath $esperado) "el worktree tiene que existir"

    $s = Get-Sesiones $f
    Assert-Equal (Get-Item -LiteralPath $esperado).FullName (Get-Item -LiteralPath $s[0].Cwd).FullName "la sesion corre parada en el worktree"

    $ramas = git -C $f.Repo branch --list 'sesiones/serie-aislada'
    Assert-Match 'sesiones/serie-aislada' ($ramas -join "`n") "tiene que existir la rama de la serie"

    # Segunda corrida: reutiliza el worktree en vez de fallar.
    Remove-Item -LiteralPath $f.Log
    $r2 = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high',
                             '-Worktree', '-WorktreeRoot', $wtRoot, '-BaseBranch', 'main', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r2.ExitCode "segunda corrida. Salida:`n$($r2.Salida)"
    Assert-Match 'Worktree existente, lo reutilizo' $r2.Salida "tiene que reutilizarlo"

    git -C $f.Repo worktree remove --force $esperado 2>&1 | Out-Null
}

Test-Case "-Worktree se niega a crear el worktree adentro del checkout principal" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-adentro' @{ '01-uno.md' = 'uno' }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high',
                            '-Worktree', '-WorktreeRoot', (Join-Path $f.Repo 'wt'), '-BaseBranch', 'main', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "tiene que fallar"
    Assert-Match 'caeria DENTRO del checkout principal' $r.Salida "con el motivo"
}

Test-Case "una carpeta sin prompts numerados no es una serie ejecutable" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-vacia' @{ 'README.md' = 'no soy un prompt'; 'ESTADO.md' = 'tampoco' }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "tiene que fallar"
    Assert-Match 'No hay prompts .md para ejecutar' $r.Salida "con el motivo"
}

Test-Case "afuera de un repo git corta con un error claro" {
    $f = New-Fixture
    $suelto = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-suelto-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $suelto 'serie') -Force | Out-Null
    $script:Temporales += $suelto
    Set-Content -LiteralPath (Join-Path $suelto 'serie\01-uno.md') -Value 'x' -Encoding UTF8

    $r = Invoke-Runner $f @('-PromptsPath', (Join-Path $suelto 'serie'), '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "tiene que fallar"
    Assert-Match 'no esta dentro de un repo git' $r.Salida "con el motivo"
}

Test-Case "el instalador deja el runner, las plantillas y los moldes en un repo limpio" {
    $repo = New-RepoVacio
    $r = Invoke-Instalador $repo @()
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $destino = Join-Path $repo 'docs\session-prompts'
    foreach ($archivo in @('Run-SessionPrompts.ps1', 'series-estado.txt', 'session-prompts.config.json',
                           '.session-prompts-version', '_plantillas\plantilla-session-prompt.md')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $destino $archivo)) "falta $archivo"
    }

    $marca = Get-Content -LiteralPath (Join-Path $destino '.session-prompts-version') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Match '^\d+\.\d+\.\d+$' $marca.version "la marca tiene que guardar la version"
}

Test-Case "el instalador respeta la carpeta Docs/ si el repo ya usa esa convencion" {
    $repo = New-RepoVacio
    New-Item -ItemType Directory -Path (Join-Path $repo 'Docs\session-prompts') -Force | Out-Null

    $r = Invoke-Instalador $repo @()
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'Docs\session-prompts\Run-SessionPrompts.ps1')) "tenia que instalar en Docs/"

    # En Windows 'docs' y 'Docs' son la MISMA carpeta, asi que Test-Path no distingue: lo que
    # se verifica es que no haya nacido una segunda carpeta con el otro nombre.
    $carpetas = @(Get-ChildItem -LiteralPath $repo -Directory | Where-Object { $_.Name -like 'docs' })
    Assert-Equal 1 $carpetas.Count "no tenia que crear una segunda carpeta de documentacion"
    Assert-Equal 'Docs' $carpetas[0].Name "tenia que respetar el nombre que el repo ya usaba"
}

Test-Case "reinstalar actualiza el runner y NO pisa la configuracion del repo" {
    $repo = New-RepoVacio
    Invoke-Instalador $repo @() | Out-Null

    $config = Join-Path $repo 'docs\session-prompts\session-prompts.config.json'
    Set-Content -LiteralPath $config -Value '{ "model": "sonnet" }' -Encoding UTF8

    $r = Invoke-Instalador $repo @()
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match '"model": "sonnet"' (Get-Content -LiteralPath $config -Raw -Encoding UTF8) "la configuracion del repo no se pisa"
}

Test-Case "el instalador se niega a pisar un runner modificado a mano" {
    $repo = New-RepoVacio
    Invoke-Instalador $repo @() | Out-Null

    $runner = Join-Path $repo 'docs\session-prompts\Run-SessionPrompts.ps1'
    Add-Content -LiteralPath $runner -Value '# cambio local del repo'
    $antes = (Get-FileHash -LiteralPath $runner).Hash

    $r = Invoke-Instalador $repo @()
    Assert-Equal 2 $r.ExitCode "tiene que salir con 2"
    Assert-Match 'MODIFICADO' $r.Salida "con el motivo"
    Assert-Equal $antes (Get-FileHash -LiteralPath $runner).Hash "no puede haber tocado el runner"

    # Con -Force si lo pisa, dejando una copia.
    $r2 = Invoke-Instalador $repo @('-Force')
    Assert-Equal 0 $r2.ExitCode "con -Force. Salida:`n$($r2.Salida)"
    Assert-True (Test-Path -LiteralPath "$runner.bak") "tiene que dejar el .bak"
    Assert-True ($antes -ne (Get-FileHash -LiteralPath $runner).Hash) "con -Force tiene que actualizarlo"
}

# --- Cierre ---------------------------------------------------------------

Write-Host ""
if ($script:Fallados -eq 0) {
    Write-Host "$script:Pasados casos, todos verdes." -ForegroundColor Green
} else {
    Write-Host "$script:Pasados verdes, $script:Fallados en rojo." -ForegroundColor Red
}

if ($KeepTemp) {
    Write-Host "Temporales conservados:" -ForegroundColor DarkGray
    $script:Temporales | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
} else {
    foreach ($t in $script:Temporales) {
        if (Test-Path -LiteralPath $t) {
            try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction Stop } catch { }
        }
    }
}

exit ([int]($script:Fallados -gt 0))
