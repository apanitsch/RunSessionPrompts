#Requires -Version 7.0
# PowerShell 7 es REQUISITO de este script, no una preferencia.
#
# Medido (2026-08-14, y de nuevo el 2026-08-18 en pwsh 7.6.4): bajo Windows PowerShell 5.1 un
# argumento nativo que contiene comillas dobles llega MUTILADO -- sin escapado se CORTA en la
# primera comilla, y con escapado a mano llega entero pero SIN las comillas. Bajo 7.x llega
# intacto. Como los prompts de sesion citan textos entre comillas todo el tiempo, correr esto
# con 5.1 degrada EN SILENCIO lo que la sesion lee: nada falla, nada se pone rojo, y la sesion
# trabaja sobre una cita distinta de la que se escribio.
#
# Por eso: 'pwsh -File .\Run-SessionPrompts.ps1', nunca 'powershell -File ...'.
# El #Requires de arriba lo hace fallar con un error claro en vez de degradar el prompt.
#
# NOTA DE ENCODING: este archivo se mantiene en ASCII puro (sin acentos ni enies) a proposito.
# 5.1 lee los .ps1 sin BOM como ANSI, asi que cualquier caracter no-ASCII en el propio script
# saldria roto ahi. Con el #Requires 5.1 ya no puede correrlo, o sea que el motivo original
# quedo historico, pero la convencion se mantiene: es gratis y saca una clase entera de sorpresa.
# Los prompts .md SI pueden tener acentos: se leen con -Encoding UTF8 explicito.

<#
.SYNOPSIS
    Ejecuta secuencialmente prompts numerados con Claude Code, cada uno en contexto limpio
    y con Remote Control activado (visible/controlable desde el celular y desde Claude Code
    Desktop).

.DESCRIPTION
    Recorre los archivos .md de una SERIE (una carpeta con prompts numerados 01-, 02-, 03- ...)
    en orden numerico. Cada prompt se corre en su propia sesion interactiva de 'claude' con
    Remote Control (--rc), por lo que:
      - arranca sin memoria de las anteriores (contexto limpio),
      - aparece en la lista de sesiones del celular y del desktop,
      - puede pausar a preguntarte y le respondes desde el telefono.

    IMPORTANTE: las sesiones con Remote Control NO se cierran solas al terminar la tarea (son
    interactivas). Para pasar a la siguiente, cerra la sesion actual con /exit (desde el celular
    o el desktop). Recien ahi el script lanza el proximo prompt. Asi nunca tenes que volver a
    la maquina.

    Si una sesion sale con error (exit code != 0), corta la ejecucion.

    TODO lo que hay que decidir se pregunta AL PRINCIPIO, antes de lanzar la primera sesion:
    contestas una vez y despues te podes ir de la maquina, que es todo el punto de este script.

.PARAMETER PromptsPath
    Carpeta de la serie (los prompts .md enumerados).
    Autocompleta con Tab: '-PromptsPath <Tab>' cicla las series que hay bajo la raiz de series.
    Si no se pasa, el script muestra un MENU con esas series y elegis por numero (Read-Host no
    puede autocompletar con Tab, asi que no hay que tipear el nombre).

    El menu muestra SOLO las series PENDIENTES, y en el ORDEN DE EJECUCION PROPUESTA. Eso sale
    de 'series-estado.txt', que vive en la raiz de series y es exclusivo de este script: no lo
    lee nada mas del sistema, y si lo borras el script sigue andando (vuelve a mostrarlas todas,
    alfabetico). Con -Todas se ven todas.

    El archivo lo mantiene el propio script: cuando una corrida termina bien y llego hasta el
    ultimo prompt de la serie, la marca 'terminada' con la fecha. Tambien se puede editar a
    mano -- el formato esta explicado adentro del propio .txt.

.PARAMETER SeriesRoot
    Carpeta que contiene las series (una subcarpeta por serie). Por defecto:
      1. la carpeta donde vive este script, si tiene series adentro (instalacion clasica:
         el runner copiado a docs/session-prompts/ del repo);
      2. si no, docs/session-prompts (o Docs/session-prompts, o la variante con guion bajo)
         del repo git donde estes parado (instalacion central: un solo runner para todos los
         repos);
      3. si no, la carpeta del script igual.

.PARAMETER Todas
    Muestra en el menu todas las series, incluidas las terminadas (alfabetico), que es como se
    comportaba antes de existir 'series-estado.txt'.

.PARAMETER StartFrom
    Numero de prompt desde el cual empezar (ej: 3 arranca en el 03-...). Es un NUMERO, no el
    nombre de archivo. Si no se pasa, se pide (Enter = desde el primero).

.PARAMETER FullAuto
    Por defecto usa '--permission-mode acceptEdits' (auto-acepta ediciones; igual te puede
    preguntar por comandos y los respondes desde el celular). Con -FullAuto usa
    '--dangerously-skip-permissions' (no pregunta nada).

.PARAMETER Model
    Modelo BASE de la corrida: 'opus' (Opus 5, default) o 'sonnet' (Sonnet 5). Si no se pasa y
    tampoco esta en la configuracion, el script muestra un MENU (Enter = opus).

    Cada prompt puede SUGERIR su propio modelo con una marca en el .md:

        <!-- modelo-sugerido: sonnet -->

    La regla (decision del owner, 2026-07-27), con el rango sonnet < opus:
      - Sugerido MENOR que el base -> manda el de la sesion, sin preguntar. Bajar es barato y
        la sesion sabe lo que necesita: si un prompt dice que con Sonnet alcanza, no hay motivo
        para gastar Opus.
      - Sugerido MAYOR que el base -> el script PARA Y PREGUNTA. Correr una sesion con menos de
        lo que pide es la clase de decision que no se toma sola.
      - Igual, o sin marca -> el base, sin ruido.

    Se resuelve todo antes de lanzar la primera sesion, y el plan se imprime con el modelo de
    cada una.

