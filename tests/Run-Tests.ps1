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
$script:Omitidos  = 0
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

# Un caso que no se puede correr en esta maquina se OMITE, con el motivo a la vista: un caso
# que se saltea en silencio es peor que no tenerlo.
class CasoOmitido : System.Exception {
    CasoOmitido([string]$m) : base($m) { }
}
function Skip-Case([string]$motivo) { throw [CasoOmitido]::new($motivo) }

function Test-Case([string]$nombre, [scriptblock]$cuerpo) {
    try {
        & $cuerpo
        $script:Pasados++
        Write-Host "  OK   $nombre" -ForegroundColor Green
    } catch [CasoOmitido] {
        $script:Omitidos++
        Write-Host "  OMITIDO $nombre" -ForegroundColor Yellow
        Write-Host "          $($_.Exception.Message)" -ForegroundColor DarkYellow
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
function Invoke-Runner($fixture, [string[]]$argumentos, [string]$stdin, [int]$fakeExit, [switch]$Legacy) {
    $env:FAKE_CLAUDE_LOG = $fixture.Log
    if ($fakeExit) { $env:FAKE_CLAUDE_EXIT = "$fakeExit" } else { Remove-Item Env:\FAKE_CLAUDE_EXIT -ErrorAction SilentlyContinue }

    # Ningun caso sale a la red salvo los que prueban el chequeo de version, que pasan
    # -SkipUpdateCheck explicitamente... al reves: se lo sacan.
    if (-not ($argumentos -contains '-ProbarChequeo')) {
        $argumentos = @('-SkipUpdateCheck') + $argumentos
    } else {
        $argumentos = @($argumentos | Where-Object { $_ -ne '-ProbarChequeo' })
    }

    if ($Legacy) {
        # $PSNativeCommandArgumentPassing solo se puede fijar ANTES de invocar el runner, y con
        # -File no hay donde hacerlo: por eso este camino usa -Command.
        # Los NOMBRES de parametro van sin comillas: entrecomillados, PowerShell los tomaria
        # como valores posicionales y ligaria todo corrido.
        $citados = $argumentos | ForEach-Object {
            if ($_ -match '^-[A-Za-z]') { $_ } else { "'" + ($_ -replace "'", "''") + "'" }
        }
        $linea = "`$PSNativeCommandArgumentPassing = 'Legacy'; & '" + ($fixture.Runner -replace "'", "''") + "' " + ($citados -join ' ')
        $todos = @('-NoProfile', '-Command', $linea)
    } else {
        $todos = @('-NoProfile', '-File', $fixture.Runner) + $argumentos
    }

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
    # Por defecto NO se lanza la sesion de Claude: los casos que la prueban pasan -ClaudeCommand
    # con el doble y sacan el -SkipClaudeMd.
    if (-not ($argumentos -contains '-ClaudeCommand')) { $argumentos = @('-SkipClaudeMd') + $argumentos }

    $todos = @('-NoProfile', '-File', $script:Instalador, '-Repo', $repo) + $argumentos
    $salida = & pwsh @todos 2>&1
    return [pscustomobject]@{
        Salida   = ($salida | ForEach-Object { "$_" }) -join "`n"
        ExitCode = $LASTEXITCODE
    }
}

# --- El consumidor NATIVO de argumentos -----------------------------------
# El doble .ps1 de arriba alcanza para casi todo, pero NO para la pregunta que mas importa de
# este script: si el texto del prompt cruza intacto la linea de comandos de Windows. Un .ps1 se
# invoca DENTRO del mismo proceso, asi que ni siquiera hay linea de comandos que cruzar.
#
# Para eso hace falta un .exe de verdad, que lea sus argumentos como los lee claude.exe (o sea,
# con CommandLineToArgvW). Se compila uno minusculo, una sola vez por corrida de la suite.
#
# Lo compila Windows PowerShell 5.1: PowerShell 7 saco el soporte de -OutputType
# ConsoleApplication, y 5.1 viene con Windows, asi que no agrega ninguna dependencia nueva. Es el
# unico uso de 5.1 en todo el proyecto, y es para CONSTRUIR el doble, no para correr el runner
# (que 5.1 no puede correr, y hay un caso que lo verifica).
# El .exe imprime, en una linea JSON por invocacion, su directorio de trabajo y CADA argumento
# tal como se lo entrego el sistema operativo. Si el prompt llega partido en la comilla, se ve.
$script:FuenteEco = @'
$ErrorActionPreference = 'Stop'
$fuente = @"
using System;
using System.IO;
using System.Text;

class Eco {
    static string J(string s) {
        return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
    }
    static int Main(string[] args) {
        string log = Environment.GetEnvironmentVariable("FAKE_CLAUDE_LOG");
        StringBuilder sb = new StringBuilder();
        sb.Append("{\"Cwd\":\"").Append(J(Environment.CurrentDirectory)).Append("\",\"Args\":[");
        for (int i = 0; i < args.Length; i++) {
            if (i > 0) sb.Append(",");
            sb.Append("\"").Append(J(args[i])).Append("\"");
        }
        sb.Append("]}");
        File.AppendAllText(log, sb.ToString() + Environment.NewLine, new UTF8Encoding(false));
        string codigo = Environment.GetEnvironmentVariable("FAKE_CLAUDE_EXIT");
        return string.IsNullOrEmpty(codigo) ? 0 : int.Parse(codigo);
    }
}
"@
Add-Type -TypeDefinition $fuente -OutputAssembly $args[0] -OutputType ConsoleApplication
'@

$script:EcoExe = $null
$script:EcoMotivo = $null

function Initialize-EcoExe {
    if ($script:EcoExe -or $script:EcoMotivo) { return }

    $ps51 = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $ps51) {
        $script:EcoMotivo = "no encontre powershell.exe (Windows PowerShell 5.1), que es lo que compila el .exe de prueba"
        return
    }

    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-eco-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $script:Temporales += $dir

    $exe = Join-Path $dir 'eco-claude.exe'
    $compilador = Join-Path $dir 'compilar.ps1'
    Set-Content -LiteralPath $compilador -Encoding UTF8 -Value $script:FuenteEco

    & $ps51.Source -NoProfile -ExecutionPolicy Bypass -File $compilador $exe 2>&1 | Out-Null

    if (Test-Path -LiteralPath $exe) {
        $script:EcoExe = $exe
    } else {
        $script:EcoMotivo = "no pude compilar el .exe de prueba con Windows PowerShell 5.1"
    }
}

# Shim .cmd al estilo del que deja npm: reenvia %* a un ejecutable nativo. Es el otro camino que
# el runner tiene que reconocer, porque ahi PowerShell NO escapa por su cuenta.
function New-EcoShim($fixture) {
    # El .exe se copia AL LADO del shim y con el mismo nombre base: es la forma que tiene una
    # instalacion real (claude.cmd junto a claude.exe), y es lo que el runner busca para
    # esquivar el shim.
    $exeAlLado = Join-Path $fixture.Repo 'eco-claude.exe'
    Copy-Item -LiteralPath $script:EcoExe -Destination $exeAlLado -Force

    $shim = Join-Path $fixture.Repo 'eco-claude.cmd'
    Set-Content -LiteralPath $shim -Encoding ASCII -Value @(
        '@echo off',
        ('"' + $exeAlLado + '" %*')
    )
    return $shim
}

# --- El release de mentira -------------------------------------------------
# Para probar la instalacion y la actualizacion desde un release sin depender de GitHub: se arma
# un .zip con la misma forma que el zipball de un tag (una carpeta arriba con todo adentro), y
# un JSON con la forma de la respuesta de la API.
function New-ReleaseFalso([string]$version) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-rel-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $adentro = Join-Path $dir "RunSessionPrompts-$version"
    New-Item -ItemType Directory -Path $adentro -Force | Out-Null
    $script:Temporales += $dir

    $productoRaiz = Split-Path -Parent $PSScriptRoot
    Copy-Item -LiteralPath (Join-Path $productoRaiz 'Run-SessionPrompts.ps1') -Destination $adentro
    Copy-Item -LiteralPath (Join-Path $productoRaiz 'Install-SessionPrompts.ps1') -Destination $adentro
    Copy-Item -LiteralPath (Join-Path $productoRaiz 'templates') -Destination $adentro -Recurse

    # La version que dice el runner del "release" tiene que ser la del tag.
    $runner = Join-Path $adentro 'Run-SessionPrompts.ps1'
    $texto = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
    $texto = [regex]::Replace($texto, "(?m)^\s*\`$script:RunnerVersion\s*=\s*'[^']+'", "`$script:RunnerVersion = '$version'")
    Set-Content -LiteralPath $runner -Value $texto -Encoding UTF8 -NoNewline

    $zip = Join-Path $dir "release-$version.zip"
    Compress-Archive -Path $adentro -DestinationPath $zip -Force

    $json = Join-Path $dir 'releases-latest.json'
    Set-Content -LiteralPath $json -Value ("{`"tag_name`": `"v$version`"}") -Encoding UTF8

    return [pscustomobject]@{ Zip = $zip; Json = $json; Version = $version }
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
    Assert-Match 'sugiere modelo Opus 5 y la corrida esta en Sonnet 5' $r.Salida "tiene que avisar antes de arrancar"

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

Test-Case "un numero fuera del menu de series corta ahi mismo, no se toma como ruta" {
    $f = New-Fixture
    New-Serie $f 'unica' @{ '01-a.md' = 'a' } | Out-Null

    # La [7] no existe: el menu tiene una sola serie. Antes esto se tomaba como una ruta pegada
    # a mano, seguia preguntando desde-donde, modelo y effort, y recien al final decia que no
    # existe la carpeta "7".
    $r = Invoke-Runner $f @('-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude) "7`n`n"

    Assert-True ($r.ExitCode -ne 0) "tiene que cortar. Salida:`n$($r.Salida)"
    Assert-Match "Valor invalido: '7'" $r.Salida "el error tiene que nombrar lo que se tipeo"
    Assert-Match 'El menu va de 1 a 1' $r.Salida "y decir cual es el rango valido"
    Assert-NotMatch 'No existe la carpeta' $r.Salida "no se toma como ruta"
    Assert-NotMatch 'Empezar desde el numero' $r.Salida "no sigue preguntando lo que viene despues"
    Assert-Equal 0 (@(Get-Sesiones $f)).Count "no lanza ninguna sesion"
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

# El techo de la linea de comandos es del sistema (32767 para todo: ejecutable, flags, nombre de
# sesion y prompt ya escapado), asi que los tamanios de estos casos se calculan a partir de la
# ruta del ejecutable de prueba en vez de ponerse a mano.
$script:TechoLinea = 32767 - 128

function Get-LargoDePromptQueEntra([string]$exe) {
    # Con holgura para los flags (~85) y el nombre de la sesion.
    return $script:TechoLinea - $exe.Length - 500
}

Test-Case "un prompt grande que SI entra en la linea de comandos se corre" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $f = New-Fixture
    $largo = Get-LargoDePromptQueEntra $script:EcoExe
    $texto = 'x' * $largo
    $serie = New-Serie $f 'serie-grande' @{ '01-grande.md' = $texto }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $script:EcoExe)
    Assert-Equal 0 $r.ExitCode "un prompt de $largo caracteres entra y tiene que correr. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal $texto (Get-PromptTexto $s[0]) "y tiene que llegar entero"
}

Test-Case "un prompt que NO entra corta con un error que dice cuanto ocupa" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $f = New-Fixture
    $largo = (Get-LargoDePromptQueEntra $script:EcoExe) + 1000
    $serie = New-Serie $f 'serie-pasada' @{ '01-pasada.md' = ('x' * $largo) }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $script:EcoExe)
    Assert-True ($r.ExitCode -ne 0) "tiene que fallar"
    Assert-Match 'no entra en la linea de comandos de Windows' $r.Salida "con el motivo"
    Assert-Match 'el maximo utilizable es' $r.Salida "y con los numeros"
    Assert-Match 'Partilo en dos sesiones' $r.Salida "y con que hacer"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "el corte cuenta lo que el prompt ocupa ESCAPADO, no su largo crudo" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $f = New-Fixture
    # Largo crudo CHICO -- 22000 caracteres, menos que cualquier corte fijo razonable -- pero
    # con dos comillas cada tres caracteres. Cada '"' viaja como '\\"', asi que escapado ocupa
    # casi el doble y no entra. Un corte hecho sobre el largo crudo dejaria pasar esto, y la
    # sesion moriria con el error del sistema en vez de con un mensaje que diga que hacer.
    $largo = 22000
    $patron = '"a"'
    $texto = ($patron * [Math]::Ceiling($largo / $patron.Length)).Substring(0, $largo)
    $serie = New-Serie $f 'serie-comillona' @{ '01-comillona.md' = $texto }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $script:EcoExe)
    Assert-True ($r.ExitCode -ne 0) "el mismo largo crudo, pero lleno de comillas, ya no entra"
    Assert-Match 'no entra en la linea de comandos de Windows' $r.Salida "con el motivo"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "maxPromptChars de la configuracion sigue siendo un tope propio del repo" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-tope' @{ '01-mediano.md' = ('x' * 5000) }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 -Value '{ "maxPromptChars": 1000 }'

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "tiene que respetar el tope del repo"
    Assert-Match 'maxPromptChars' $r.Salida "y decir de donde sale"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
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