.PARAMETER Effort
    Nivel de esfuerzo de razonamiento: low, medium, high (default), xhigh, max. Si no se pasa y
    tampoco esta en la configuracion, el script muestra un MENU (Enter = high).

.PARAMETER Worktree
    Corre la serie AISLADA en su propio git worktree, en vez de en el checkout donde estas.

    Antes de la primera sesion la serie obtiene un worktree propio (por defecto
    '<repo>\..\worktrees\<serie>') con una rama nueva '<BranchPrefix>/<serie>' partiendo de
    -BaseBranch. TODAS las sesiones de la serie corren paradas ahi y comparten ese arbol, asi:
      - el checkout principal no se toca (util cuando algo lo esta sirviendo: IIS, un watcher),
      - un arnes de testing que se aisle por ruta de disco se auto-aisla,
      - las sesiones se encadenan: la 02 construye sobre lo que commiteo la 01.

    El worktree NO se borra al terminar: queda con sus commits para revisar y mergear. Al
    reanudar la serie (-StartFrom) se reutiliza el que ya existe.

.PARAMETER BaseBranch
    Rama base de la que parte el worktree de la serie. Default: la rama actual del repo.
    (No se checkoutea: se crea una rama NUEVA a partir de ella.) Solo aplica con -Worktree.

.PARAMETER BranchPrefix
    Prefijo de la rama del worktree: '<prefijo>/<serie>'. Default: 'sesiones'.

.PARAMETER WorktreeRoot
    Carpeta donde se crean los worktrees. Default: hermano del repo, '<repo>\..\worktrees'.
    Cada serie usa '<WorktreeRoot>\<serie>'.

.PARAMETER ClaudeCommand
    Ejecutable de Claude Code. Default: 'claude'. Se expone para poder apuntarlo a otra
    instalacion (o a un doble de prueba, que es como se testea este script).

.PARAMETER DryRun
    Imprime el plan completo -- serie, modelo de cada sesion, directorio de trabajo y la linea
    de comandos que se ejecutaria -- y NO lanza ninguna sesion. No crea worktrees ni toca
    series-estado.txt.

.PARAMETER Version
    Imprime la version del runner y termina.

.EXAMPLE
    # Sin parametros: menu de series pendientes, numero de inicio, modelo y effort.
    pwsh -File .\Run-SessionPrompts.ps1

.EXAMPLE
    .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie

.EXAMPLE
    # Retomar en la sesion 04 (es el NUMERO, no el nombre del archivo).
    .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -StartFrom 4

.EXAMPLE
    # Sin menus: serie, modelo y effort fijados por parametro.
    .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -StartFrom 1 -Model sonnet -Effort max

.EXAMPLE
    # La serie corre aislada en su propio worktree, partiendo de main.
    .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Worktree -BaseBranch main

.EXAMPLE
    # Todas las series, incluidas las ya terminadas.
    .\Run-SessionPrompts.ps1 -Todas

.EXAMPLE
    # Tab completa el nombre de la serie que exista bajo la raiz de series.
    .\Run-SessionPrompts.ps1 -PromptsPath <Tab>

.NOTES
    Version, changelog y procedimiento de release: ver CHANGELOG.md del repo RunSessionPrompts.
#>

[CmdletBinding()]
param(
    # Autocompleta con Tab las series que viven bajo la raiz de series:
    #   .\Run-SessionPrompts.ps1 -PromptsPath <Tab>
    # (El prompt interactivo de mas abajo NO puede autocompletar: Read-Host lee una linea
    # cruda, sin el motor de completado. Por eso ahi ofrecemos un menu.)
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $raiz = if ($fakeBoundParameters.ContainsKey('SeriesRoot')) {
            [string]$fakeBoundParameters['SeriesRoot']
        } else {
            $PSScriptRoot
        }

        Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$wordToComplete*" } |
            Where-Object { -not $_.Name.StartsWith('_') -and -not $_.Name.StartsWith('.') } |
            Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Filter *.md -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -match '^\d+' }).Count -gt 0 } |
            Sort-Object Name |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    "'$($_.FullName)'", $_.Name, 'ParameterValue', $_.FullName)
            }
    })]
    [string]$PromptsPath,

    [string]$SeriesRoot,

    [int]$StartFrom,

    [switch]$FullAuto,

    # Alias corto: 'opus' / 'sonnet' apuntan siempre al ultimo de cada familia.
    # El id completo se resuelve mas abajo para dejarlo explicito en el log.
    [ValidateSet('opus', 'sonnet')]
    [string]$Model,

    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')]
    [string]$Effort,

    # El menu muestra solo las series PENDIENTES segun series-estado.txt. Con -Todas
    # las lista todas (alfabetico), que es como se comportaba antes de ese archivo.
    [switch]$Todas,

    [switch]$Worktree,

    [string]$BaseBranch,

    [string]$BranchPrefix,

    [string]$WorktreeRoot,

    [string]$ClaudeCommand,

    [switch]$DryRun,

    [switch]$Version
)

$ErrorActionPreference = 'Stop'

$script:RunnerVersion = '1.0.0'

if ($Version) {
    Write-Host "Run-SessionPrompts $script:RunnerVersion"
    exit 0
}

# --- Configuracion opcional (session-prompts.config.json) ------------------
# Lo que cambia de repo a repo -- la rama base, si la serie corre aislada, el modelo de
# siempre -- se escribe una vez ahi y no se vuelve a tipear. Precedencia:
#   parametro explicito  >  configuracion  >  default del script.
# El archivo es OPCIONAL: sin el, el script se comporta como el default de siempre.
$script:ConfigPath = $null
$script:Config = $null

function Import-RunnerConfig([string]$raiz) {
    $path = Join-Path $raiz 'session-prompts.config.json'
    if (-not (Test-Path -LiteralPath $path)) { return }

    try {
        $script:Config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:ConfigPath = $path
    } catch {
        Write-Host "No pude leer $path : $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Lookup case-insensitive sobre el JSON. Devuelve $null si la clave no esta.
function Get-ConfigValue([string]$nombre) {
    if ($null -eq $script:Config) { return $null }
    $prop = $script:Config.PSObject.Properties[$nombre]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

# Resuelve un valor de texto con la precedencia de arriba.
function Resolve-Setting([string]$nombre, $valorParametro, $default) {
    if (-not [string]::IsNullOrWhiteSpace([string]$valorParametro)) { return $valorParametro }
    $cfg = Get-ConfigValue $nombre
    if (-not [string]::IsNullOrWhiteSpace([string]$cfg)) { return $cfg }
    return $default
}

# Igual, para los switch: un switch pasado explicitamente gana; si no, manda la config.
# $pasadoExplicitamente lo decide el llamador ($PSBoundParameters adentro de una funcion son
# los parametros DE LA FUNCION, no los del script).
function Resolve-SwitchSetting([string]$nombre, [bool]$pasadoExplicitamente, [bool]$valorParametro, [bool]$default) {
    if ($pasadoExplicitamente) { return $valorParametro }
    $cfg = Get-ConfigValue $nombre
    if ($null -ne $cfg) { return [bool]$cfg }
    return $default
}

# --- Donde viven las series -----------------------------------------------
# Instalacion clasica: el runner copiado adentro de docs/session-prompts/ del repo, con las
# series como subcarpetas suyas. Instalacion central: un solo runner en algun lado y las
# series en el repo donde estes parado. Las dos andan sin configurar nada.
function Test-EsRaizDeSeries([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return $false }
    return @(Get-SeriesEnRaiz $path).Count -gt 0
}

# Series = subcarpetas con al menos un prompt numerado (01-, 02-...).
# Se excluyen las carpetas que empiezan con '_' o '.': son andamiaje, no series ejecutables.
# Asi '_plantillas' (moldes, sin numerar) y '_serie-de-ejemplo' (que SI trae 01-/02- para
# mostrar el formato completo) quedan afuera del menu y del Tab, sin depender de que el
# ejemplo se abstenga de numerar sus prompts.
function Get-SeriesEnRaiz([string]$raiz) {
    Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.StartsWith('_') -and -not $_.Name.StartsWith('.') } |
        Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Filter *.md -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '^\d+' }).Count -gt 0 } |
        Sort-Object Name
}

function Resolve-SeriesRoot([string]$pedida) {
    if (-not [string]::IsNullOrWhiteSpace($pedida)) {
        if (-not (Test-Path -LiteralPath $pedida)) {
            Write-Host "No existe la raiz de series: $pedida" -ForegroundColor Red
            exit 1
        }
        return (Get-Item -LiteralPath $pedida).FullName
    }

    if (Test-EsRaizDeSeries $PSScriptRoot) { return $PSScriptRoot }

    # Runner instalado fuera del repo: buscamos la carpeta de series del repo donde estes.
    $root = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($root)) {
        $root = $root.Trim()
        foreach ($rel in @('docs/session-prompts', 'Docs/session-prompts',
                           'docs/session_prompts', 'Docs/session_prompts')) {
            $candidata = Join-Path $root $rel
            if (Test-Path -LiteralPath $candidata) { return (Get-Item -LiteralPath $candidata).FullName }
        }
    }

    return $PSScriptRoot
}

$SeriesRoot = Resolve-SeriesRoot $SeriesRoot
Import-RunnerConfig $SeriesRoot

# Ahora que hay config, se resuelven los valores que salen de ella.
$ClaudeCommand = Resolve-Setting 'claudeCommand' $ClaudeCommand 'claude'
$BranchPrefix  = Resolve-Setting 'branchPrefix'  $BranchPrefix  'sesiones'
$BaseBranch    = Resolve-Setting 'baseBranch'    $BaseBranch    ''
$WorktreeRoot  = Resolve-Setting 'worktreeRoot'  $WorktreeRoot  ''
$usaWorktree   = Resolve-SwitchSetting 'worktree' $PSBoundParameters.ContainsKey('Worktree') ([bool]$Worktree) $false
$fullAuto      = Resolve-SwitchSetting 'fullAuto' $PSBoundParameters.ContainsKey('FullAuto') ([bool]$FullAuto) $false

# CreateProcess corta en 32767 caracteres TODA la linea de comandos, no solo el prompt: ahi
# entran tambien claude, --model, --effort, --permission-mode, --rc y --name (unos 130
# caracteres). El corte en 30000 deja ese margen y algo mas. Si un prompt se pasa, preferimos
# un error claro y no un prompt truncado en silencio: partilo en dos sesiones.
$maxPromptChars = 30000
$cfgMax = Get-ConfigValue 'maxPromptChars'
if ($null -ne $cfgMax -and [int]$cfgMax -gt 0) { $maxPromptChars = [int]$cfgMax }

function Get-PromptSeries { Get-SeriesEnRaiz $SeriesRoot }

# --- El estado de las series (series-estado.txt) ---------------------------
# Archivo propio de ESTE script: nada mas del sistema lo lee, y si no existe el script
# funciona igual (muestra todas, alfabetico). Ver el encabezado del .txt para el formato.
$estadoPath = Join-Path $SeriesRoot 'series-estado.txt'

function Get-SeriesEstado {
    $mapa = @{}
    if (-not (Test-Path -LiteralPath $estadoPath)) { return $mapa }

    foreach ($linea in (Get-Content -LiteralPath $estadoPath -Encoding UTF8)) {
        $t = $linea.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }

        # <estado> <orden> <serie>  -- la fecha que el script agrega al cerrar queda al final
        # y se ignora.
        $m = [regex]::Match($t, '^(pendiente|terminada)\s+(\S+)\s+(\S+)')
        if (-not $m.Success) { continue }

        $orden = 9999
        if ($m.Groups[2].Value -match '^\d+$') { $orden = [int]$m.Groups[2].Value }

        $mapa[$m.Groups[3].Value] = [pscustomobject]@{
            Estado = $m.Groups[1].Value
            Orden  = $orden
        }
    }
    return $mapa
}