Test-Case "sin -Model ni -Effort ni configuracion, los menus se muestran y Enter toma el default" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-menu' @{ '01-uno.md' = 'x' }

    # Enter en el menu de modelo y Enter en el de effort. Es el camino de la corrida a mano:
    # el ValidateSet de los parametros se revalida en cada asignacion, asi que resolver el
    # valor "no hay nada configurado" adentro de $Model / $Effort aborta el script.
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-ClaudeCommand', $f.FakeClaude) "`n`n"
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-NotMatch 'cannot be validated' $r.Salida "el menu no puede morir validando la variable"

    $s = Get-Sesiones $f
    Assert-Equal 'claude-opus-5' (Get-ArgValue $s[0] '--model') "Enter = Opus 5"
    Assert-Equal 'high' (Get-ArgValue $s[0] '--effort') "Enter = high"
}

Test-Case "la configuracion de la plantilla, con modelo y effort en null, tambien pregunta" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-nulls' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 -Value '{ "model": null, "effort": null }'

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-ClaudeCommand', $f.FakeClaude) "`n`n"
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal 'claude-opus-5' (Get-ArgValue $s[0] '--model') "una clave en null es como si no estuviera"
}

Test-Case "un modelo desconocido en la configuracion corta con un error que lo nombra" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-modelo-raro' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 -Value '{ "model": "gpt" }'

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "no puede arrancar con un modelo que no existe"
    Assert-Match "Modelo desconocido en la configuracion: 'gpt'" $r.Salida "el error tiene que nombrar el valor"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "un effort desconocido en la configuracion corta con un error que lo nombra" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-effort-raro' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 -Value '{ "effort": "altisimo" }'

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "no puede arrancar con un effort que no existe"
    Assert-Match "Effort desconocido en la configuracion: 'altisimo'" $r.Salida "el error tiene que nombrar el valor"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "sin series que correr, un Enter en la pregunta de la carpeta corta ahi mismo" {
    $f = New-Fixture
    New-Serie $f 'serie-cerrada' @{ '01-uno.md' = 'x' } | Out-Null
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Encoding UTF8 `
        -Value 'terminada - serie-cerrada   # cerrada 2026-08-01'

    # Enter en "Carpeta con los prompts .md". Sin el corte, el script seguia preguntando modelo y
    # effort y recien ahi moria con "No existe la carpeta: " (sin carpeta).
    $r = Invoke-Runner $f @('-ClaudeCommand', $f.FakeClaude) "`n`n`n"
    Assert-True ($r.ExitCode -ne 0) "no hay nada que correr"
    Assert-Match 'No hay series pendientes' $r.Salida "primero avisa que estan todas terminadas"
    Assert-Match 'No elegiste ninguna carpeta' $r.Salida "y corta ahi, con un motivo"
    Assert-NotMatch 'Modelo:' $r.Salida "no puede seguir preguntando el modelo"
    Assert-NotMatch 'No existe la carpeta: *$' $r.Salida "ni morir con una ruta vacia"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "-StartFrom mas grande que el ultimo prompt corta, y dice hasta donde llega la serie" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-corta' @{ '01-uno.md' = 'uno'; '02-dos.md' = 'dos' }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '9', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "un numero de inicio que no deja nada para correr tiene que cortar"
    Assert-Match 'No hay nada para correr desde el 9' $r.Salida "el error nombra el numero pedido"
    Assert-Match "tiene 2 prompts y el ultimo es el 2" $r.Salida "y dice hasta donde llega la serie"
    Assert-NotMatch 'No hay prompts .md para ejecutar' $r.Salida "no se confunde con una carpeta sin prompts"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "un numero de inicio entre dos prompts arranca en el siguiente que existe" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-salteada' @{ '01-uno.md' = 'uno'; '02-dos.md' = 'dos'; '05-cinco.md' = 'cinco' }

    # El 3 no existe como prompt, pero no es un error: se pidio "desde el 3" y el 05 esta despues.
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '3', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal 1 $s.Count "corre solo el 05"
    Assert-Equal 'serie-salteada/05-cinco' (Get-ArgValue $s[0] '--name') "y arranca en el 05"
}