# Se llama al terminar una corrida completa. Reescribe SOLO la linea de esa serie:
# el resto del archivo (comentarios incluidos) queda intacto.
function Set-SerieTerminada([string]$nombre) {
    if (-not (Test-Path -LiteralPath $estadoPath)) { return }

    $hoy = (Get-Date).ToString('yyyy-MM-dd')
    $lineas = @(Get-Content -LiteralPath $estadoPath -Encoding UTF8)
    $tocada = $false

    for ($i = 0; $i -lt $lineas.Count; $i++) {
        if ($lineas[$i] -match "^(pendiente|terminada)\s+(\S+)\s+$([regex]::Escape($nombre))(\s|$)") {
            $lineas[$i] = "terminada - $nombre   # cerrada $hoy"
            $tocada = $true
            break
        }
    }

    # Serie que no figuraba (carpeta nueva): se agrega al final.
    if (-not $tocada) { $lineas += "terminada - $nombre   # cerrada $hoy" }

    Set-Content -LiteralPath $estadoPath -Value $lineas -Encoding UTF8
    Write-Host "series-estado.txt: '$nombre' marcada terminada." -ForegroundColor DarkGray
}

# --- Helpers de paths ------------------------------------------------------
# Windows: comparacion case-insensitive y sin barra final. git imprime rutas con '/';
# GetFullPath las normaliza a '\' y colapsa los '..'.
function Get-NormPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    try { return ([System.IO.Path]::GetFullPath($p)).TrimEnd('\') }
    catch { return $p.TrimEnd('\', '/') }
}

# Copia PRINCIPAL del repo (no un worktree enlazado): primera entrada de 'worktree list'.
# Robusto aunque el script se corra desde adentro de un worktree.
function Get-MainWorktree([string]$anyPathInRepo) {
    $out = git -C $anyPathInRepo worktree list --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    foreach ($line in $out) {
        if ($line -match '^worktree\s+(.+)$') { return (Get-NormPath $Matches[1]) }
    }
    return $null
}

# Rutas de todos los worktrees registrados (normalizadas).
function Get-WorktreePaths([string]$repo) {
    $out = git -C $repo worktree list --porcelain 2>$null
    $paths = @()
    foreach ($line in $out) {
        if ($line -match '^worktree\s+(.+)$') { $paths += (Get-NormPath $Matches[1]) }
    }
    return $paths
}

# --- Ctrl+C corta TODO el script (no solo la sesion de Claude) ------------
# CancelKeyPress es un evento: se suscribe con add_*, no con .Add().
# El handler corre en otro hilo, asi que no usamos Write-Host (no es thread-safe).
[Console]::add_CancelKeyPress({
    param($eventSender, $e)
    $e.Cancel = $true
    [Console]::Error.WriteLine("`nAbortado por el usuario (Ctrl+C). Corto todo el script.")
    [Environment]::Exit(130)
})

# --- Pedir por consola lo que no se haya pasado ---------------------------
# Read-Host NO autocompleta con Tab (lee una linea cruda, sin PSReadLine). En vez de
# pelear con eso, mostramos un menu con las series que hay: no hay que tipear el nombre.
# Si preferis tipear con Tab, pasa el parametro: -PromptsPath <Tab> (tiene completer).
if ([string]::IsNullOrWhiteSpace($PromptsPath)) {
    $seriesTodas = @(Get-PromptSeries)
    $estado = Get-SeriesEstado

    # Menu = solo las PENDIENTES, en el orden de ejecucion propuesta. Una serie que no figura
    # en el archivo se considera pendiente y va al final (orden 9999): asi una carpeta nueva
    # aparece en el menu sin que haya que acordarse de anotarla.
    if ($Todas -or $estado.Count -eq 0) {
        $series = $seriesTodas
        $ocultas = 0
    } else {
        $series = @($seriesTodas |
            Where-Object { -not ($estado.ContainsKey($_.Name)) -or $estado[$_.Name].Estado -eq 'pendiente' } |
            Sort-Object @{ Expression = { if ($estado.ContainsKey($_.Name)) { $estado[$_.Name].Orden } else { 9999 } } }, Name)
        $ocultas = $seriesTodas.Count - $series.Count
    }

    if ($series.Count -eq 0) {
        if ($ocultas -gt 0) {
            Write-Host "No hay series pendientes ($ocultas terminadas). -Todas para verlas." -ForegroundColor Yellow
        } else {
            Write-Host "No encontre series en $SeriesRoot." -ForegroundColor Yellow
            Write-Host "Una serie es una subcarpeta con prompts numerados (01-..., 02-...)." -ForegroundColor DarkGray
        }
        $PromptsPath = Read-Host "Carpeta con los prompts .md"
    } else {
        $titulo = if ($ocultas -gt 0) { "Series pendientes (en orden de ejecucion propuesta):" } else { "Series disponibles:" }
        Write-Host $titulo -ForegroundColor Cyan
        for ($i = 0; $i -lt $series.Count; $i++) {
            $n = @(Get-ChildItem -LiteralPath $series[$i].FullName -Filter *.md |
                   Where-Object { $_.Name -match '^\d+' }).Count
            Write-Host ("  [{0}] {1} ({2} prompts)" -f ($i + 1), $series[$i].Name, $n)
        }
        if ($ocultas -gt 0) {
            Write-Host ("  ... y {0} terminadas, ocultas (-Todas para verlas; el estado esta en series-estado.txt)" -f $ocultas) -ForegroundColor DarkGray
        }

        $ans = Read-Host "Elegi el numero (o pega una ruta)"
        if ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $series.Count) {
            $PromptsPath = $series[[int]$ans - 1].FullName
            Write-Host "Serie: $($series[[int]$ans - 1].Name)" -ForegroundColor DarkGray
        } elseif (-not [string]::IsNullOrWhiteSpace($ans)) {
            $PromptsPath = $ans   # ruta pegada a mano
        } else {
            Write-Host "No elegiste ninguna serie." -ForegroundColor Red
            exit 1
        }
    }
}

if (-not $PSBoundParameters.ContainsKey('StartFrom')) {
    $ans = Read-Host "Empezar desde el numero (Enter = desde el primero)"
    if ([string]::IsNullOrWhiteSpace($ans)) {
        $StartFrom = 0
    } elseif ($ans -match '^\d+$') {
        $StartFrom = [int]$ans
    } else {
        Write-Host "Valor invalido: '$ans'. Tiene que ser un numero." -ForegroundColor Red
        exit 1
    }
}

# --- Modelo y effort ------------------------------------------------------
# Mismo criterio que el menu de series: numeritos, sin tipear nombres. Enter toma el default
# (opus / high), que es lo que corre una sesion de serie normalmente.
$modelos = @(
    @{ Alias = 'opus';   Id = 'claude-opus-5';   Etiqueta = 'Opus 5' },
    @{ Alias = 'sonnet'; Id = 'claude-sonnet-5'; Etiqueta = 'Sonnet 5' }
)

$Model = Resolve-Setting 'model' $Model ''
if (-not [string]::IsNullOrWhiteSpace($Model) -and -not ($modelos.Alias -contains $Model)) {
    Write-Host "Modelo desconocido en la configuracion: '$Model'. Validos: $($modelos.Alias -join ', ')." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Model)) {
    Write-Host "Modelo:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $modelos.Count; $i++) {
        $marca = if ($i -eq 0) { ' (default)' } else { '' }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $modelos[$i].Etiqueta, $marca)
    }

    $ans = Read-Host "Elegi el numero (Enter = $($modelos[0].Etiqueta))"
    if ([string]::IsNullOrWhiteSpace($ans)) {
        $Model = $modelos[0].Alias
    } elseif ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $modelos.Count) {
        $Model = $modelos[[int]$ans - 1].Alias
    } else {
        Write-Host "Valor invalido: '$ans'. Tiene que ser un numero de la lista." -ForegroundColor Red
        exit 1
    }
}