Test-Case "el numero de inicio se valida ANTES de preguntar el modelo y el effort" {
    $f = New-Fixture
    New-Serie $f 'unica' @{ '01-a.md' = 'a'; '02-b.md' = 'b' } | Out-Null

    # Serie [1] del menu, y despues un numero de inicio imposible. Sin -Model ni -Effort: si la
    # validacion quedara para el final, el script preguntaria las dos cosas antes de cortar.
    $r = Invoke-Runner $f @('-ClaudeCommand', $f.FakeClaude) "1`n9`n"
    Assert-True ($r.ExitCode -ne 0) "tiene que cortar. Salida:`n$($r.Salida)"
    Assert-Match 'No hay nada para correr desde el 9' $r.Salida "con el motivo"
    Assert-NotMatch 'Modelo:' $r.Salida "no llega a preguntar el modelo"
    Assert-NotMatch 'Effort:' $r.Salida "ni el effort"
}

Test-Case "-StartFrom negativo corta con un error, no se toma como 'desde el primero'" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-negativa' @{ '01-uno.md' = 'uno'; '02-dos.md' = 'dos' }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '-3', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "un numero de inicio imposible no puede reinterpretarse"
    Assert-Match '-StartFrom no puede ser negativo' $r.Salida "el error tiene que decir que pasa"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "una clave desconocida en la configuracion corta, y sugiere la que quiso escribir" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-typo' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 `
        -Value '{ "modelo": "sonnet", "cualquiera": 1 }'

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "una clave que el script no mira no puede pasar como si nada"
    Assert-Match "clave desconocida: 'modelo'" $r.Salida "tiene que nombrar la clave"
    Assert-Match "Quisiste decir 'model'" $r.Salida "y sugerir la parecida"
    Assert-Match "clave desconocida: 'cualquiera'" $r.Salida "todas las que haya, no solo la primera"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "un valor con el tipo equivocado en la configuracion corta, diciendo que se esperaba" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-tipos' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 `
        -Value '{ "worktree": "true", "maxPromptChars": "1000", "model": 5 }'

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "un true entre comillas no es un booleano"
    Assert-Match "'worktree'" $r.Salida "nombra la clave booleana"
    Assert-Match 'true o false, sin comillas' $r.Salida "y dice como se escribe"
    Assert-Match "'maxPromptChars'" $r.Salida "nombra la clave numerica"
    Assert-Match "'model'" $r.Salida "nombra la clave de texto"
    Assert-Match '3 problemas' $r.Salida "los tres juntos, no de a uno por corrida"
}

Test-Case "las claves que empiezan con _ son comentarios y no molestan" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-comentada' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 `
        -Value '{ "_ayuda": "lo que sea", "_model": "texto de ayuda", "model": "sonnet", "effort": null }'

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Equal 'claude-sonnet-5' (Get-ArgValue (Get-Sesiones $f)[0] '--model') "la clave de verdad se sigue leyendo"
}

Test-Case "la configuracion que instala el instalador pasa su propia validacion" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-plantilla' @{ '01-uno.md' = 'x' }
    $plantilla = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates\session-prompts.config.json'
    Copy-Item -LiteralPath $plantilla -Destination (Join-Path $f.SeriesRoot 'session-prompts.config.json')

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "la plantilla no puede quedar en rojo contra el validador. Salida:`n$($r.Salida)"
    Assert-Equal 1 (Get-Sesiones $f).Count "y la corrida sale normal"
}

Test-Case "-BaseBranch, -BranchPrefix y -WorktreeRoot sin -Worktree avisan que no se aplican" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-sin-wt' @{ '01-uno.md' = 'x' }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high',
                            '-BaseBranch', 'main', '-WorktreeRoot', 'Z:\nada', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "avisar no es cortar: la corrida es la que se pidio. Salida:`n$($r.Salida)"
    Assert-Match '-BaseBranch, -WorktreeRoot no se aplican sin -Worktree' $r.Salida "tiene que nombrar los que se pasaron"
    Assert-NotMatch '-BranchPrefix' $r.Salida "y solo esos"
    Assert-Equal 1 (Get-Sesiones $f).Count "la sesion corre igual"
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
    foreach ($archivo in @('Run-SessionPrompts.ps1', 'README.md', 'series-estado.txt',
                           'session-prompts.config.json', '.session-prompts-version',
                           '_plantillas\plantilla-session-prompt.md')) {
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

Test-Case "un checkout con autocrlf no convierte al runner ni al README en modificados" {
    # El repo destino tipico de Windows: core.autocrlf=true y ningun .gitattributes, que es el
    # default de Git for Windows. Al hacer checkout, git reescribe los finales de linea. El
    # contenido es el mismo -- y al runner no le afecta, ni siquiera lee el README -- pero los
    # bytes cambian. Con el hash de los bytes, cualquier clon nuevo del destino frenaba la
    # actualizacion con exit 2 y dejaba de actualizar el README en silencio.
    $repo = New-RepoVacio
    git -C $repo config core.autocrlf true
    Invoke-Instalador $repo @() | Out-Null

    $destino = Join-Path $repo 'docs\session-prompts'
    $runner  = Join-Path $destino 'Run-SessionPrompts.ps1'
    $readme  = Join-Path $destino 'README.md'

    git -C $repo add -A 2>&1 | Out-Null
    git -C $repo commit -qm "andamiaje" 2>&1 | Out-Null

    # Un clon nuevo, o cualquier checkout: git reescribe el archivo desde el indice.
    Remove-Item -LiteralPath $runner, $readme -Force
    git -C $repo checkout -- . 2>&1 | Out-Null

    $eranCrLf = ((Get-Content -LiteralPath $runner -Raw) -match "`r`n") -and
                ((Get-Content -LiteralPath $readme -Raw) -match "`r`n")
    if (-not $eranCrLf) { Skip-Case "el git de esta maquina no convirtio a CRLF con autocrlf=true" }

    $r = Invoke-Instalador $repo @()
    Assert-Equal 0 $r.ExitCode "un cambio de finales de linea no puede frenar la actualizacion. Salida:`n$($r.Salida)"
    Assert-NotMatch 'MODIFICADO'     $r.Salida "el runner no lo toco nadie"
    Assert-NotMatch 'ya tiene uno propio' $r.Salida "el README lo puso este instalador"
    Assert-Match    'sin modificar'  $r.Salida "tiene que reconocerlo como suyo"
}

Test-Case "una marca vieja, con el hash de los bytes, sigue reconociendo lo que instalo" {
    # Las marcas de 1.6.0 y anteriores guardan el hash de los BYTES. Si el archivo instalado tenia
    # CRLF -- como el runner que viene en el zip del release -- ese hash no coincide con el del
    # contenido normalizado, y sin la compatibilidad hacia atras la primera corrida del instalador
    # nuevo veria como modificado todo lo que dejo el viejo.
    $repo = New-RepoVacio
    Invoke-Instalador $repo @() | Out-Null

    $destino = Join-Path $repo 'docs\session-prompts'
    $runner  = Join-Path $destino 'Run-SessionPrompts.ps1'
    $readme  = Join-Path $destino 'README.md'
    $marca   = Join-Path $destino '.session-prompts-version'

    foreach ($f in @($runner, $readme)) {
        $texto = [System.IO.File]::ReadAllText($f) -replace "`r`n", "`n" -replace "`n", "`r`n"
        [System.IO.File]::WriteAllText($f, $texto)
    }

    # La marca como la escribia el instalador viejo: hash de los bytes, y sin el campo hashDe.
    $vieja = Get-Content -LiteralPath $marca -Raw -Encoding UTF8 | ConvertFrom-Json
    $vieja.runnerHash = (Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash
    $vieja.readmeHash = (Get-FileHash -LiteralPath $readme -Algorithm SHA256).Hash
    $sinHashDe = $vieja | Select-Object -Property * -ExcludeProperty hashDe
    Set-Content -LiteralPath $marca -Value ($sinHashDe | ConvertTo-Json) -Encoding UTF8

    $r = Invoke-Instalador $repo @()
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-NotMatch 'MODIFICADO'          $r.Salida "la marca vieja tiene que seguir valiendo"
    Assert-NotMatch 'ya tiene uno propio' $r.Salida "el README tambien"
    Assert-Match    'hashDe' (Get-Content -LiteralPath $marca -Raw -Encoding UTF8) "y la marca queda reescrita en el formato nuevo"
}

Test-Case "effort-sugerido menor o igual que el tope se usa sin preguntar" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-effort' @{
        '01-sin-marca.md' = 'sin marca'
        '02-baja.md'      = "<!-- effort-sugerido: low -->`n`ntramite corto"
        '03-igual.md'     = "<!-- effort-sugerido: high -->`n`nlo mismo que el tope"
    }
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal 'high' (Get-ArgValue $s[0] '--effort') "la sesion sin marca usa el tope"
    Assert-Equal 'low'  (Get-ArgValue $s[1] '--effort') "la sesion que pide menos baja sola"
    Assert-Equal 'high' (Get-ArgValue $s[2] '--effort') "la sesion que pide lo mismo que el tope"
    Assert-Match 'baja desde high' $r.Salida "el plan tiene que decir por que bajo"
}

Test-Case "effort-sugerido mayor que el tope pregunta, y con Enter usa el de la sesion" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-effort-sube' @{ '01-dificil.md' = "<!-- effort-sugerido: max -->`n`nesto cuesta" }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude) "`n"
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'sugiere effort max y la corrida esta en high' $r.Salida "tiene que avisar antes de arrancar"

    $s = Get-Sesiones $f
    Assert-Equal 'max' (Get-ArgValue $s[0] '--effort') "con Enter usa el sugerido"
}

Test-Case "en la pregunta de effort, la opcion 2 corre igual con el tope y la 3 aborta" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-effort-no' @{ '01-dificil.md' = "<!-- effort-sugerido: xhigh -->`n`nesto cuesta" }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'medium', '-ClaudeCommand', $f.FakeClaude) "2`n"
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    $s = Get-Sesiones $f
    Assert-Equal 'medium' (Get-ArgValue $s[0] '--effort') "con 2 corre con el tope de la corrida"
    Assert-Match 'IGNORA el effort sugerido' $r.Salida "y lo deja escrito en el plan"

    Remove-Item -LiteralPath $f.Log -ErrorAction SilentlyContinue
    $r2 = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'medium', '-ClaudeCommand', $f.FakeClaude) "3`n"
    Assert-True ($r2.ExitCode -ne 0) "con 3 tiene que abortar"
    Assert-Equal 0 (Get-Sesiones $f).Count "y no lanzar ninguna sesion"
}

Test-Case "un prompt puede pedir modelo y effort a la vez" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-ambas' @{
        '01-barata.md' = "<!-- modelo-sugerido: sonnet -->`n<!-- effort-sugerido: low -->`n`ntramite"
    }
    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $s = Get-Sesiones $f
    Assert-Equal 'claude-sonnet-5' (Get-ArgValue $s[0] '--model') "modelo de la sesion"
    Assert-Equal 'low' (Get-ArgValue $s[0] '--effort') "effort de la sesion"
}

Test-Case "una marca con un valor invalido corta con error, no se ignora en silencio" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-marca-mala' @{ '01-mal.md' = "<!-- effort-sugerido: extra -->`n`nx" }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "tiene que fallar"
    Assert-Match "declara 'extra', que no es un valor valido" $r.Salida "con el motivo"
    Assert-Match 'low, medium, high, xhigh, max' $r.Salida "y con los valores validos"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "el prompt cruza INTACTO la linea de comandos hacia un .exe nativo" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $f = New-Fixture
    # El texto que se rompia bajo 5.1: comillas dobles, y una ruta con backslashes.
    $texto = 'El legacy loguea "Session ended" cuando cierra. La ruta es C:\temp\x.'
    $serie = New-Serie $f 'serie-nativa' @{ '01-cita.md' = $texto }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $script:EcoExe)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'NO escapa' $r.Salida "con un .exe nativo, el runner NO tiene que escapar"

    $s = Get-Sesiones $f
    Assert-Equal 1 $s.Count "una sesion"
    Assert-Equal $texto (Get-PromptTexto $s[0]) "el prompt tiene que llegar tal cual, con sus comillas"

    # Lo que rompia bajo 5.1 era que el argumento se PARTIA en la primera comilla: el pedazo de
    # atras llegaba como argumentos sueltos. Por eso no alcanza con mirar el ultimo.
    $anteriores = @($s[0].Args)[0..(@($s[0].Args).Count - 2)]
    Assert-True (-not ($anteriores | Where-Object { $_ -match 'Session|legacy|temp' })) "ningun pedazo del prompt puede haber quedado suelto como otro argumento"
}