$modelo = $modelos | Where-Object { $_.Alias -eq $Model } | Select-Object -First 1

# Los niveles son los que acepta 'claude --effort'. El default del modelo ya es high, pero lo
# pasamos explicito igual: asi la corrida no depende de que el default no cambie.
$efforts = @('high', 'low', 'medium', 'xhigh', 'max')

$Effort = Resolve-Setting 'effort' $Effort ''
if (-not [string]::IsNullOrWhiteSpace($Effort) -and -not ($efforts -contains $Effort)) {
    Write-Host "Effort desconocido en la configuracion: '$Effort'. Validos: $($efforts -join ', ')." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Effort)) {
    Write-Host "Effort:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $efforts.Count; $i++) {
        $marca = if ($i -eq 0) { ' (default)' } else { '' }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $efforts[$i], $marca)
    }

    $ans = Read-Host "Elegi el numero (Enter = $($efforts[0]))"
    if ([string]::IsNullOrWhiteSpace($ans)) {
        $Effort = $efforts[0]
    } elseif ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $efforts.Count) {
        $Effort = $efforts[[int]$ans - 1]
    } else {
        Write-Host "Valor invalido: '$ans'. Tiene que ser un numero de la lista." -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $PromptsPath)) {
    Write-Host "No existe la carpeta: $PromptsPath" -ForegroundColor Red
    exit 1
}

# Effort y permisos son iguales para todas las sesiones de la corrida. El MODELO no: cada
# prompt puede sugerir el suyo (ver el bloque "Modelo sugerido por sesion" mas abajo), asi que
# '--model' se agrega por sesion.
# (Dentro de una sesion se pueden cambiar con /model y /effort, o verificar con /status.)
# Remote Control (--rc) se agrega por sesion, con nombre, mas abajo.
$claudeArgs = @('--effort', $Effort)
if ($fullAuto) {
    $claudeArgs += '--dangerously-skip-permissions'
} else {
    $claudeArgs += @('--permission-mode', 'acceptEdits')
}

# --- Escapado de argumentos nativos: SOLO donde hace falta ----------------
# El prompt entero viaja como UN argumento hacia 'claude', y casi todos citan algo ENTRE
# COMILLAS. Que esas comillas lleguen intactas no es cosmetico: es lo que la sesion lee.
#
# Escapar segun las reglas de CommandLineToArgvW (comillas con \, y backslashes duplicados
# cuando preceden a una comilla o cierran la cadena) hace falta cuando el llamador NO lo hace.
# Windows PowerShell 5.1 no lo hace. PowerShell 7.3+ SI, y ahi el escapado a mano se suma
# encima: doble escapado.
#
# MEDIDO (pwsh 7.6.4, Windows 11) pasando el argumento
#     cita: "texto", ruta C:\x\
# y leyendo la linea de comandos CRUDA que recibe el proceso hijo (Win32_Process.CommandLine)
# mas su parseo con CommandLineToArgvW, que es como un .exe nativo lee sus argumentos:
#
#   | modo                          | sin escapar        | escapado a mano                |
#   |-------------------------------|--------------------|--------------------------------|
#   | Windows (default 7.x), a .exe | INTACTO            | cita: \"texto\", ruta C:\x\\   |
#   | Windows (default 7.x), a .cmd | comillas PERDIDAS  | comillas OK (*)                |
#   | Legacy                        | comillas PERDIDAS  | comillas OK (*)                |
#
#   (*) con un efecto colateral medido: un '\' AL FINAL del argumento llega DUPLICADO, porque
#       las dos capas duplican los backslashes de cierre. Se deja como esta: los prompts no
#       terminan en backslash, y el interprete donde esto importaria (5.1) ya no puede correr
#       este script.
#
# O sea que en el caso normal de hoy -- 'claude' es claude.exe y el modo es el default -- el
# escapado a mano no protege: CORROMPE. Por eso se conserva, pero CONDICIONADO a los dos casos
# donde si hace falta. INFERIDO de about_Parsing: 'Legacy' no escapa nunca; 'Standard' escapa
# siempre; 'Windows' (el default en Windows) escapa salvo para cmd.exe, .bat, .cmd y algunos
# mas, que quedan en el comportamiento viejo. La fila del shim .cmd ademas esta medida.
function ConvertTo-NativeArg([string]$s) {
    $s = $s -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return $s
}