Test-Case "un 'claude' que es un shim .cmd con el .exe al lado: usa el .exe" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $f = New-Fixture
    $shim = New-EcoShim $f   # queda al lado de una copia del .exe, con el mismo nombre
    $texto = "El legacy loguea `"Session ended`" cuando cierra.`nY esta segunda linea tambien tiene que llegar."
    $serie = New-Serie $f 'serie-shim' @{ '01-cita.md' = $texto }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $shim)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'resolvia a un shim' $r.Salida "tiene que avisar que cambio el shim por el ejecutable"

    $s = Get-Sesiones $f
    Assert-Equal $texto (Get-PromptTexto $s[0]) "el prompt multilinea tiene que llegar ENTERO"
}

Test-Case "un shim .cmd SIN ejecutable al lado: el runner no arranca, y dice por que" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $f = New-Fixture
    # El shim vive solo, sin ningun .exe con su nombre: no hay a que caerse.
    $soloShim = Join-Path $f.Repo 'solo\claude.cmd'
    New-Item -ItemType Directory -Path (Split-Path -Parent $soloShim) -Force | Out-Null
    Set-Content -LiteralPath $soloShim -Encoding ASCII -Value @('@echo off', ('"' + $script:EcoExe + '" %*'))

    $serie = New-Serie $f 'serie-solo-shim' @{ '01-cita.md' = "linea uno`nlinea dos" }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $soloShim)
    Assert-True ($r.ExitCode -ne 0) "tiene que negarse a arrancar"
    Assert-Match 'resuelve a un shim' $r.Salida "con el motivo"
    Assert-Match 'se trunca en su primera linea' $r.Salida "y explicando que se pierde"
    Assert-Match 'ClaudeCommand' $r.Salida "y que hacer al respecto"
    Assert-Equal 0 (Get-Sesiones $f).Count "no puede haber lanzado ninguna sesion"
}

Test-Case "si el llamador dejo el modo en Legacy, el runner lo fija y el prompt cruza intacto" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $f = New-Fixture
    # Con el modo en Legacy y sin hacer nada, esto se parte en la primera comilla y ademas
    # pierde el backslash final. El runner fija el modo para si mismo, asi que no pasa.
    $texto = "El legacy loguea `"Session ended`" cuando cierra.`nRuta: C:\temp\x\"
    $serie = New-Serie $f 'serie-legacy' @{ '01-cita.md' = $texto }

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $script:EcoExe) -Legacy
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match "modo fijado en 'Standard'" $r.Salida "el runner tiene que fijar el modo, no compensarlo escapando"

    $s = Get-Sesiones $f
    Assert-Equal $texto (Get-PromptTexto $s[0]) "el prompt tiene que llegar tal cual, hasta el backslash final"
}

Test-Case "Windows PowerShell 5.1 no puede correr el runner (#Requires -Version 7.0)" {
    $ps51 = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $ps51) { Skip-Case "no encontre powershell.exe (Windows PowerShell 5.1) en esta maquina" }

    $f = New-Fixture
    $salida = & $ps51.Source -NoProfile -ExecutionPolicy Bypass -File $f.Runner -Version 2>&1
    $code = $LASTEXITCODE

    Assert-True ($code -ne 0) "5.1 tiene que fallar, no correr el script"
    Assert-Match '#requires' (($salida | ForEach-Object { "$_" }) -join "`n") "y el motivo tiene que ser el #Requires, no otra cosa"
}

Test-Case "los payloads hostiles cruzan intactos: comillas, backticks, XML, HTML, JSON escapado" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    # Cada payload va en un here-string de comillas simples: adentro no hay escapado de
    # PowerShell, asi que lo que se lee aca es LITERALMENTE lo que tiene que llegar.
    $payloads = [ordered]@{}

    $payloads['comillas-dobles-pares'] = @'
dos comillas dobles seguidas: "" y otro par ""
'@
    $payloads['comilla-doble-impar'] = @'
una sola comilla doble: " y sigue el texto
'@
    $payloads['comillas-anidadas'] = @'
el mensaje "dice ""esto"" adentro" y termina
'@
    $payloads['backticks'] = @'
backtick simple `codigo`, doble `` y triple ``` bloque ```
'@
    $payloads['comillas-simples'] = @'
dos comillas simples: '' y un par ' ' y una sola '
'@
    $payloads['comilla-simple-escapada'] = @'
<caso>\'</caso>
'@
    $payloads['xml'] = @'
<root attr="valor" otro='simple'><![CDATA[texto con " y ' y & y < ]]><vacio /></root>
'@
    $payloads['html'] = @'
<div class="x" onclick='f("a")'>&amp; &lt; &quot; &#39; <br/></div>
'@
    $payloads['json-escapado'] = @'
{ "propiedad": "valor \n  \" \' valor" }
'@
    $payloads['json-con-rutas'] = @'
{"path":"C:\\temp\\x\\","cita":"dijo \"hola\"","fin":"\\"}
'@
    $payloads['json-en-bloque-multilinea'] = @'
Mandale exactamente este cuerpo:

```json
{ "a": "b \" c", "d": [1, 2], "e": "linea1\nlinea2", "f": "simple \' escapada" }
```
'@
    $payloads['combinado'] = @'
"" '' `` \\ \" \' <a b="c" d='e'> {"k": "v \" w"} y ``` fin
'@
    $payloads['backslash-final'] = @'
la ruta es C:\temp\x\
'@
    $payloads['metacaracteres-de-shell'] = @'
shell: & | > < ^ ( ) ; redireccion 2>&1 y tuberia a | more
'@
    $payloads['variables-de-entorno'] = @'
variables: %PATH% %1 %* !DELAYED! $env:PATH $(whoami) ${x}
'@
    $payloads['multilinea-con-comillas'] = @'
primera linea con "comillas dobles"
segunda con 'simples'
tercera con `backticks` y \" escapado
'@
    $payloads['guion-al-principio'] = @'
--dangerously-skip-permissions parece un flag pero es el texto del prompt
'@

    # Los que no se pueden escribir literalmente sin romper este archivo: PowerShell 7 trata
    # las comillas tipograficas como delimitadores de string.
    $payloads['acentos-agudos-y-tipograficas'] =
        'agudos: ' + [char]0xB4 + [char]0xB4 + ' dos seguidos, uno solo ' + [char]0xB4 +
        ' y tipograficas ' + [char]0x201C + [char]0x201D + [char]0x2018 + [char]0x2019 + ' fin'

    $payloads['unicode-y-emoji'] =
        'acentos: ' + [char]0xF3 + ' ' + [char]0xF1 + ' | CJK: ' + [char]0x4E2D + [char]0x6587 +
        ' | emoji: ' + [char]::ConvertFromUtf32(0x1F600) + ' | cirilico: ' + [char]0x0416

    $f = New-Fixture
    $serieDir = Join-Path $f.SeriesRoot 'serie-hostil'
    New-Item -ItemType Directory -Path $serieDir -Force | Out-Null

    $n = 0
    $esperados = [ordered]@{}
    foreach ($nombre in $payloads.Keys) {
        $n++
        $archivo = Join-Path $serieDir ("{0:D2}-{1}.md" -f $n, $nombre)
        # -NoNewline: lo esperado es EXACTAMENTE el payload, sin el salto que agrega Set-Content.
        Set-Content -LiteralPath $archivo -Value $payloads[$nombre] -Encoding UTF8 -NoNewline
        $esperados[$nombre] = Get-Content -LiteralPath $archivo -Raw -Encoding UTF8
    }

    $r = Invoke-Runner $f @('-PromptsPath', $serieDir, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $script:EcoExe)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $sesiones = Get-Sesiones $f
    Assert-Equal $payloads.Count $sesiones.Count "tienen que haber corrido todos los payloads"

    $rotos = @()
    $i = 0
    foreach ($nombre in $payloads.Keys) {
        $args_ = @($sesiones[$i].Args)
        $recibido = if ($args_.Count) { $args_[-1] } else { '' }
        $i++

        if ($args_.Count -ne 11) {
            # 5 flags con su valor + el prompt. Mas argumentos = el prompt se PARTIO.
            $rotos += "$nombre (partido en $($args_.Count) argumentos)"
        } elseif ($recibido -ne $esperados[$nombre]) {
            $rotos += "$nombre (deformado: llego [$($recibido -replace "`n", '\n')])"
        }
    }

    Assert-True ($rotos.Count -eq 0) ("estos payloads no llegaron intactos:`n      " + ($rotos -join "`n      "))
}