# Decide si este entorno necesita el escapado manual. Se evalua UNA vez, no por prompt: ni el
# modo de pasaje de argumentos ni el PATH cambian a mitad de una serie.
function Test-NecesitaEscapadoNativo([string]$comando) {
    # En 7.0-7.2 la variable de preferencia todavia no existe y el comportamiento es el viejo,
    # asi que $null se trata como 'Legacy'.
    $modo = if ($null -ne $PSNativeCommandArgumentPassing) { [string]$PSNativeCommandArgumentPassing } else { 'Legacy' }

    # 1) Modo Legacy: PowerShell no escapa nada y ademas solo entrecomilla si hay espacios.
    #    Se puede setear por sesion o desde un perfil, asi que no alcanza con el #Requires.
    if ($modo -eq 'Legacy') {
        return @($true, "modo Legacy: PowerShell no escapa")
    }

    # 2) Modo 'Windows' con un destino .cmd/.bat: PowerShell les aplica las reglas VIEJAS
    #    (no escapa las comillas), porque cmd.exe no entiende el escapado de
    #    CommandLineToArgvW. Pasa, por ejemplo, si 'claude' se instalo por npm, que deja un
    #    shim .cmd en el PATH. En modo 'Standard' no hay excepcion por extension.
    if ($modo -eq 'Windows') {
        $cmd = Get-Command $comando -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.CommandType -eq 'Application' -and $cmd.Source -match '\.(cmd|bat)$') {
            return @($true, "'$comando' es un shim $([IO.Path]::GetExtension($cmd.Source))")
        }
    }

    # 3) Todo lo demas (hoy: modo 'Windows' + claude.exe): PowerShell ya escapa bien.
    return @($false, "modo $modo y '$comando' no es un shim .cmd/.bat")
}

$escapar, $motivoEscapado = Test-NecesitaEscapadoNativo $ClaudeCommand

# Numero al inicio del nombre (01-foo.md -> 1). Sirve para ordenar y filtrar.
function Get-PromptNumber($name) { [int]($name -replace '^(\d+).*$', '$1') }

# Solo los .md que empiezan con numero: README.md y ESTADO.md no son prompts.
# Orden numerico: 01-, 02- ... 10- (no alfabetico, para que 10 no venga antes que 2).
# OJO: se resuelven ACA, con .FullName ABSOLUTO, ANTES de cambiar de directorio. Asi el loop
# nunca depende de que $PromptsPath sea relativo (podria serlo).
$prompts = Get-ChildItem -LiteralPath $PromptsPath -Filter *.md |
    Where-Object { $_.Name -match '^\d+' } |
    Sort-Object { Get-PromptNumber $_.Name }, Name

if ($StartFrom -gt 0) {
    $prompts = $prompts | Where-Object { (Get-PromptNumber $_.Name) -ge $StartFrom }
}

# @() para que un solo prompt (o ninguno) siga teniendo .Count.
$prompts = @($prompts)

if ($prompts.Count -eq 0) {
    Write-Host "No hay prompts .md para ejecutar en $PromptsPath (StartFrom = $StartFrom)." -ForegroundColor Yellow
    exit 1
}

# Nombre de la serie (la carpeta). Va en el nombre de cada sesion, y de el salen la rama y el
# worktree cuando la corrida es aislada.
$serie = (Get-Item -LiteralPath $PromptsPath).Name

# --- Donde corren las sesiones --------------------------------------------
# claude agrupa las sesiones por su directorio de trabajo. Si lo lanzamos parados en
# docs/session-prompts, el proyecto no es el repo sino esa subcarpeta. Nos paramos en la raiz
# del repo para que las sesiones caigan donde corresponde, para que CLAUDE.md se cargue solo,
# y para que las rutas repo-relativas de los prompts resuelvan.
#
# En un worktree, --show-toplevel devuelve la raiz DEL WORKTREE, que es justo lo que queremos:
# la serie corre contra el checkout donde vive.
$repoRoot = git -C $PromptsPath rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    Write-Host "$PromptsPath no esta dentro de un repo git." -ForegroundColor Red
    exit 1
}
$repoRoot = Get-NormPath $repoRoot.Trim()

$workDir = $repoRoot
$branch = $null
$mainRepo = $null
$worktreePath = $null