Test-Case "el nombre de la serie y del prompt tambien cruzan intactos hacia --rc y --name" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $f = New-Fixture

    # Todo esto es legal en un nombre de archivo de Windows (que solo prohibe < > : " / \ | ? *)
    # y todo esto es especial para algun interprete.
    $serieNombre  = "rara & ^ %PATH% 'sim' ``bt`` (p) #h `$p ~t !b +m =i ,c ;p [c] {l}"
    $promptNombre = "01-raro & 'con' ``bt`` %VAR% !b.md"

    $serieDir = Join-Path $f.SeriesRoot $serieNombre
    New-Item -ItemType Directory -Path $serieDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $serieDir $promptNombre) -Encoding UTF8 -NoNewline -Value 'x'

    $r = Invoke-Runner $f @('-PromptsPath', $serieDir, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $script:EcoExe)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    $esperado = "$serieNombre/" + [System.IO.Path]::GetFileNameWithoutExtension($promptNombre)
    $s = Get-Sesiones $f
    Assert-Equal $esperado (Get-ArgValue $s[0] '--rc') "el nombre de sesion de Remote Control"
    Assert-Equal $esperado (Get-ArgValue $s[0] '--name') "el nombre visible de la sesion"
    Assert-Equal 11 @($s[0].Args).Count "y nada se partio en el camino"
}

Test-Case "el README que instala explica los criterios de modelo y de effort" {
    $repo = New-RepoVacio
    Invoke-Instalador $repo @() | Out-Null

    $readme = Get-Content -LiteralPath (Join-Path $repo 'docs\session-prompts\README.md') -Raw -Encoding UTF8

    Assert-Match 'modelo-sugerido' $readme "tiene que documentar la marca de modelo"
    Assert-Match 'effort-sugerido' $readme "tiene que documentar la marca de effort"
    Assert-Match 'tope' $readme "y la regla del tope"
    Assert-Match 'sonnet' $readme "con criterio para elegir modelo"
    Assert-Match 'xhigh' $readme "y para elegir effort"
    Assert-Match 'pwsh' $readme "y como se corre"
    Assert-NotMatch 'powershell -File' $readme "nunca con powershell"
}

Test-Case "un README propio del repo no se pisa, salvo con -Force" {
    $repo = New-RepoVacio
    $destino = Join-Path $repo 'docs\session-prompts'
    New-Item -ItemType Directory -Path $destino -Force | Out-Null
    $readme = Join-Path $destino 'README.md'
    Set-Content -LiteralPath $readme -Value '# El indice de series de este repo' -Encoding UTF8

    $r = Invoke-Instalador $repo @()
    Assert-Equal 0 $r.ExitCode "la instalacion tiene que seguir. Salida:`n$($r.Salida)"
    Assert-Match 'ya tiene uno propio' $r.Salida "tiene que avisar que no lo pisa"
    Assert-Match 'El indice de series de este repo' (Get-Content -LiteralPath $readme -Raw -Encoding UTF8) "y no haberlo tocado"

    $r2 = Invoke-Instalador $repo @('-Force')
    Assert-Equal 0 $r2.ExitCode "con -Force. Salida:`n$($r2.Salida)"
    Assert-Match 'series de sesiones' (Get-Content -LiteralPath $readme -Raw -Encoding UTF8) "con -Force lo reemplaza"
    Assert-True (Test-Path -LiteralPath "$readme.bak") "dejando el .bak"

    # Y una reinstalacion posterior ya lo reconoce como suyo y lo actualiza sin quejarse.
    $r3 = Invoke-Instalador $repo @()
    Assert-Equal 0 $r3.ExitCode "reinstalacion. Salida:`n$($r3.Salida)"
    Assert-NotMatch 'ya tiene uno propio' $r3.Salida "ya es el nuestro: no tiene que quejarse"
}

Test-Case "la instalacion lanza una sesion de Claude con el prompt del CLAUDE.md" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $repo = New-RepoVacio
    $env:FAKE_CLAUDE_LOG = Join-Path $repo 'claude.log'

    $r = Invoke-Instalador $repo @('-ClaudeCommand', $script:EcoExe, '-Model', 'sonnet', '-Effort', 'low')
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"

    Assert-True (Test-Path -LiteralPath $env:FAKE_CLAUDE_LOG) "tenia que haber lanzado la sesion"
    $args_ = @((Get-Content -LiteralPath $env:FAKE_CLAUDE_LOG -Raw -Encoding UTF8 | ConvertFrom-Json).Args)

    Assert-True ($args_ -contains '-p') "en modo -p: una pasada, sin sesion interactiva"
    Assert-Equal 'claude-sonnet-5' (Get-ArgValue @{ Args = $args_ } '--model') "el modelo que se pidio"
    Assert-Equal 'low' (Get-ArgValue @{ Args = $args_ } '--effort') "el effort que se pidio"
    Assert-Equal 'acceptEdits' (Get-ArgValue @{ Args = $args_ } '--permission-mode') "para que pueda escribir el CLAUDE.md"

    $prompt = $args_[-1]
    Assert-NotMatch '\{\{' $prompt "no pueden quedar marcadores sin reemplazar"
    Assert-NotMatch 'El instalador reemplaza los marcadores' $prompt "el comentario de la plantilla no se manda"
    Assert-Match 'CLAUDE\.md' $prompt "el prompt tiene que hablar del CLAUDE.md"
    Assert-Match 'powershell' $prompt "y de las afirmaciones viejas que hay que corregir"
    Assert-Match ([regex]::Escape((Join-Path $repo 'docs\session-prompts\README.md'))) $prompt "con la ruta real del README instalado"
}

Test-Case "el instalador con -ClaudeCommand vacio usa el default, no revienta al final" {
    $repo = New-RepoVacio

    # PATH minimo (solo el directorio de pwsh): asi 'claude' no resuelve en ninguna maquina y el
    # paso del CLAUDE.md se saltea limpio, sin lanzar nada. Lo que se prueba es que el vacio se
    # toma como "no me lo pasaron": antes, Get-Command reventaba con un error de binding DESPUES
    # de haber instalado todo, y la instalacion terminaba en rojo.
    $pathViejo = $env:PATH
    $minimo = @(
        (Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)),
        (Split-Path -Parent (Get-Command git).Source)   # el instalador necesita git
    )
    $env:PATH = ($minimo -join ';')
    try {
        $r = Invoke-Instalador $repo @('-ClaudeCommand', '')
    } finally {
        $env:PATH = $pathViejo
    }

    Assert-Equal 0 $r.ExitCode "instalar tiene que terminar bien. Salida:`n$($r.Salida)"
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'docs\session-prompts\Run-SessionPrompts.ps1')) "el runner se instala igual"
    Assert-Match "No encontre 'claude'" $r.Salida "el vacio se toma como el default, y el paso se saltea con su motivo"
    Assert-NotMatch 'Cannot validate argument' $r.Salida "no puede salir un error de binding de PowerShell"
}

Test-Case "-SkipClaudeMd no lanza ninguna sesion" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $repo = New-RepoVacio
    $env:FAKE_CLAUDE_LOG = Join-Path $repo 'claude.log'

    $r = Invoke-Instalador $repo @('-SkipClaudeMd', '-ClaudeCommand', $script:EcoExe)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'no toco el CLAUDE.md' $r.Salida "tiene que decirlo"
    Assert-True (-not (Test-Path -LiteralPath $env:FAKE_CLAUDE_LOG)) "no puede haber lanzado nada"
}

Test-Case "-WhatIf no instala nada ni lanza la sesion" {
    Initialize-EcoExe
    if (-not $script:EcoExe) { Skip-Case $script:EcoMotivo }

    $repo = New-RepoVacio
    $env:FAKE_CLAUDE_LOG = Join-Path $repo 'claude.log'

    $r = Invoke-Instalador $repo @('-WhatIf', '-ClaudeCommand', $script:EcoExe)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo 'docs\session-prompts\Run-SessionPrompts.ps1'))) "no tenia que copiar nada"
    Assert-True (-not (Test-Path -LiteralPath $env:FAKE_CLAUDE_LOG)) "ni lanzar la sesion"
    Assert-Match 'lanzaria una sesion' $r.Salida "pero si decir que la lanzaria"
}

Test-Case "el instalador instala desde un zip de release, sin tocar la red" {
    $repo = New-RepoVacio
    $rel = New-ReleaseFalso '9.9.9'

    $r = Invoke-Instalador $repo @('-ReleaseZip', $rel.Zip)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'Instalando desde' $r.Salida "tiene que decir de donde instala"

    $marca = Get-Content -LiteralPath (Join-Path $repo 'docs\session-prompts\.session-prompts-version') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal '9.9.9' $marca.version "la version instalada es la del release, no la de esta carpeta"
}

Test-Case "-FromRelease resuelve el tag y usa el zip que le den" {
    $repo = New-RepoVacio
    $rel = New-ReleaseFalso '9.9.9'

    $env:SESSION_PROMPTS_RELEASES_URL = $rel.Json
    $env:SESSION_PROMPTS_RELEASE_ZIP = $rel.Zip
    try {
        $r = Invoke-Instalador $repo @('-FromRelease', 'latest')
    } finally {
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\SESSION_PROMPTS_RELEASE_ZIP -ErrorAction SilentlyContinue
    }

    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'docs\session-prompts\Run-SessionPrompts.ps1')) "tenia que instalar"
}

Test-Case "-FromRelease sin poder averiguar el tag corta con un error que dice que hacer" {
    $repo = New-RepoVacio
    $env:SESSION_PROMPTS_RELEASES_URL = Join-Path ([System.IO.Path]::GetTempPath()) 'no-existe-este-json.json'
    try {
        $r = Invoke-Instalador $repo @('-FromRelease', 'latest')
    } finally {
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
    }

    Assert-True ($r.ExitCode -ne 0) "tiene que fallar"
    Assert-Match 'No pude averiguar cual es el ultimo release' $r.Salida "con el motivo"
    Assert-Match '-FromRelease v1\.2\.3' $r.Salida "y con la salida a mano"
}

Test-Case "-ReleaseZip junto con -FromRelease avisa cual de los dos origenes usa" {
    $repo = New-RepoVacio
    $rel = New-ReleaseFalso '9.9.9'

    $r = Invoke-Instalador $repo @('-FromRelease', 'v1.0.0', '-ReleaseZip', $rel.Zip)

    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'uso el zip' $r.Salida "tiene que decir cual gano"
    Assert-Match 'ignoro -FromRelease v1.0.0' $r.Salida "y cual ignoro, con su valor"
    Assert-True (Test-Path -LiteralPath (Join-Path $repo 'docs\session-prompts\Run-SessionPrompts.ps1')) "instala igual"
}

Test-Case "el runner -Update baja el release y lo instala en su repo" {
    $f = New-Fixture
    $rel = New-ReleaseFalso '9.9.9'

    $env:SESSION_PROMPTS_RELEASES_URL = $rel.Json
    $env:SESSION_PROMPTS_RELEASE_ZIP = $rel.Zip
    try {
        # -Force porque el runner del fixture se copio a mano y no tiene marca de version:
        # es exactamente el estado de los repos que todavia usan la copia vieja.
        $r = Invoke-Runner $f @('-Update', '-SkipClaudeMd', '-Force')
    } finally {
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\SESSION_PROMPTS_RELEASE_ZIP -ErrorAction SilentlyContinue
    }

    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'Actualizado a v9.9.9' $r.Salida "tiene que decir a que version quedo"
    Assert-Match 'Volve a correr el script' $r.Salida "y que hay que volver a correrlo"

    $instalado = Get-Content -LiteralPath $f.Runner -Raw -Encoding UTF8
    Assert-Match "RunnerVersion = '9.9.9'" $instalado "el runner del repo tiene que ser el del release"
}

Test-Case "-Update cuando ya estas en la ultima version no hace nada" {
    $f = New-Fixture
    $rel = New-ReleaseFalso '0.0.1'

    $env:SESSION_PROMPTS_RELEASES_URL = $rel.Json
    try {
        $r = Invoke-Runner $f @('-Update')
    } finally {
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
    }

    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-Match 'Ya estas en la ultima version' $r.Salida "tiene que decirlo"
}

Test-Case "al arrancar avisa que hay una version nueva y ofrece instalarla" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-chequeo' @{ '01-uno.md' = 'x' }
    $rel = New-ReleaseFalso '9.9.9'

    # El chequeo se anota una vez por dia en el perfil de la maquina: cada caso usa el suyo.
    $perfil = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-perfil-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $perfil -Force | Out-Null
    $script:Temporales += $perfil

    $localAppDataOriginal = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $perfil
    $env:SESSION_PROMPTS_RELEASES_URL = $rel.Json
    try {
        # Respondemos [2]: seguir con la version que tenemos.
        $r = Invoke-Runner $f @('-ProbarChequeo', '-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude) "2`n"
    } finally {
        $env:LOCALAPPDATA = $localAppDataOriginal
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
    }

    Assert-Equal 0 $r.ExitCode "la corrida tiene que seguir. Salida:`n$($r.Salida)"
    Assert-Match 'Hay una version nueva' $r.Salida "tiene que avisar"
    Assert-Match 'v9.9.9' $r.Salida "con cual"
    Assert-Equal 1 (Get-Sesiones $f).Count "y despues correr la serie igual"

    # El chequeo quedo anotado: la proxima corrida del dia no vuelve a preguntar.
    Assert-True (Test-Path -LiteralPath (Join-Path $perfil 'RunSessionPrompts\ultimo-chequeo.txt')) "tiene que anotar el chequeo"
}