if ($usaWorktree) {
    $branch = "$BranchPrefix/$serie"

    $mainRepo = Get-MainWorktree $PromptsPath
    if ([string]::IsNullOrWhiteSpace($mainRepo)) {
        Write-Host "No pude ubicar la copia principal del repo desde $PromptsPath." -ForegroundColor Red
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($BaseBranch)) {
        $BaseBranch = (git -C $mainRepo rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($BaseBranch)) {
            Write-Host "No pude leer la rama actual de $mainRepo. Pasa -BaseBranch." -ForegroundColor Red
            exit 1
        }
        $BaseBranch = $BaseBranch.Trim()
    }

    # Default del WorktreeRoot: hermano del repo ('<repo>\..\worktrees'). GetFullPath colapsa
    # el '..' a una ruta real.
    if ([string]::IsNullOrWhiteSpace($WorktreeRoot)) {
        $WorktreeRoot = Get-NormPath (Join-Path $mainRepo '..\worktrees')
    } else {
        $WorktreeRoot = Get-NormPath $WorktreeRoot
    }
    $worktreePath = Get-NormPath (Join-Path $WorktreeRoot $serie)

    # Guarda de seguridad: el worktree NUNCA debe caer adentro del checkout principal
    # (romperia el status del repo y podria pisar lo que ese checkout este sirviendo).
    if ($worktreePath.ToLowerInvariant().StartsWith($mainRepo.ToLowerInvariant() + '\')) {
        Write-Host "El worktree ($worktreePath) caeria DENTRO del checkout principal ($mainRepo)." -ForegroundColor Red
        Write-Host "Pasa -WorktreeRoot a una carpeta fuera del repo." -ForegroundColor Red
        exit 1
    }

    $workDir = $worktreePath
}

# --- Modelo sugerido por sesion -------------------------------------------
# Un prompt puede declarar con que modelo se penso escribirlo, con una marca en el .md:
#
#     <!-- modelo-sugerido: sonnet -->
#
# La regla (decision del owner, 2026-07-27), con el rango sonnet < opus:
#   - sugerido MENOR que el base -> manda el de la sesion, sin preguntar (bajar es barato).
#   - sugerido MAYOR que el base -> PARA Y PREGUNTA (correr con menos de lo que pide la sesion
#     no se decide solo).
#   - igual, o sin marca         -> el base, sin ruido.
#
# Todo esto se resuelve ACA, antes de crear el worktree y de lanzar la primera sesion: si el
# script preguntara en medio del loop, romperia lo unico que promete (que te podes ir de la
# maquina).
$rangoModelo = @{ 'sonnet' = 1; 'opus' = 2 }

function Get-ModeloSugerido([string]$path) {
    # -Encoding UTF8 por el mismo motivo que al leer el prompt: los .md no tienen BOM.
    $texto = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $m = [regex]::Match($texto, '(?im)^[ \t]*<!--[ \t]*(?:modelo-sugerido|suggested-model):[ \t]*(opus|sonnet)[ \t]*-->[ \t]*$')
    if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
    return $null
}

$plan = @()
foreach ($p in $prompts) {
    $sugerido = Get-ModeloSugerido $p.FullName
    $modeloSesion = $modelo
    $nota = ''

    if ($sugerido) {
        $modeloSugerido = $modelos | Where-Object { $_.Alias -eq $sugerido } | Select-Object -First 1

        if ($rangoModelo[$sugerido] -lt $rangoModelo[$Model]) {
            $modeloSesion = $modeloSugerido
            $nota = "sugerido por la sesion (baja desde $($modelo.Etiqueta))"
        }
        elseif ($rangoModelo[$sugerido] -gt $rangoModelo[$Model]) {
            Write-Host ""
            Write-Host ("$($p.Name) sugiere {0} y la corrida esta en {1}." -f $modeloSugerido.Etiqueta, $modelo.Etiqueta) -ForegroundColor Yellow
            Write-Host "  [1] Usar $($modeloSugerido.Etiqueta) en ESTA sesion (lo que pide el prompt)  (default)"
            Write-Host "  [2] Correrla igual con $($modelo.Etiqueta)"
            Write-Host "  [3] Abortar"

            $ans = Read-Host "Elegi el numero (Enter = 1)"
            if ([string]::IsNullOrWhiteSpace($ans) -or $ans -eq '1') {
                $modeloSesion = $modeloSugerido
                $nota = 'sugerido por la sesion (SUBE, confirmado)'
            } elseif ($ans -eq '2') {
                $nota = "IGNORA el sugerido ($($modeloSugerido.Etiqueta)), confirmado"
            } elseif ($ans -eq '3') {
                Write-Host "Abortado por el usuario." -ForegroundColor Red
                exit 1
            } else {
                Write-Host "Valor invalido: '$ans'. Tiene que ser 1, 2 o 3." -ForegroundColor Red
                exit 1
            }
        }
        else {
            $nota = 'coincide con el sugerido'
        }
    }

    $plan += [pscustomobject]@{ Prompt = $p; Modelo = $modeloSesion; Nota = $nota }
}

# --- El plan, antes de arrancar -------------------------------------------
$desde = if ($StartFrom -gt 0) { " (desde el $StartFrom)" } else { "" }
Write-Host ""
Write-Host "Ejecutando $($prompts.Count) prompts de la serie '$serie'$desde" -ForegroundColor Cyan
Write-Host "Prompts: $PromptsPath" -ForegroundColor DarkGray
if ($usaWorktree) {
    Write-Host "Worktree (directorio de trabajo): $worktreePath  |  rama: $branch (desde $BaseBranch)" -ForegroundColor DarkGray
} else {
    Write-Host "Proyecto (directorio de trabajo): $workDir" -ForegroundColor DarkGray
}
Write-Host "Modelo base: $($modelo.Etiqueta) ($($modelo.Id))  |  Effort: $Effort" -ForegroundColor DarkGray
if ($script:ConfigPath) {
    Write-Host "Configuracion: $script:ConfigPath" -ForegroundColor DarkGray
}

# Que quede en el log: si esto decide mal, los prompts llegan con las comillas rotas y no se
# nota en ningun lado. Verlo escrito es mas barato que volver a medirlo.
$queHace = if ($escapar) { "escapa a mano" } else { "NO escapa (lo hace PowerShell)" }
Write-Host "Argumentos nativos: $queHace -- $motivoEscapado" -ForegroundColor DarkGray

# El plan completo: que modelo le toca a cada sesion y por que.
foreach ($item in $plan) {
    $detalle = if ($item.Nota) { "  <- $($item.Nota)" } else { "" }
    $color = if ($item.Modelo.Alias -ne $modelo.Alias) { 'Yellow' } else { 'DarkGray' }
    Write-Host ("  {0,-34} {1}{2}" -f $item.Prompt.Name, $item.Modelo.Etiqueta, $detalle) -ForegroundColor $color
}

if ($DryRun) {
    Write-Host ""
    Write-Host "-DryRun: no se lanza ninguna sesion. Lo que se ejecutaria:" -ForegroundColor Yellow
    foreach ($item in $plan) {
        $sessionName = "$serie/$($item.Prompt.BaseName)"
        $linea = "$ClaudeCommand --model $($item.Modelo.Id) $($claudeArgs -join ' ') --rc $sessionName --name $sessionName <prompt de $($item.Prompt.Name)>"
        Write-Host "  $linea" -ForegroundColor DarkGray
    }
    exit 0
}

# --- Crear o reutilizar el worktree de la serie ---------------------------
# Recien aca, con el plan ya cerrado: si algo de arriba aborta, no dejamos un worktree colgado.
if ($usaWorktree) {
    $registered = @(Get-WorktreePaths $mainRepo | Where-Object { $_.ToLowerInvariant() -eq $worktreePath.ToLowerInvariant() })

    if ($registered.Count -gt 0) {
        Write-Host "Worktree existente, lo reutilizo: $worktreePath" -ForegroundColor DarkGray
    } elseif (Test-Path -LiteralPath $worktreePath) {
        # Hay una carpeta ahi que git NO conoce como worktree: no la tocamos.
        Write-Host "Existe la carpeta $worktreePath pero no es un worktree registrado." -ForegroundColor Red
        Write-Host "Borrala o elegi otro -WorktreeRoot." -ForegroundColor Red
        exit 1
    } else {
        $parent = Split-Path -Parent $worktreePath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

        # La rama del worktree puede existir ya (corrida previa cuyo worktree se removio).
        git -C $mainRepo show-ref --verify --quiet "refs/heads/$branch"
        $branchExists = ($LASTEXITCODE -eq 0)

        if ($branchExists) {
            Write-Host "Creo worktree $worktreePath sobre la rama existente $branch" -ForegroundColor Cyan
            git -C $mainRepo worktree add $worktreePath $branch
        } else {
            Write-Host "Creo worktree $worktreePath con rama nueva $branch (desde $BaseBranch)" -ForegroundColor Cyan
            git -C $mainRepo worktree add $worktreePath -b $branch $BaseBranch
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Fallo 'git worktree add'. Revisa que $BaseBranch exista y que $branch no este en uso." -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host "Cada sesion tiene Remote Control. Para pasar a la siguiente, cerra la actual con /exit.`n" -ForegroundColor DarkGray

# --- El loop --------------------------------------------------------------
$reloj = [System.Diagnostics.Stopwatch]::StartNew()

Push-Location -LiteralPath $workDir
try {

foreach ($item in $plan) {
    $p = $item.Prompt
    $modeloSesion = $item.Modelo

    Write-Host "== Sesion: $($p.Name)  [$($modeloSesion.Etiqueta)]  (/exit para pasar a la proxima) ==" -ForegroundColor Cyan

    # El contenido del prompt va como argumento posicional (mensaje inicial), NO por stdin:
    # si se pipea, claude pierde la TTY y no seria interactivo/RC.
    #
    # -Encoding UTF8 explicito: los .md son UTF-8 sin BOM. En 7.x ese ya es el default, pero
    # dejarlo escrito hace que la corrida no dependa de que el default no cambie. Se lee del
    # checkout donde viven los prompts ($p.FullName es absoluto); el cwd puede ser otro.
    $promptText = Get-Content -LiteralPath $p.FullName -Raw -Encoding UTF8

    # Ver el bloque "Escapado de argumentos nativos": en el camino normal (claude.exe, modo
    # 'Windows') PowerShell ya escapa solo y meter escapado encima degrada el prompt.
    $arg = if ($escapar) { ConvertTo-NativeArg $promptText } else { $promptText }

    if ($arg.Length -gt $maxPromptChars) {
        Write-Host "$($p.Name) tiene $($arg.Length) caracteres (maximo $maxPromptChars): no entra en la linea de comandos. Partilo en dos sesiones." -ForegroundColor Red
        exit 1
    }

    # Nombre visible de la sesion en el celular y en Claude Code Desktop. Sin esto, Remote
    # Control genera uno al azar tipo 'mi-pc-snappy-emerson'.
    $sessionName = "$serie/$($p.BaseName)"

    $relojSesion = [System.Diagnostics.Stopwatch]::StartNew()

    # Se pone en cero para no arrastrar el exit code de un comando anterior si el destino no
    # llega a setearlo.
    $global:LASTEXITCODE = 0

    # $($...) explicito: en modo argumento, un '$var.Prop' suelto es facil de leer mal.
    & $ClaudeCommand --model $($modeloSesion.Id) @claudeArgs --rc $sessionName --name $sessionName $arg

    $relojSesion.Stop()

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Fallo $($p.Name) (exit $LASTEXITCODE). Corto la ejecucion." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    Write-Host ("Cerrada {0} ({1:hh\:mm\:ss}).`n" -f $p.Name, $relojSesion.Elapsed) -ForegroundColor Green
}

}
finally {
    Pop-Location
}

$reloj.Stop()
Write-Host ("Todos los prompts se ejecutaron correctamente ({0} sesiones, {1:hh\:mm\:ss})." -f $plan.Count, $reloj.Elapsed) -ForegroundColor Green

if ($usaWorktree) {
    Write-Host ""
    Write-Host "El worktree quedo con sus commits (no se borra solo):" -ForegroundColor DarkGray
    Write-Host "  $worktreePath  (rama $branch)" -ForegroundColor DarkGray
    Write-Host "Para integrar, desde el checkout principal:" -ForegroundColor DarkGray
    Write-Host "  git -C `"$mainRepo`" merge $branch      # o PR por gh" -ForegroundColor DarkGray
    Write-Host "Para limpiar:" -ForegroundColor DarkGray
    Write-Host "  git -C `"$mainRepo`" worktree remove `"$worktreePath`"" -ForegroundColor DarkGray
}

# La serie se marca terminada SOLO si la corrida llego hasta el ultimo prompt. Con -StartFrom
# se puede retomar a mitad y terminar igual (por eso no se exige empezar en el 1); lo que no
# cuenta es una corrida que se corto antes del final.
$ultimoDeLaSerie = @(Get-ChildItem -LiteralPath $PromptsPath -Filter *.md |
    Where-Object { $_.Name -match '^\d+' } |
    Sort-Object { Get-PromptNumber $_.Name } |
    Select-Object -Last 1)

if ($ultimoDeLaSerie.Count -gt 0 -and $plan[-1].Prompt.Name -eq $ultimoDeLaSerie[0].Name) {
    Set-SerieTerminada $serie
}