Test-Case "si no se puede averiguar la version, la corrida sigue igual" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-sin-red' @{ '01-uno.md' = 'x' }

    $perfil = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-perfil-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $perfil -Force | Out-Null
    $script:Temporales += $perfil

    $localAppDataOriginal = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $perfil
    $env:SESSION_PROMPTS_RELEASES_URL = Join-Path ([System.IO.Path]::GetTempPath()) 'no-existe.json'
    try {
        $r = Invoke-Runner $f @('-ProbarChequeo', '-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    } finally {
        $env:LOCALAPPDATA = $localAppDataOriginal
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
    }

    Assert-Equal 0 $r.ExitCode "no poder chequear no puede romper la corrida. Salida:`n$($r.Salida)"
    Assert-NotMatch 'Hay una version nueva' $r.Salida "no puede inventar una version"
    Assert-Equal 1 (Get-Sesiones $f).Count "y la serie corre igual"
}

Test-Case "checkForUpdates false en la configuracion apaga el chequeo" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-sin-chequeo' @{ '01-uno.md' = 'x' }
    $rel = New-ReleaseFalso '9.9.9'
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'session-prompts.config.json') -Encoding UTF8 -Value '{ "checkForUpdates": false }'

    $perfil = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-perfil-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $perfil -Force | Out-Null
    $script:Temporales += $perfil

    $localAppDataOriginal = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $perfil
    $env:SESSION_PROMPTS_RELEASES_URL = $rel.Json
    try {
        $r = Invoke-Runner $f @('-ProbarChequeo', '-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    } finally {
        $env:LOCALAPPDATA = $localAppDataOriginal
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
    }

    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-NotMatch 'Hay una version nueva' $r.Salida "con la configuracion en false no tiene que chequear"
}

Test-Case "-Update no pisa un runner que el instalador no reconoce, y dice como forzarlo" {
    $f = New-Fixture
    $rel = New-ReleaseFalso '9.9.9'

    $env:SESSION_PROMPTS_RELEASES_URL = $rel.Json
    $env:SESSION_PROMPTS_RELEASE_ZIP = $rel.Zip
    try {
        # Sin -Force, contra un runner copiado a mano (sin marca de version).
        $r = Invoke-Runner $f @('-Update', '-SkipClaudeMd')
    } finally {
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\SESSION_PROMPTS_RELEASE_ZIP -ErrorAction SilentlyContinue
    }

    Assert-True ($r.ExitCode -ne 0) "no puede decir que actualizo si no actualizo"
    Assert-NotMatch 'Actualizado a' $r.Salida "y no puede anunciar lo contrario"
    Assert-Match 'sin marca de version' $r.Salida "con el motivo del instalador"
    Assert-Match '-Update -Force' $r.Salida "y con la salida"

    $instalado = Get-Content -LiteralPath $f.Runner -Raw -Encoding UTF8
    Assert-NotMatch "RunnerVersion = '9.9.9'" $instalado "el runner tiene que haber quedado como estaba"
}

Test-Case "el instalador solo, sin el producto al lado, baja el release sin que se lo pidan" {
    $repo = New-RepoVacio
    $rel = New-ReleaseFalso '9.9.9'

    # Se copia SOLO el instalador a una carpeta aparte: es como queda cuando lo bajas por su
    # cuenta con irm.
    $suelto = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-suelto-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $suelto -Force | Out-Null
    $script:Temporales += $suelto
    Copy-Item -LiteralPath $script:Instalador -Destination $suelto

    $env:SESSION_PROMPTS_RELEASES_URL = $rel.Json
    $env:SESSION_PROMPTS_RELEASE_ZIP = $rel.Zip
    try {
        # Sin -FromRelease y sin -Repo: sale del directorio donde se lo corre.
        Push-Location -LiteralPath $repo
        try {
            $salida = & pwsh -NoProfile -File (Join-Path $suelto 'Install-SessionPrompts.ps1') -SkipClaudeMd 2>&1
            $code = $LASTEXITCODE
        } finally { Pop-Location }
    } finally {
        Remove-Item Env:\SESSION_PROMPTS_RELEASES_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\SESSION_PROMPTS_RELEASE_ZIP -ErrorAction SilentlyContinue
    }

    $texto = ($salida | ForEach-Object { "$_" }) -join "`n"
    Assert-Equal 0 $code "exit code. Salida:`n$texto"
    Assert-Match 'No tengo el producto al lado' $texto "tiene que decir por que baja el release"

    $marca = Get-Content -LiteralPath (Join-Path $repo 'docs\session-prompts\.session-prompts-version') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal '9.9.9' $marca.version "instalo la version del release"
}

Test-Case "con el producto al lado NO baja nada: instala desde la carpeta" {
    $repo = New-RepoVacio

    # Sin overrides de release ni red: si intentara bajar algo, fallaria.
    $r = Invoke-Instalador $repo @()
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-NotMatch 'No tengo el producto al lado' $r.Salida "tiene el producto al lado"
    Assert-NotMatch 'Bajando el release' $r.Salida "asi que no tiene que bajar nada"
}

Test-Case "una linea mal escrita en series-estado.txt corta, y dice cual" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-estado-malo' @{ '01-uno.md' = 'x' }
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Encoding UTF8 -Value @(
        '# el encabezado de siempre',
        '',
        'pendiente 1 serie-estado-malo',
        'terminadas - se-escribio-mal',
        'pendiente 2 otra con espacios'
    )

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-True ($r.ExitCode -ne 0) "tiene que cortar"
    Assert-Match 'linea 4' $r.Salida "diciendo en que linea esta el error"
    Assert-Match 'terminadas - se-escribio-mal' $r.Salida "y cual es"
    Assert-Match 'linea 5' $r.Salida "y la otra tambien: un nombre con espacios se leeria truncado"
    Assert-Match 'El formato de una linea es' $r.Salida "y con el formato correcto"
    Assert-Equal 0 (Get-Sesiones $f).Count "no lanza nada"
}

Test-Case "el formato que ya usan los repos existentes se lee sin quejas" {
    $f = New-Fixture
    $serie = New-Serie $f 'serie-vigente' @{ '01-uno.md' = 'x' }
    New-Serie $f 'serie-cerrada' @{ '01-uno.md' = 'x' } | Out-Null
    New-Serie $f 'serie-cerrada-sin-fecha' @{ '01-uno.md' = 'x' } | Out-Null

    # Las tres formas que aparecen en los series-estado.txt reales.
    Set-Content -LiteralPath (Join-Path $f.SeriesRoot 'series-estado.txt') -Encoding UTF8 -Value @(
        '# comentario, y una linea vacia abajo',
        '',
        'pendiente 1 serie-vigente',
        'terminada - serie-cerrada   # cerrada 2026-08-18',
        'terminada - serie-cerrada-sin-fecha'
    )

    $r = Invoke-Runner $f @('-PromptsPath', $serie, '-StartFrom', '0', '-Model', 'opus', '-Effort', 'high', '-ClaudeCommand', $f.FakeClaude)
    Assert-Equal 0 $r.ExitCode "exit code. Salida:`n$($r.Salida)"
    Assert-NotMatch 'No entiendo estas lineas' $r.Salida "el formato de siempre no puede molestar"
    Assert-Equal 1 (Get-Sesiones $f).Count "y la serie corre"
}

# --- Cierre ---------------------------------------------------------------

Write-Host ""
$omitidos = if ($script:Omitidos -gt 0) { ", $script:Omitidos omitidos" } else { "" }
if ($script:Fallados -eq 0) {
    Write-Host "$script:Pasados casos, todos verdes$omitidos." -ForegroundColor Green
} else {
    Write-Host "$script:Pasados verdes, $script:Fallados en rojo$omitidos." -ForegroundColor Red
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
