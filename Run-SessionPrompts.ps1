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

    Con -Unattended la serie corre SOLA, sin Remote Control y sin /exit: cada sesion se lanza en
    modo no interactivo y es ella la que dice si la serie puede seguir. Es un modo distinto, se
    pide explicitamente, y solo corre series escritas para el. Ver .PARAMETER Unattended.

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
    No hace falta que exista un prompt con ese numero exacto: en una serie 01, 02, 05, un 3
    arranca en el 05. Un numero posterior al ultimo prompt no deja nada que correr, y corta.

.PARAMETER PermissionMode
    Modo de permisos de todas las sesiones de la corrida: se pasa tal cual a
    '--permission-mode'. Valores: acceptEdits (default), auto, bypassPermissions, manual,
    dontAsk, plan. Son los que acepta el CLI, y el runner NO los interpreta: si en una version
    de Claude Code alguno cambia de sentido, cambia igual aca.

    El default sigue siendo 'acceptEdits' (auto-acepta ediciones; igual te puede preguntar por
    comandos, y los respondes desde el celular).

.PARAMETER Auto
    Atajo de '-PermissionMode auto': el modo "Auto" de Claude Code Desktop, donde el modelo
    decide cuando pedir permiso. NO es lo mismo que acceptEdits, que es el default.

.PARAMETER FullAuto
    Atajo de '--dangerously-skip-permissions' (no pregunta nada). Es un flag propio del CLI, no
    un valor de '--permission-mode': con -FullAuto no se pasa '--permission-mode' ninguno.

    Pasar -FullAuto junto con -Auto o con -PermissionMode es un error, no una precedencia
    silenciosa: son dos ordenes distintas sobre lo mismo.

.PARAMETER Unattended
    Corre la serie SIN SUPERVISION: no hay Remote Control, no hay /exit, y no hay nadie que
    conteste. Cada sesion se lanza con 'claude -p' y, al terminar, DEVUELVE si la serie puede
    seguir. Es opt-in: sin este parametro no cambia absolutamente nada del comportamiento de
    siempre.

    Lo que cambia:
      - El modo de permisos es 'auto' (el modo "Auto" del desktop, donde un clasificador
        decide en tu lugar) y NO se elige: pasar -PermissionMode o -FullAuto junto con
        -Unattended es un error. Lo que el clasificador no aprueba queda denegado, la sesion no
        puede hacer el trabajo, y lo reporta -- que es exactamente el freno de abajo.
      - No se pasa --rc: Remote Control es interactivo por definicion. Las sesiones igual
        quedan guardadas, con su nombre, y se pueden abrir despues con 'claude --resume'.
      - La consola muestra lo que la sesion va haciendo (herramienta por herramienta) leyendo
        el stream de eventos, no el dibujo de la TUI, que en -p no existe.

    COMO DECIDE SI SIGUE. Se le pide a cada sesion un resultado estructurado:

        { "result": "ok" | "stop", "reason": "<una o dos frases>" }

    La serie sigue SOLO si se cumple todo:
      1. la corrida termino con exit code 0,
      2. la sesion dejo el resultado estructurado y parsea,
      3. 'result' dice 'ok'.

    Cualquier otra cosa FRENA la serie, incluida la ausencia de resultado. Es a proposito: si
    la falta de senal se leyera como "segui", una sesion que se colgo o se fue por las ramas
    arrastraria el error a todas las que vienen. El 'reason' se imprime siempre, tambien
    cuando dice 'ok'.

    QUE SERIES PUEDE CORRER. Solo las escritas sabiendo que esto existe. Cada prompt tiene que
    declararlo en su encabezado:

        <!-- runner-requerido: 2.0 -->

    Sin esa marca, -Unattended no corre la serie. No es burocracia: un repo con las plantillas
    de una version anterior no tiene documentado el contrato del JSON, asi que sus prompts no
    pueden cumplirlo aunque quieran.

    QUE SESION NO PUEDE CORRER SOLA. Un prompt que necesita un humano lo declara, y con eso el
    runner se niega a correrlo en este modo:

        <!-- automatico: no | hace deploy a produccion -->

    El motivo despues del '|' es opcional y se imprime. La serie corre automatica hasta la
    sesion anterior y FRENA ahi, limpio, diciendote como seguir a mano. Se detecta al arrancar:
    antes de lanzar la primera sesion ya sabes donde va a parar.

.PARAMETER MaxBudgetUsd
    Techo de gasto por sesion, en dolares, que se pasa a '--max-budget-usd'. Solo aplica con
    -Unattended, que es donde no hay nadie mirando: sin techo, una sesion trabada puede quemar
    la noche entera. Cuando se pasa del techo, la sesion corta con exit code distinto de cero
    y la serie frena.

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

    Se resuelve todo antes de lanzar la primera sesion, y el plan se imprime con el modelo y el
    effort de cada una.

.PARAMETER Effort
    Nivel de esfuerzo de razonamiento: low, medium, high (default), xhigh, max. Si no se pasa y
    tampoco esta en la configuracion, el script muestra un MENU (Enter = high).

    Igual que con el modelo, cada prompt puede SUGERIR el suyo con una marca en el .md:

        <!-- effort-sugerido: xhigh -->

    Y vale la misma regla, con el effort de la corrida como TOPE:
      - Sugerido MENOR o IGUAL que el tope -> se usa el de la sesion, sin preguntar.
      - Sugerido MAYOR que el tope         -> el script PARA Y PREGUNTA.
      - Sin marca                          -> el tope, sin ruido.

    O sea que el default de siempre (high) deja pasar solo lo que pida high o menos, y cualquier
    sesion que pida xhigh o max se confirma a mano. Para levantar el tope de toda la corrida,
    -Effort xhigh (o max).

    Si la marca trae un valor que no es ninguno de los cinco, el script CORTA con un error: una
    marca mal escrita que se ignora en silencio es justo lo que este script no hace.

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

.PARAMETER Update
    Se actualiza a la ultima version publicada en GitHub y termina. Baja el release, y lo instala
    con el instalador que viene adentro (o sea que tambien actualiza las plantillas y el README).

.PARAMETER SkipUpdateCheck
    No chequea si hay una version nueva al arrancar. Ese chequeo se hace una vez por dia, contra
    la API de GitHub, con cinco segundos de paciencia; si no hay conexion, la corrida sigue igual.
    Tambien se apaga para siempre con "checkForUpdates": false en session-prompts.config.json.

.PARAMETER SkipClaudeMd
    Al actualizar (-Update, o aceptando la oferta), no corre la sesion de Claude Code que pone al
    dia el CLAUDE.md del repo. Solo aplica a la actualizacion.

.PARAMETER Force
    Solo con -Update: pisa el runner instalado aunque el instalador no lo reconozca como suyo
    (porque esta modificado a mano, o porque es una copia vieja sin marca de version). Antes de
    pisarlo deja una copia .bak al lado.

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
    # En el modo "Auto" del desktop, en vez del acceptEdits de siempre.
    .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Auto

.EXAMPLE
    # La serie corre SOLA, sin Remote Control: cada sesion decide si la siguiente arranca.
    .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Unattended

.EXAMPLE
    # Lo mismo, con un techo de gasto por sesion.
    .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Unattended -MaxBudgetUsd 5

.EXAMPLE
    # La serie corre aislada en su propio worktree, partiendo de main.
    .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Worktree -BaseBranch main

.EXAMPLE
    # Todas las series, incluidas las ya terminadas.
    .\Run-SessionPrompts.ps1 -Todas

.EXAMPLE
    # Tab completa el nombre de la serie que exista bajo la raiz de series.
    .\Run-SessionPrompts.ps1 -PromptsPath <Tab>

.EXAMPLE
    # Actualizar a la ultima version publicada.
    pwsh -File .\Run-SessionPrompts.ps1 -Update

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

    # Los seis modos que acepta 'claude --permission-mode'. 'auto' es el modo "Auto" del
    # desktop, y NO es acceptEdits: son dos modos distintos del CLI.
    [ValidateSet('acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')]
    [string]$PermissionMode,

    # Atajo de '-PermissionMode auto'.
    [switch]$Auto,

    # Corre la serie sin supervision: 'claude -p', sin Remote Control, y cada sesion devuelve
    # si la serie puede seguir. Opt-in: sin esto, nada cambia. Ver la ayuda del parametro.
    [switch]$Unattended,

    # Techo de gasto por sesion (--max-budget-usd). Solo con -Unattended.
    [double]$MaxBudgetUsd,

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

    [switch]$Version,

    [switch]$Update,

    [switch]$SkipUpdateCheck,

    # Se le pasa al instalador cuando se actualiza: asi no corre la sesion que pone al dia el
    # CLAUDE.md del repo.
    [switch]$SkipClaudeMd,

    # Solo con -Update: pisa el runner instalado aunque el instalador no lo reconozca como suyo
    # (modificado a mano, o una copia vieja sin marca de version). Deja un .bak al lado.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$script:RunnerVersion = '2.0.2'

# La primera version que entiende el contrato de -Unattended. Un prompt que declara menos que
# esto no fue escrito para correr sin supervision, aunque el runner instalado sea nuevo.
$script:VersionMinimaDesatendida = [version]'2.0'

if ($Version) {
    Write-Host "Run-SessionPrompts $script:RunnerVersion"
    exit 0
}

# --- La consola tiene que ser UTF-8, y hay que fijarlo YA -------------------
# TODO lo que escribe una sesion de Claude Code vuelve por el stdout de un proceso NATIVO, y
# PowerShell lo decodifica con [Console]::OutputEncoding. Si esa no es UTF-8, cada acento llega
# como mojibake. No depende de -Unattended, pero lo que esta en juego SI es distinto:
#
#   - En -Unattended el canal se PARSEA. Un 'reason' con acentos llega roto EN SILENCIO, porque el
#     JSON sigue parseando igual: es la misma clase de falla que el escapado de argumentos, del
#     otro lado del canal. Ahi no poder fijar la codificacion es fatal y la corrida no arranca.
#   - En una corrida normal el canal solo se MIRA. Una tabla ANSI es una biyeccion byte<->caracter,
#     asi que los bytes originales siguen ahi y lo que se degrada es el dibujo, no el texto: se
#     intenta igual, y si el host no deja, la corrida sigue.
#
# Y manda el proceso pegado a la consola, no el que lanza el .exe: MEDIDO con el runner en la ANSI
# y el instalador en UTF-8 (que es lo que pasa en -Update), la salida de la sesion del CLAUDE.md
# sale rota lo mismo, porque el instalador la reescribe en UTF-8 y el runner la lee en ANSI. Por
# eso el bloque vive en los dos lados.
#
# Va ACA ARRIBA, antes de la primera linea de salida del script, y no al lado del loop: MEDIDO en
# pwsh 7.6.5 con -File, el host se queda con el encoding que tenia cuando escribio por primera vez.
# Fijarlo despues arregla la LECTURA pero deja la ESCRITURA en la codificacion vieja, y entonces una
# corrida redirigida a un archivo queda en la ANSI de la consola en vez de UTF-8.
#
# Es exactamente el mismo motivo por el que los prompts se leen con -Encoding UTF8 explicito: para
# que la corrida no dependa de un default que puede ser otro en otra maquina.
$encodingPrevio = $null
if ([Console]::OutputEncoding.CodePage -ne 65001) {
    try {
        $encodingPrevio = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    } catch {
        $encodingPrevio = $null
        if ($Unattended) {
            Write-Host "No pude poner la consola en UTF-8 ([Console]::OutputEncoding = $([Console]::OutputEncoding.WebName))." -ForegroundColor Red
            Write-Host "En -Unattended el resultado de cada sesion vuelve por ahi: con otra codificacion, un texto" -ForegroundColor Red
            Write-Host "con acentos se corrompe sin que nada falle. Corre esto en una consola UTF-8." -ForegroundColor Red
            exit 1
        }
    }
}

# Desde aca hasta el final: la consola es del usuario, y hay que devolversela como estaba salga la
# corrida por donde salga. 'exit' desenrolla el try, asi que el finally corre igual (medido).
try {

# --- De donde sale una version nueva --------------------------------------
# El producto vive en un repo de GitHub y se publica por releases. El runner no se actualiza
# solo: chequea (una vez por dia, sin bloquear nada) y OFRECE. Bajar e instalar es siempre a
# pedido, y lo hace el instalador que viene adentro del release, no este script.
$script:RepoGitHub = 'apanitsch/RunSessionPrompts'

# El ultimo chequeo se anota en el perfil de la MAQUINA, no en el repo: la carpeta de series
# esta commiteada en el repo destino, y un archivo de cache apareceria ahi como un cambio sin
# explicacion.
# ($env:LOCALAPPDATA primero: GetFolderPath NO la mira -- va a la API de Windows -- y entonces
# no habria forma de correr esto contra un perfil de prueba.)
$script:CarpetaDeEstado = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $env:LOCALAPPDATA
} else {
    [Environment]::GetFolderPath('LocalApplicationData')
}
$script:CacheChequeo = Join-Path $script:CarpetaDeEstado 'RunSessionPrompts\ultimo-chequeo.txt'

function Get-VersionDeTag([string]$tag) {
    if ([string]::IsNullOrWhiteSpace($tag)) { return $null }
    try { return [version]($tag -replace '^v', '') } catch { return $null }
}

# Un pedido HTTP que fallo, fallo por que? Que el servidor haya contestado 404 o 403 no es lo
# mismo que no haber llegado a ningun servidor, y es lo unico que decide si reintentar con 'gh'
# sirve para algo:
#
#   - Hubo respuesta (404 de un repo privado, 403 del limite anonimo): 'gh' usa la credencial del
#     usuario y puede contestar lo que la API anonima no. Vale la pena.
#   - No hubo respuesta (DNS caido, red bloqueada, timeout): no hay red, y 'gh' va a fallar
#     igual. Reintentar solo agrega espera, y 'gh' NO tiene con que acotarse: medido contra una
#     red que traga los paquetes, 'gh api' tarda 21 segundos (el timeout de SYN de Windows) y no
#     hay flag que lo baje. El chequeo de cortesia pasaba de 5 segundos a 26 antes de mostrar el
#     menu, en silencio y una vez por dia. Sin red ninguna (el DNS falla al toque) eran 0,2.
#
# El discriminador es la respuesta: HttpResponseException la trae, y las excepciones de conexion
# (HttpRequestException) y de timeout (TaskCanceledException) no.
function Test-HuboRespuestaHttp($errorRecord) {
    return ($null -ne $errorRecord.Exception.Response)
}

# El tag del ultimo release, o $null si no se pudo averiguar. NUNCA tira ni corta la corrida:
# no poder chequear no es un error, es no saber.
function Get-UltimoReleasePublicado {
    # Override para probar, o para una maquina que llega al producto por otro lado (un mirror
    # interno, un archivo copiado a mano). Acepta una URL o la ruta a un JSON.
    $fuente = $env:SESSION_PROMPTS_RELEASES_URL
    if ([string]::IsNullOrWhiteSpace($fuente)) {
        $fuente = "https://api.github.com/repos/$script:RepoGitHub/releases/latest"
    }

    # Que el servidor CONTESTE (aunque sea un error) y que no haya red son dos cosas distintas,
    # y de ahi depende si tiene sentido reintentar con 'gh'. Ver Test-HuboRespuestaHttp.
    $huboRespuesta = $false

    try {
        if ($fuente -notmatch '^https?://') {
            if (-not (Test-Path -LiteralPath $fuente)) { return $null }
            $json = Get-Content -LiteralPath $fuente -Raw -Encoding UTF8 | ConvertFrom-Json
        } else {
            $json = Invoke-RestMethod -Uri $fuente -TimeoutSec 5 -Headers @{ 'User-Agent' = 'Run-SessionPrompts' }
        }
        $huboRespuesta = $true
        if ($json.tag_name) { return [string]$json.tag_name }
    } catch {
        $huboRespuesta = Test-HuboRespuestaHttp $_
    }

    # Mientras el repo sea privado, la API anonima contesta 404. 'gh' usa la credencial del
    # usuario y sirve para las dos etapas.
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh -and $huboRespuesta -and $fuente -match '^https?://api\.github\.com') {
        try {
            $salida = & $gh.Source api "repos/$script:RepoGitHub/releases/latest" 2>$null
            if ($LASTEXITCODE -eq 0 -and $salida) {
                $json = (($salida | ForEach-Object { "$_" }) -join '') | ConvertFrom-Json
                if ($json.tag_name) { return [string]$json.tag_name }
            }
        } catch { }
    }

    return $null
}

# Baja el .zip del release y devuelve su ruta, o $null.
function Get-ZipDelRelease([string]$tag) {
    if (-not [string]::IsNullOrWhiteSpace($env:SESSION_PROMPTS_RELEASE_ZIP)) {
        if (Test-Path -LiteralPath $env:SESSION_PROMPTS_RELEASE_ZIP) { return $env:SESSION_PROMPTS_RELEASE_ZIP }
        Write-Host "SESSION_PROMPTS_RELEASE_ZIP apunta a algo que no existe: $env:SESSION_PROMPTS_RELEASE_ZIP" -ForegroundColor Red
        return $null
    }

    $destino = Join-Path ([System.IO.Path]::GetTempPath()) ("run-session-prompts-$tag.zip")

    $huboRespuesta = $false
    try {
        Invoke-WebRequest -Uri "https://github.com/$script:RepoGitHub/archive/refs/tags/$tag.zip" `
                          -OutFile $destino -TimeoutSec 120 -Headers @{ 'User-Agent' = 'Run-SessionPrompts' }
        $huboRespuesta = $true
        if (Test-Path -LiteralPath $destino) { return $destino }
    } catch {
        $huboRespuesta = Test-HuboRespuestaHttp $_
    }

    # Mismo criterio que arriba: sin red, 'gh' no tiene nada que agregar.
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh -and $huboRespuesta) {
        & $gh.Source release download $tag --repo $script:RepoGitHub --archive=zip --output $destino --clobber 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $destino)) { return $destino }
    }

    return $null
}

# Baja el release y lo instala en ESTE repo con el instalador que viene adentro. El trabajo real
# lo hace ese instalador: asi la logica de instalacion vive en un solo lado, y una version nueva
# puede cambiarla sin depender de lo que sepa hacer el runner viejo.
function Invoke-Actualizacion([string]$tag) {
    Write-Host "Bajando $tag..." -ForegroundColor Cyan
    $zip = Get-ZipDelRelease $tag
    if (-not $zip) {
        Write-Host "No pude bajar el release $tag." -ForegroundColor Red
        Write-Host "Probalo a mano: https://github.com/$script:RepoGitHub/releases" -ForegroundColor DarkGray
        return $false
    }

    $carpeta = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-release-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Expand-Archive -LiteralPath $zip -DestinationPath $carpeta -Force
    } catch {
        Write-Host "No pude descomprimir $zip : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    $inst = @(Get-ChildItem -LiteralPath $carpeta -Filter 'Install-SessionPrompts.ps1' -Recurse -Depth 2 |
              Select-Object -First 1)
    if ($inst.Count -eq 0) {
        Write-Host "El release no trae Install-SessionPrompts.ps1." -ForegroundColor Red
        return $false
    }

    Write-Host "Instalando con $($inst[0].FullName)" -ForegroundColor DarkGray
    $argsInstalador = @('-NoProfile', '-File', $inst[0].FullName, '-Repo', $SeriesRoot, '-SeriesRoot', $SeriesRoot)
    if ($SkipClaudeMd) { $argsInstalador += '-SkipClaudeMd' }
    if ($Force)        { $argsInstalador += '-Force' }

    # | Out-Host, y no a secas: la salida de un comando nativo adentro de una funcion se va al
    # stream de SALIDA, o sea que terminaria siendo el valor de retorno. Un array no vacio es
    # verdadero, y un fallo del instalador se leeria como exito.
    & pwsh @argsInstalador | Out-Host
    $code = $LASTEXITCODE

    if ($code -eq 2) {
        # El instalador se niega a pisar un runner que no puso el (modificado a mano, o una copia
        # vieja sin marca de version). Es el caso de todos los repos que todavia tienen la copia
        # que se copiaba y pegaba.
        Write-Host ""
        Write-Host "No actualice nada. Si ya miraste el diff y queres pisarlo igual:" -ForegroundColor Yellow
        Write-Host "  pwsh -File `"$PSCommandPath`" -Update -Force" -ForegroundColor DarkGray
        return $false
    }
    if ($code -ne 0) {
        Write-Host "El instalador salio con codigo $code." -ForegroundColor Yellow
        return $false
    }
    return $true
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

# Lo que el archivo puede decir, con el tipo de cada clave. Es la lista completa: una clave
# que no este aca es un error, no algo que se ignora. Un typo ('modelo' por 'model', 'worktrees'
# por 'worktree') no cambia nada visible -- el script simplemente pregunta, o corre sin aislar --
# y se descubre cuando ya corrio media serie donde no era.
# Las claves que empiezan con '_' son comentarios de la propia plantilla y no se miran.
$script:ConfigEsquema = [ordered]@{
    'model'           = 'texto'
    'effort'          = 'texto'
    'fullAuto'        = 'booleano'
    'permissionMode'  = 'texto'
    'worktree'        = 'booleano'
    'baseBranch'      = 'texto'
    'branchPrefix'    = 'texto'
    'worktreeRoot'    = 'texto'
    'checkForUpdates' = 'booleano'
    'claudeCommand'   = 'texto'
    'maxPromptChars'  = 'entero'
}

# La conocida mas parecida a una clave mal escrita, o $null. Alcanza con prefijo comun o
# contencion: cubre 'modelo', 'Model ', 'worktrees', 'effor', que son los typos que pasan.
function Get-ClaveParecida([string]$clave) {
    $c = $clave.ToLowerInvariant()
    foreach ($conocida in $script:ConfigEsquema.Keys) {
        $k = $conocida.ToLowerInvariant()
        if ($c.StartsWith($k) -or $k.StartsWith($c) -or $c.Contains($k) -or $k.Contains($c)) { return $conocida }
    }
    return $null
}

function Test-TipoDeConfig($valor, [string]$tipo) {
    switch ($tipo) {
        'texto'    { return ($valor -is [string]) }
        'booleano' { return ($valor -is [bool]) }
        'entero'   { return (($valor -is [int]) -or ($valor -is [long])) -and ([long]$valor -gt 0) }
    }
    return $false
}

# El archivo entero, de una: todos los problemas juntos y recien despues el corte. Corregir uno
# por corrida, cada una con su error, es peor que verlos todos.
function Test-RunnerConfig {
    if ($null -eq $script:Config) { return }

    $problemas = @()
    foreach ($prop in $script:Config.PSObject.Properties) {
        $clave = $prop.Name
        if ($clave.StartsWith('_')) { continue }   # comentario de la plantilla

        $conocida = @($script:ConfigEsquema.Keys | Where-Object { $_ -eq $clave })
        if ($conocida.Count -eq 0) {
            $parecida = Get-ClaveParecida $clave
            $sugerencia = if ($parecida) { " Quisiste decir '$parecida'?" } else { "" }
            $problemas += "clave desconocida: '$clave'.$sugerencia"
            continue
        }

        # null = "no la fijo", que es como viene la plantilla. Siempre valido.
        if ($null -eq $prop.Value) { continue }

        $tipo = $script:ConfigEsquema[$conocida[0]]
        if (-not (Test-TipoDeConfig $prop.Value $tipo)) {
            # Un booleano de PowerShell se imprime 'True'; en el archivo se escribe 'true'.
            $comoLlego = if ($prop.Value -is [string]) { "`"$($prop.Value)`"" }
                         elseif ($prop.Value -is [bool]) { if ($prop.Value) { 'true' } else { 'false' } }
                         else { [string]$prop.Value }
            $esperado = switch ($tipo) {
                'texto'    { 'un texto entre comillas' }
                'booleano' { 'true o false, sin comillas' }
                'entero'   { 'un numero entero mayor que cero, sin comillas' }
            }
            $problemas += "'$clave' = $comoLlego : tiene que ser $esperado."
        }
    }

    if ($problemas.Count -gt 0) {
        $titulo = if ($problemas.Count -eq 1) { "Hay un problema en" } else { "Hay $($problemas.Count) problemas en" }
        Write-Host "$titulo $script:ConfigPath :" -ForegroundColor Red
        foreach ($p in $problemas) { Write-Host "  - $p" -ForegroundColor Red }
        Write-Host "Claves validas: $(($script:ConfigEsquema.Keys) -join ', ')." -ForegroundColor DarkGray
        Write-Host "(Las que empiezan con '_' son comentarios y se ignoran.)" -ForegroundColor DarkGray
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
Test-RunnerConfig

# Ahora que hay config, se resuelven los valores que salen de ella.
$ClaudeCommand = Resolve-Setting 'claudeCommand' $ClaudeCommand 'claude'
$BranchPrefix  = Resolve-Setting 'branchPrefix'  $BranchPrefix  'sesiones'
$BaseBranch    = Resolve-Setting 'baseBranch'    $BaseBranch    ''
$WorktreeRoot  = Resolve-Setting 'worktreeRoot'  $WorktreeRoot  ''
$usaWorktree   = Resolve-SwitchSetting 'worktree' $PSBoundParameters.ContainsKey('Worktree') ([bool]$Worktree) $false

# --- Permisos: un solo modo para toda la corrida --------------------------
# Tres maneras de decir lo mismo (-PermissionMode, su atajo -Auto, y -FullAuto, que no es un
# modo sino otro flag del CLI), asi que dos de ellas juntas son una contradiccion, no una
# precedencia: se corta. Un modo que se ignora en silencio es exactamente lo que este script
# no hace.
$script:ModosDePermiso = @('acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')

$modoPasado     = $PSBoundParameters.ContainsKey('PermissionMode')
$autoPasado     = $PSBoundParameters.ContainsKey('Auto') -and [bool]$Auto
$fullAutoPasado = $PSBoundParameters.ContainsKey('FullAuto') -and [bool]$FullAuto
$desatendida       = [bool]$Unattended

# En -Unattended el modo de permisos NO se elige: es 'auto' y punto. Sin humano que conteste, un
# clasificador que decide es el unico punto medio que queda -- 'acceptEdits' dejaria a la sesion
# sin poder correr comandos, y 'bypassPermissions' la dejaria sin ningun freno. Pedir otro modo
# es pedir algo que este modo no hace, asi que se corta en vez de ignorarlo.
# (-Auto y '-PermissionMode auto' dicen lo mismo que ya va a pasar: no molestan.)
if ($desatendida -and $fullAutoPasado) {
    Write-Host "-Unattended corre siempre con '--permission-mode auto', y -FullAuto pide no preguntar nada." -ForegroundColor Red
    Write-Host "Son dos cosas distintas. Sacale uno de los dos." -ForegroundColor DarkGray
    exit 1
}
if ($desatendida -and $modoPasado -and $PermissionMode -ne 'auto') {
    Write-Host "-Unattended corre siempre con '--permission-mode auto', y pediste '-PermissionMode $PermissionMode'." -ForegroundColor Red
    Write-Host "Sacale el -PermissionMode, o corre la serie sin -Unattended." -ForegroundColor DarkGray
    exit 1
}
if ($PSBoundParameters.ContainsKey('MaxBudgetUsd') -and -not $desatendida) {
    Write-Host "-MaxBudgetUsd solo aplica con -Unattended: es el techo de una sesion que corre sin nadie mirando." -ForegroundColor Red
    exit 1
}
if ($PSBoundParameters.ContainsKey('MaxBudgetUsd') -and $MaxBudgetUsd -le 0) {
    Write-Host "-MaxBudgetUsd tiene que ser mayor que cero (llego '$MaxBudgetUsd')." -ForegroundColor Red
    exit 1
}

if ($autoPasado -and $modoPasado -and $PermissionMode -ne 'auto') {
    Write-Host "-Auto es el atajo de '-PermissionMode auto', y pediste '-PermissionMode $PermissionMode'." -ForegroundColor Red
    Write-Host "Elegi uno de los dos." -ForegroundColor DarkGray
    exit 1
}
if ($fullAutoPasado -and ($autoPasado -or $modoPasado)) {
    $otro = if ($modoPasado) { "-PermissionMode $PermissionMode" } else { '-Auto' }
    Write-Host "-FullAuto (--dangerously-skip-permissions) y $otro piden dos cosas distintas." -ForegroundColor Red
    Write-Host "Elegi uno de los dos. Para no preguntar nada, -FullAuto; para el modo Auto del desktop, -Auto." -ForegroundColor DarkGray
    exit 1
}

# Un parametro explicito le gana a la configuracion, de los dos lados: -FullAuto anula un
# 'permissionMode' del archivo, y -Auto/-PermissionMode anulan un '"fullAuto": true'.
$modoExplicito = if ($modoPasado) { $PermissionMode } elseif ($autoPasado) { 'auto' } else { '' }

$fullAuto = if ($modoExplicito) { $false }
            else { Resolve-SwitchSetting 'fullAuto' $PSBoundParameters.ContainsKey('FullAuto') ([bool]$FullAuto) $false }

$modoPermiso = ''
if (-not $fullAuto) {
    $modoPermiso = Resolve-Setting 'permissionMode' $modoExplicito 'acceptEdits'
    if (-not ($script:ModosDePermiso -contains $modoPermiso)) {
        Write-Host "Modo de permisos desconocido: '$modoPermiso'. Validos: $($script:ModosDePermiso -join ', ')." -ForegroundColor Red
        exit 1
    }
} elseif (-not $fullAutoPasado -and $null -ne (Get-ConfigValue 'permissionMode')) {
    # Los dos salen del archivo: nadie desempata.
    Write-Host "La configuracion pide 'fullAuto': true y ademas 'permissionMode'. Son dos cosas distintas." -ForegroundColor Red
    Write-Host "Dejate una sola en $script:ConfigPath." -ForegroundColor DarkGray
    exit 1
}

# -Unattended fija el modo, tambien contra la configuracion del repo. Ahi no se corta -- el archivo
# es de todo el repo y -Unattended es de ESTA corrida --, pero se DICE: un modo que se ignora en
# silencio es lo mismo que este script no hace en ningun otro lado.
if ($desatendida) {
    # Solo lo que el ARCHIVO pide: el 'acceptEdits' que sale del default no lo puso nadie, y
    # avisar que se pisa un valor que nadie escribio es ruido.
    $pisado = if ($fullAuto -and $null -ne (Get-ConfigValue 'fullAuto')) { "'fullAuto': true" }
              elseif ($modoPermiso -ne 'auto' -and $null -ne (Get-ConfigValue 'permissionMode')) { "'permissionMode': '$modoPermiso'" }
              else { '' }
    if ($pisado -and -not $modoPasado -and -not $autoPasado) {
        Write-Host "-Unattended: la configuracion del repo dice $pisado, y en este modo el permiso es 'auto'. Uso 'auto'." -ForegroundColor Yellow
    }
    $fullAuto    = $false
    $modoPermiso = 'auto'
}

# Los tres parametros del worktree no hacen NADA si la serie no corre aislada. Pasarlos y que no
# pase nada se lee como que se aplicaron: quien los paso cree que la serie va a salir de esa rama.
# No es un error (el resto de la corrida es exactamente lo que se pidio), pero se dice.
if (-not $usaWorktree) {
    $sinEfecto = @('BaseBranch', 'BranchPrefix', 'WorktreeRoot') |
        Where-Object { $PSBoundParameters.ContainsKey($_) }
    if ($sinEfecto.Count -gt 0) {
        $lista = ($sinEfecto | ForEach-Object { "-$_" }) -join ', '
        Write-Host "$lista no se aplican sin -Worktree: la serie corre en el checkout donde estas." -ForegroundColor Yellow
    }
}

# CreateProcess corta en 32767 caracteres TODA la linea de comandos: la ruta del ejecutable,
# los flags, el nombre de la sesion y el prompt ya escapado. Por eso el corte NO se hace sobre
# el largo del prompt (ver Test-EntraEnLaLineaDeComandos mas abajo): un numero fijo se equivoca
# en las dos direcciones, y esta MEDIDO que se equivoca.
$script:TechoLineaDeComandos = 32767

# Margen: el techo es del sistema operativo y no queremos quedar justo contra el borde por una
# diferencia de un caracter entre lo que estimamos y lo que PowerShell arma.
$script:MargenLineaDeComandos = 128

# Tope opcional y ADICIONAL sobre el largo crudo del prompt, para el que quiera mantener sus
# prompts cortos por politica. Sin esta clave no hay tope propio: manda el del sistema.
$maxPromptChars = 0
$cfgMax = Get-ConfigValue 'maxPromptChars'
if ($null -ne $cfgMax -and [int]$cfgMax -gt 0) { $maxPromptChars = [int]$cfgMax }

function Get-PromptSeries { Get-SeriesEnRaiz $SeriesRoot }


# --- Chequeo de version, y la oferta --------------------------------------
# Aca arriba de todo, antes de cualquier menu: si hay algo que decidir, se decide antes de
# lanzar la primera sesion. Y si no hay conexion, no pasa nada: la corrida sigue.
if ($Update) {
    $tag = Get-UltimoReleasePublicado
    if (-not $tag) {
        Write-Host "No pude averiguar cual es la ultima version publicada." -ForegroundColor Red
        Write-Host "Mira https://github.com/$script:RepoGitHub/releases" -ForegroundColor DarkGray
        exit 1
    }

    $nueva = Get-VersionDeTag $tag
    $actual = Get-VersionDeTag $script:RunnerVersion
    if ($nueva -and $actual -and $nueva -le $actual) {
        Write-Host "Ya estas en la ultima version publicada ($script:RunnerVersion)." -ForegroundColor Green
        exit 0
    }

    if (Invoke-Actualizacion $tag) {
        Write-Host ""
        Write-Host "Actualizado a $tag. Volve a correr el script." -ForegroundColor Green
        exit 0
    }
    exit 1
}

function Test-TocaChequear {
    if ($SkipUpdateCheck) { return $false }

    $cfg = Get-ConfigValue 'checkForUpdates'
    if ($null -ne $cfg -and -not [bool]$cfg) { return $false }

    # Una vez por dia alcanza: esto no es un canal de seguridad, es un aviso de cortesia.
    if (Test-Path -LiteralPath $script:CacheChequeo) {
        $ultimo = (Get-Content -LiteralPath $script:CacheChequeo -Raw -ErrorAction SilentlyContinue).Trim()
        if ($ultimo -eq (Get-Date).ToString('yyyy-MM-dd')) { return $false }
    }
    return $true
}

if (Test-TocaChequear) {
    # Se anota ANTES de preguntar: si la red esta caida o tarda, no queremos pagar la espera en
    # cada corrida del dia.
    try {
        $dir = Split-Path -Parent $script:CacheChequeo
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $script:CacheChequeo -Value (Get-Date).ToString('yyyy-MM-dd') -Encoding UTF8
    } catch { }

    $tag = Get-UltimoReleasePublicado
    $nueva = Get-VersionDeTag $tag
    $actual = Get-VersionDeTag $script:RunnerVersion

    if ($nueva -and $actual -and $nueva -gt $actual) {
        Write-Host ""
        Write-Host "Hay una version nueva de Run-SessionPrompts: $tag (tenes la $script:RunnerVersion)." -ForegroundColor Yellow
        Write-Host "  https://github.com/$script:RepoGitHub/blob/main/CHANGELOG.md" -ForegroundColor DarkGray
        Write-Host "  [1] Actualizar ahora. Instala el release en este repo y termina, para que arranques limpio  (default)"
        Write-Host "  [2] Seguir con la $script:RunnerVersion"

        $ans = Read-Host "Elegi el numero (Enter = 1)"
        if ([string]::IsNullOrWhiteSpace($ans) -or $ans -eq '1') {
            if (Invoke-Actualizacion $tag) {
                Write-Host ""
                Write-Host "Actualizado a $tag. Volve a correr el script." -ForegroundColor Green
                exit 0
            }
            Write-Host "Sigo con la $script:RunnerVersion." -ForegroundColor Yellow
        } elseif ($ans -ne '2') {
            Write-Host "Valor invalido: '$ans'. Tiene que ser 1 o 2." -ForegroundColor Red
            exit 1
        }
    }
}

# --- El estado de las series (series-estado.txt) ---------------------------
# Archivo propio de ESTE script: nada mas del sistema lo lee, y si no existe el script
# funciona igual (muestra todas, alfabetico). Ver el encabezado del .txt para el formato.
$estadoPath = Join-Path $SeriesRoot 'series-estado.txt'

# Una linea de datos: <estado> <orden> <serie>, y despues nada o un comentario. El nombre de la
# serie no puede tener espacios (es un nombre de carpeta en kebab-case) y por eso se exige que la
# linea termine ahi: 'terminada - mi serie' se leeria como la serie 'mi', y nadie se enteraria.
$script:LineaDeEstado = '^(pendiente|terminada)\s+(\S+)\s+(\S+)\s*(#.*)?$'

# Las lineas que no se entienden CORTAN, no se ignoran. Una serie mal escrita aparece como
# pendiente cuando esta terminada, o al reves, y eso no se nota mirando el menu -- es la misma
# clase de degradacion silenciosa que el script no se permite en ningun otro lado.
function Assert-SeriesEstadoValido {
    if (-not (Test-Path -LiteralPath $estadoPath)) { return }

    $malas = @()
    $n = 0
    foreach ($linea in (Get-Content -LiteralPath $estadoPath -Encoding UTF8)) {
        $n++
        $t = $linea.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -notmatch $script:LineaDeEstado) { $malas += [pscustomobject]@{ Numero = $n; Texto = $t } }
    }

    if ($malas.Count -eq 0) { return }

    Write-Host "No entiendo estas lineas de $estadoPath :" -ForegroundColor Red
    foreach ($m in $malas) { Write-Host ("  linea {0}: [{1}]" -f $m.Numero, $m.Texto) -ForegroundColor Red }
    Write-Host ""
    Write-Host "El formato de una linea es:" -ForegroundColor Yellow
    Write-Host "  <pendiente|terminada> <orden|-> <serie>        # comentario opcional" -ForegroundColor DarkGray
    Write-Host "El nombre de la serie es el de la carpeta, sin espacios. Las lineas vacias y las que" -ForegroundColor DarkGray
    Write-Host "empiezan con # se ignoran. Borrar el archivo tambien es valido: el menu vuelve a" -ForegroundColor DarkGray
    Write-Host "mostrar todas las series, en orden alfabetico." -ForegroundColor DarkGray
    exit 1
}

function Get-SeriesEstado {
    $mapa = @{}
    if (-not (Test-Path -LiteralPath $estadoPath)) { return $mapa }

    foreach ($linea in (Get-Content -LiteralPath $estadoPath -Encoding UTF8)) {
        $t = $linea.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }

        # Lo malformado ya corto en Assert-SeriesEstadoValido, arriba de todo.
        $m = [regex]::Match($t, $script:LineaDeEstado)
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

# Si el archivo de estado esta mal escrito, se dice ahora y se corta. Va aca y no adentro del
# menu porque con -PromptsPath el menu no se abre, y el archivo igual se reescribe al cerrar.
Assert-SeriesEstadoValido

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

# El menu solo acepta digitos, pero por parametro se puede pasar un negativo: correrlo como si
# fuera 0 seria hacer algo distinto de lo que se pidio, en silencio.
if ($StartFrom -lt 0) {
    Write-Host "-StartFrom no puede ser negativo (era $StartFrom). 0 o vacio = desde el primero." -ForegroundColor Red
    exit 1
}

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
        # Sin esto, un Enter deja $PromptsPath vacio, el script sigue preguntando modelo y
        # effort, y recien despues corta con "No existe la carpeta: " (sin carpeta).
        if ([string]::IsNullOrWhiteSpace($PromptsPath)) {
            Write-Host "No elegiste ninguna carpeta." -ForegroundColor Red
            exit 1
        }
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
        } elseif ($ans -match '^\d+$') {
            # Sin esto, un numero fuera de la lista caia en la rama de abajo y se tomaba como
            # RUTA: el script seguia preguntando desde-donde, modelo y effort, y recien al final
            # cortaba con "No existe la carpeta: 7". Un numero es un numero, y si no esta en el
            # menu es un error aca mismo.
            Write-Host "Valor invalido: '$ans'. El menu va de 1 a $($series.Count)." -ForegroundColor Red
            exit 1
        } elseif (-not [string]::IsNullOrWhiteSpace($ans)) {
            $PromptsPath = $ans   # ruta pegada a mano
        } else {
            Write-Host "No elegiste ninguna serie." -ForegroundColor Red
            exit 1
        }
    }
}

# --- La serie ya elegida: carpeta y prompts --------------------------------
# Se resuelve ACA, y no mas abajo, por dos motivos. Uno: que la carpeta no exista, o que no
# tenga prompts, tiene que saltar AHORA y no despues de preguntar desde-donde, modelo y effort.
# Dos: el numero de inicio se valida contra los prompts que hay, y para eso hay que conocerlos.
if (-not (Test-Path -LiteralPath $PromptsPath)) {
    Write-Host "No existe la carpeta: $PromptsPath" -ForegroundColor Red
    exit 1
}

# Numero al inicio del nombre (01-foo.md -> 1). Sirve para ordenar y filtrar.
function Get-PromptNumber($name) { [int]($name -replace '^(\d+).*$', '$1') }

# Solo los .md que empiezan con numero: README.md y ESTADO.md no son prompts.
# Orden numerico: 01-, 02- ... 10- (no alfabetico, para que 10 no venga antes que 2).
# OJO: se resuelven ACA, con .FullName ABSOLUTO, ANTES de cambiar de directorio. Asi el loop
# nunca depende de que $PromptsPath sea relativo (podria serlo).
# @() para que un solo prompt (o ninguno) siga teniendo .Count.
$prompts = @(Get-ChildItem -LiteralPath $PromptsPath -Filter *.md |
    Where-Object { $_.Name -match '^\d+' } |
    Sort-Object { Get-PromptNumber $_.Name }, Name)

if ($prompts.Count -eq 0) {
    Write-Host "No hay prompts .md para ejecutar en $PromptsPath" -ForegroundColor Yellow
    Write-Host "Una serie son .md que empiezan con numero (01-..., 02-...): README.md y ESTADO.md no cuentan." -ForegroundColor DarkGray
    exit 1
}

# Nombre de la serie (la carpeta). Va en el nombre de cada sesion, y de el salen la rama y el
# worktree cuando la corrida es aislada.
$serie = (Get-Item -LiteralPath $PromptsPath).Name
$ultimoNumero = Get-PromptNumber $prompts[-1].Name

if (-not $PSBoundParameters.ContainsKey('StartFrom')) {
    $ans = Read-Host "Empezar desde el numero (Enter = desde el primero; la serie llega hasta el $ultimoNumero)"
    if ([string]::IsNullOrWhiteSpace($ans)) {
        $StartFrom = 0
    } elseif ($ans -match '^\d+$') {
        $StartFrom = [int]$ans
    } else {
        Write-Host "Valor invalido: '$ans'. Tiene que ser un numero." -ForegroundColor Red
        exit 1
    }
}

# Un numero de inicio mas grande que el ultimo prompt no saltea nada: no deja NADA para correr.
# Antes eso se descubria recien despues de contestar modelo y effort, y el error solo decia que
# no habia prompts -- que es tambien lo que dice una carpeta vacia, que se arregla de otra
# forma. No se exige que exista un prompt con ese numero exacto: -StartFrom 3 en una serie
# 01, 02, 05 arranca en el 05, que es exactamente lo que se pidio.
if ($StartFrom -gt $ultimoNumero) {
    Write-Host "No hay nada para correr desde el $StartFrom." -ForegroundColor Red
    Write-Host ("La serie '{0}' tiene {1} prompts y el ultimo es el {2}: {3}" -f $serie, $prompts.Count, $ultimoNumero, $prompts[-1].Name) -ForegroundColor DarkGray
    exit 1
}

# --- Modelo y effort ------------------------------------------------------
# Mismo criterio que el menu de series: numeritos, sin tipear nombres. Enter toma el default
# (opus / high), que es lo que corre una sesion de serie normalmente.
$modelos = @(
    @{ Alias = 'opus';   Id = 'claude-opus-5';   Etiqueta = 'Opus 5' },
    @{ Alias = 'sonnet'; Id = 'claude-sonnet-5'; Etiqueta = 'Sonnet 5' }
)

# Ojo con el ValidateSet del parametro: PowerShell lo revalida en CADA asignacion a $Model, asi
# que asignarle '' -- lo que devuelve Resolve-Setting cuando no hay ni parametro ni config --
# aborta el script. Por eso se resuelve aparte y solo se asigna un alias ya valido.
$modelPedido = Resolve-Setting 'model' $Model ''
if (-not [string]::IsNullOrWhiteSpace($modelPedido)) {
    if (-not ($modelos.Alias -contains $modelPedido)) {
        Write-Host "Modelo desconocido en la configuracion: '$modelPedido'. Validos: $($modelos.Alias -join ', ')." -ForegroundColor Red
        exit 1
    }
    $Model = $modelPedido
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

# Mismo cuidado que con $Model: el ValidateSet del parametro se revalida en cada asignacion.
$effortPedido = Resolve-Setting 'effort' $Effort ''
if (-not [string]::IsNullOrWhiteSpace($effortPedido)) {
    if (-not ($efforts -contains $effortPedido)) {
        Write-Host "Effort desconocido en la configuracion: '$effortPedido'. Validos: $($efforts -join ', ')." -ForegroundColor Red
        exit 1
    }
    $Effort = $effortPedido
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

# Los permisos son iguales para todas las sesiones de la corrida. El MODELO y el EFFORT no:
# cada prompt puede sugerir los suyos (ver el bloque "Modelo y effort sugeridos por sesion" mas
# abajo), asi que '--model' y '--effort' se agregan por sesion.
# (Dentro de una sesion se pueden cambiar con /model y /effort, o verificar con /status.)
# Remote Control (--rc) se agrega por sesion, con nombre, mas abajo.
$claudeArgs = @()
if ($fullAuto) {
    $claudeArgs += '--dangerously-skip-permissions'
} else {
    $claudeArgs += @('--permission-mode', $modoPermiso)
}

# --- El contrato de -Unattended ---------------------------------------------
# En este modo la sesion no habla con nadie: lo unico que el runner puede leer de ella es el
# resultado estructurado. '--json-schema' no hace que el modelo imprima JSON en su prosa -- fuerza
# una llamada a la herramienta StructuredOutput que el propio CLI valida --, asi que el resultado
# no comparte canal con el texto y no puede confundirse con nada que la sesion haya escrito.
#
# El esquema dice la FORMA; el system prompt de abajo dice CUANDO va cada valor. Las dos mitades
# tienen que viajar juntas: un esquema sin la regla deja a la sesion adivinando que es "ok".
$script:EsquemaResultado = '{"type":"object","properties":{"result":{"type":"string","enum":["ok","stop"]},"reason":{"type":"string"}},"required":["result","reason"],"additionalProperties":false}'

# Va por --append-system-prompt y no por el README del repo destino a proposito: asi llega
# SIEMPRE, en todas las sesiones, sin depender de que el agente lea un archivo ni de que el autor
# del prompt se haya acordado. Y viaja versionado con el runner, que es lo que lo hace servir en
# cualquier repo sin editar nada.
$script:ContratoDesatendida = @'
Esta sesion corre SIN SUPERVISION HUMANA, como parte de una serie que un runner ejecuta de
punta a punta. Nadie esta mirando la consola mientras trabajas y nadie puede contestarte.

Al terminar devolves un resultado estructurado con dos campos:

  result: "ok"   si hiciste lo que el prompt pedia y la proxima sesion de la serie puede
                 arrancar sobre lo que dejaste.
          "stop" si NO lo lograste, si quedo a medias, o si encontraste algo que hace que
                 seguir con la proxima sesion sea una mala idea.

  reason: una o dos frases para un humano que va a leer esto despues, sin la sesion a la
          vista. Va SIEMPRE, tambien cuando result es "ok": ahi resumis que hiciste.

Ante la duda, "stop". Una serie frenada de mas cuesta una corrida; una serie que sigue sobre
una sesion que fallo le arrastra el error a todas las que vienen.

Si el prompt necesita una decision humana, no la inventes: devolve "stop" diciendo que
decision hace falta. Lo mismo si te falta un permiso, una credencial o un dato que no esta.
'@

# Un resumen de una linea de lo que la herramienta va a hacer. Lo que la TUI dibuja (cajas,
# diffs, spinners) no viaja por el stream: viaja la conversacion, y el dibujo lo hace la TUI, que
# en -p no existe. Asi que el formato de consola de este modo lo define el runner.
function Get-ResumenHerramienta($nombre, $entrada) {
    if ($null -eq $entrada) { return '' }
    $valor = switch ($nombre) {
        'Bash'         { $entrada.command }
        'Read'         { $entrada.file_path }
        'Write'        { $entrada.file_path }
        'Edit'         { $entrada.file_path }
        'NotebookEdit' { $entrada.notebook_path }
        'Glob'         { $entrada.pattern }
        'Grep'         { $entrada.pattern }
        'Agent'        { $entrada.description }
        'Task'         { $entrada.description }
        'WebFetch'     { $entrada.url }
        default        { ($entrada | ConvertTo-Json -Compress -Depth 4) }
    }
    if ($null -eq $valor) { return '' }
    $unaLinea = ([string]$valor) -replace '\s+', ' '
    if ($unaLinea.Length -gt 100) { return $unaLinea.Substring(0, 97) + '...' }
    return $unaLinea
}

# Corre UNA sesion desatendida -- headless del lado del CLI -- y va imprimiendo lo que hace,
# leyendo el stream de eventos NDJSON.
# Devuelve el exit code, el resultado estructurado (o $null si no llego), y lo ultimo que la
# sesion estaba haciendo -- que es lo que hace falta para diagnosticar una sesion que termino
# sin dejar resultado.
function Invoke-SesionDesatendida([string]$exe, [string[]]$argumentos) {
    # Con alcance 'script' a proposito: el bloque de ForEach-Object corre en un alcance HIJO, y
    # una asignacion comun ahi adentro crearia una variable nueva en vez de tocar esta. El
    # resultado se perderia y toda sesion se leeria como "no dejo resultado".
    $script:DsEstructurado = $null
    $script:DsHuboResult   = $false
    $script:DsUltimo       = ''

    & $exe @argumentos | ForEach-Object {
        $linea = "$_"
        if ([string]::IsNullOrWhiteSpace($linea)) { return }

        $ev = $null
        try { $ev = $linea | ConvertFrom-Json } catch { }

        # Una linea que no es JSON no se descarta: puede ser un aviso del CLI, y tragarselo
        # seria degradar en silencio.
        if ($null -eq $ev) {
            Write-Host "    $linea" -ForegroundColor DarkGray
            return
        }

        # InvariantCulture: en un formato custom, ':' no es un literal sino el SEPARADOR HORARIO de
        # la cultura. Con otra configuracion regional la hora del log saldria con otro caracter.
        $hora = (Get-Date).ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)

        switch ($ev.type) {
            'assistant' {
                foreach ($bloque in @($ev.message.content)) {
                    if ($bloque.type -eq 'text' -and -not [string]::IsNullOrWhiteSpace($bloque.text)) {
                        $texto = $bloque.text.Trim()
                        Write-Host "  [$hora] $texto" -ForegroundColor Gray
                        # Lo ultimo que la sesion dijo, recortado: es el diagnostico de una
                        # sesion que despues termina sin dejar resultado.
                        $corto = ($texto -replace '\s+', ' ')
                        if ($corto.Length -gt 80) { $corto = $corto.Substring(0, 77) + '...' }
                        $script:DsUltimo = "dijo `"$corto`""
                    } elseif ($bloque.type -eq 'tool_use' -and $bloque.name -eq 'StructuredOutput') {
                        # Es como el CLI implementa --json-schema, no trabajo de la sesion. Y su
                        # contenido es el mismo 'reason' que se imprime unas lineas mas abajo.
                        continue
                    } elseif ($bloque.type -eq 'tool_use') {
                        $resumen = Get-ResumenHerramienta $bloque.name $bloque.input
                        Write-Host ("  [{0}] {1,-14} {2}" -f $hora, $bloque.name, $resumen) -ForegroundColor DarkCyan
                        $script:DsUltimo = "$($bloque.name) $resumen"
                    }
                }
            }
            'user' {
                foreach ($bloque in @($ev.message.content)) {
                    if ($bloque.type -eq 'tool_result' -and $bloque.is_error) {
                        Write-Host "  [$hora] la herramienta fallo" -ForegroundColor DarkYellow
                    }
                }
            }
            'result' {
                $script:DsHuboResult   = $true
                $script:DsEstructurado = $ev.structured_output
            }
        }
    }

    return [pscustomobject]@{
        ExitCode     = $LASTEXITCODE
        HuboResult   = $script:DsHuboResult
        Estructurado = $script:DsEstructurado
        Ultimo       = $script:DsUltimo
    }
}

$argsDesatendida = @()
if ($desatendida) {
    $argsDesatendida = @(
        '-p',
        '--output-format', 'stream-json',
        '--verbose',
        '--json-schema', $script:EsquemaResultado,
        '--append-system-prompt', $script:ContratoDesatendida
    )
    if ($MaxBudgetUsd -gt 0) {
        # InvariantCulture a mano: con la configuracion regional de por aca, "$MaxBudgetUsd"
        # sale con COMA decimal y el CLI lo rechaza (o peor, lo lee distinto).
        $argsDesatendida += @('--max-budget-usd', $MaxBudgetUsd.ToString([System.Globalization.CultureInfo]::InvariantCulture))
    }
}

# --- Como viaja el prompt hasta claude ------------------------------------
# El prompt entero viaja como UN argumento, y casi todos citan algo entre comillas, traen JSON
# o XML con sus escapes, y TODOS son multilinea. Que eso cruce intacto la linea de comandos de
# Windows no es cosmetico: es lo que la sesion lee.
#
# MEDIDO (pwsh 7.6.4, Windows 11, 2026-08-18) con 21 payloads hostiles -- comillas dobles pares
# e impares, comillas simples, backticks, acentos agudos y comillas tipograficas, XML, HTML,
# JSON con \" y \' y \n adentro, backslash final, metacaracteres de shell, %VARIABLES%, prompts
# multilinea, unicode y emoji -- contra un .exe nativo que anota cada argumento tal como se lo
# entrego el sistema operativo:
#
#   | camino                                   | resultado                                     |
#   |------------------------------------------|-----------------------------------------------|
#   | .exe nativo, modo Standard/Windows       | los 21 INTACTOS                               |
#   | .exe nativo, modo Legacy, sin escapar    | se PARTE en la primera comilla                |
#   | .exe nativo, modo Legacy, escapando      | 20 de 21 (un '\' final llega duplicado)       |
#   | shim .cmd/.bat, escapando o no           | ver abajo: irreparable                        |
#
# De ahi salen las dos decisiones de este bloque.

# --- 1) El modo de pasaje de argumentos se FIJA, no se adivina -------------
# $PSNativeCommandArgumentPassing es una variable de preferencia: la puede haber dejado en
# 'Legacy' un perfil, o el llamador. En vez de detectar eso y compensarlo escapando a mano
# (que es lo que hacia este script hasta la 1.1.1), lo fijamos para nuestro propio ambito.
# MEDIDO: con el llamador en 'Legacy', fijarlo en 'Standard' aca alcanza para que el prompt
# llegue intacto, incluso adentro de las funciones de este script.
#
# 'Standard' y no 'Windows': 'Windows' tiene una excepcion para .cmd/.bat, y no queremos que
# el comportamiento dependa de con que se resolvio 'claude'.
#
# La variable existe desde 7.3. En 7.0-7.2 no existe y el comportamiento es el viejo (como
# 'Legacy'): ahi, y SOLO ahi, hay que escapar a mano.
$hayVariableDeModo = $null -ne (Get-Variable -Name PSNativeCommandArgumentPassing -ErrorAction SilentlyContinue)

if ($hayVariableDeModo) {
    $PSNativeCommandArgumentPassing = 'Standard'
    $escapar = $false
    $motivoEscapado = "modo fijado en 'Standard' por el script; PowerShell escapa"
} else {
    $escapar = $true
    $motivoEscapado = "PowerShell $($PSVersionTable.PSVersion) no tiene PSNativeCommandArgumentPassing (7.0-7.2): escapo a mano"
}

# Escapado segun las reglas de CommandLineToArgvW (comillas con \, y backslashes duplicados
# cuando preceden a una comilla o cierran la cadena). Solo se usa en 7.0-7.2. Efecto colateral
# medido: un '\' AL FINAL del prompt llega duplicado. Se deja asi -- un prompt no termina en
# backslash, y en 7.3+ no se escapa nada.
function ConvertTo-NativeArg([string]$s) {
    $s = $s -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return $s
}

# Como queda un argumento adentro de la linea de comandos: entre comillas si hace falta, y con
# las comillas internas escapadas. Es lo mismo que hace PowerShell en modo 'Standard'; lo
# replicamos para poder MEDIR cuanto va a ocupar antes de intentarlo.
function Get-ArgumentoEnLinea([string]$s) {
    $cuerpo = ConvertTo-NativeArg $s
    if ($s -eq '' -or $s -match '[\s"]') { return '"' + $cuerpo + '"' }
    return $cuerpo
}

# El largo REAL de la linea de comandos que se va a armar. MEDIDO en esta maquina el 2026-08-18
# con un .exe nativo: con texto plano entra un prompt de 32500 y falla uno de 32600 (ruta del
# ejecutable de 150 caracteres); con un texto que trae una comilla cada diez caracteres, el
# mismo prompt ocupa mucho mas y falla ya en 30000, porque cada '"' viaja como '\"'.
#
# O sea que el corte fijo de 30000 caracteres que este script traia se equivocaba en las dos
# direcciones: rechazaba prompts de 31697 que entran (hay casos reales) y aceptaba
# prompts llenos de comillas que no entran.
#
# Cuando no entra, la falla es RUIDOSA ("The filename or extension is too long"), no un truncado
# en silencio. Igual cortamos antes: el mensaje del sistema no dice cual prompt fue ni que hacer.
function Test-EntraEnLaLineaDeComandos([string]$exe, [string[]]$argumentos) {
    $partes = @(Get-ArgumentoEnLinea $exe) + @($argumentos | ForEach-Object { Get-ArgumentoEnLinea $_ })
    $largo = ($partes -join ' ').Length
    $techo = $script:TechoLineaDeComandos - $script:MargenLineaDeComandos
    return @(($largo -le $techo), $largo, $techo)
}

# --- 2) Un 'claude' que sea un shim .cmd/.bat no sirve ---------------------
# Si 'claude' se instalo por npm, en el PATH queda un claude.cmd. Pasar el prompt por ahi lo
# rompe, y de la peor manera. MEDIDO con los mismos 21 payloads, escapando y sin escapar:
#
#   - un prompt MULTILINEA llega TRUNCADO en su primera linea, sin error ni aviso. Como todos
#     los prompts de sesion son multilinea, esto solo no deja nada en pie;
#   - %PATH% y compania los EXPANDE cmd: al prompt le entra el PATH de la maquina;
#   - un '<' o un '>' (o sea, cualquier prompt con XML o HTML) hace fallar la invocacion;
#   - un '\' final llega duplicado.
#
# No hay escapado que arregle eso: son reglas de cmd.exe, no de CommandLineToArgvW. Asi que si
# 'claude' resuelve a un shim, primero buscamos el .exe equivalente; si no hay, el script NO
# ARRANCA. Es la misma regla que el corte por tamano: mejor una corrida que no empieza que una
# serie entera leyendo la primera linea de cada prompt.
function Resolve-ComandoClaude([string]$comando) {
    $resuelto = Get-Command $comando -ErrorAction SilentlyContinue
    if (-not $resuelto) {
        Write-Host "No encuentro '$comando'. Instala Claude Code, o pasa -ClaudeCommand con la ruta al ejecutable." -ForegroundColor Red
        exit 1
    }

    # Un .ps1, una funcion o un alias no pasan por la linea de comandos de Windows: se usan
    # tal cual. (Es, entre otras cosas, como se testea este script.)
    if ($resuelto.CommandType -ne 'Application') { return $comando }

    if ($resuelto.Source -notmatch '\.(cmd|bat)$') { return $resuelto.Source }

    # Es un shim. Alguna otra entrada del PATH con el mismo nombre que NO sea shim?
    $alternativa = @(Get-Command $comando -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' -and $_.Source -notmatch '\.(cmd|bat)$' } |
        Select-Object -First 1)

    # O un ejecutable al lado del shim (claude.cmd -> claude.exe en la misma carpeta)?
    if ($alternativa.Count -eq 0) {
        $hermano = [System.IO.Path]::ChangeExtension($resuelto.Source, '.exe')
        if (Test-Path -LiteralPath $hermano) {
            Write-Host "'$comando' resolvia a un shim $([IO.Path]::GetExtension($resuelto.Source)); uso el ejecutable de al lado: $hermano" -ForegroundColor DarkGray
            return $hermano
        }
    } else {
        Write-Host "'$comando' resolvia a un shim $([IO.Path]::GetExtension($resuelto.Source)); uso $($alternativa[0].Source)" -ForegroundColor DarkGray
        return $alternativa[0].Source
    }

    Write-Host "'$comando' resuelve a un shim: $($resuelto.Source)" -ForegroundColor Red
    Write-Host "Por ese camino el prompt NO llega entero: uno multilinea se trunca en su primera linea," -ForegroundColor Red
    Write-Host "en silencio, y un '<' o un '%VAR%' lo rompen de otras formas (medido). No arranco." -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "Que hacer:" -ForegroundColor Yellow
    Write-Host "  - instalar Claude Code como ejecutable nativo (winget install Anthropic.ClaudeCode), o" -ForegroundColor Yellow
    Write-Host "  - apuntar el runner al ejecutable real: -ClaudeCommand <ruta al .exe>, o la clave" -ForegroundColor Yellow
    Write-Host "    'claudeCommand' del session-prompts.config.json." -ForegroundColor Yellow
    exit 1
}

$ClaudeCommand = Resolve-ComandoClaude $ClaudeCommand

# La carpeta, los prompts, el nombre de la serie y el numero de inicio ya se resolvieron y se
# validaron arriba, antes de preguntar modelo y effort. Lo unico que falta es recortar.
# El numero de inicio ya se comparo contra el ultimo prompt, asi que esto nunca vacia la lista.
if ($StartFrom -gt 0) {
    $prompts = @($prompts | Where-Object { (Get-PromptNumber $_.Name) -ge $StartFrom })
}

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

# --- Modelo y effort sugeridos por sesion ---------------------------------
# Un prompt puede declarar con que modelo y con cuanto esfuerzo se penso escribirlo, con dos
# marcas en el .md:
#
#     <!-- modelo-sugerido: sonnet -->
#     <!-- effort-sugerido: xhigh -->
#
# La regla es la MISMA para los dos (la del modelo es decision del owner, 2026-07-27; la del
# effort, 2026-08-18), con el valor de la corrida haciendo de TOPE:
#   - sugerido MENOR que el tope -> manda el de la sesion, sin preguntar (bajar es barato, y la
#     sesion sabe lo que necesita).
#   - sugerido MAYOR que el tope -> PARA Y PREGUNTA (correr una sesion con menos de lo que pide
#     no se decide solo).
#   - igual, o sin marca         -> el tope, sin ruido.
#
# Con los defaults (Opus 5 y high) eso significa: cualquier sesion puede pedir menos y arranca
# sola; ninguna sesion puede pedir mas -- Opus si la corrida esta en Sonnet, xhigh o max si esta
# en high -- sin que vos lo confirmes. Para levantar el tope de toda la corrida: -Model / -Effort.
#
# Todo esto se resuelve ACA, antes de crear el worktree y de lanzar la primera sesion: si el
# script preguntara en medio del loop, romperia lo unico que promete (que te podes ir de la
# maquina).
$rangoModelo = @{ 'sonnet' = 1; 'opus' = 2 }
$rangoEffort = @{ 'low' = 1; 'medium' = 2; 'high' = 3; 'xhigh' = 4; 'max' = 5 }

# Los valores validos, listados de menor a mayor: es como se leen en un mensaje de error.
# ($efforts esta en orden de MENU, con el default primero, que no sirve para eso.)
$modelosPorRango = @($rangoModelo.GetEnumerator() | Sort-Object Value | ForEach-Object { $_.Key })
$effortsPorRango = @($rangoEffort.GetEnumerator() | Sort-Object Value | ForEach-Object { $_.Key })

$etiquetaModelo = @{}
foreach ($m in $modelos) { $etiquetaModelo[$m.Alias] = $m.Etiqueta }
$etiquetaEffort = @{}
foreach ($e in $efforts) { $etiquetaEffort[$e] = $e }

# Lee una marca del prompt. El patron es ANCHO a proposito -- captura cualquier valor y despues
# valida -- para que '<!-- effort-sugerido: alto -->' corte con un error y no se ignore en
# silencio, que es como un prompt terminaria corriendo con algo distinto de lo que pidio.
# --- Un prompt que no este en UTF-8 no se lee "mas o menos" ----------------
# El runner lee los .md con -Encoding UTF8 explicito. Si el archivo esta guardado en la ANSI de
# Windows (cp1252, cp437), los bytes de los acentos no forman UTF-8 valido y .NET los reemplaza por
# U+FFFD: la sesion recibe "ejecuci<?>n" y NADA falla. Es la misma clase de degradacion silenciosa
# que este script existe para no cometer, del lado de la entrada.
#
# MEDIDO: UTF-8 con y sin BOM, ASCII puro y UTF-16 CON BOM se leen bien (PowerShell respeta el BOM
# aunque se le pida UTF8); cp1252 y cp437 con acentos pierden un caracter por acento.
#
# La deteccion es exacta, no una adivinanza: se intenta decodificar en UTF-8 ESTRICTO. Texto ASCII
# es UTF-8 valido, asi que un archivo sin acentos nunca molesta; y una secuencia de bytes cp1252
# con acentos practicamente nunca es UTF-8 valido. Devuelve '' si esta bien, o el motivo.
function Test-PromptNoEsUtf8([string]$ruta) {
    $bytes = [System.IO.File]::ReadAllBytes($ruta)
    if ($bytes.Length -lt 2) { return '' }

    # UTF-16 CON BOM: PowerShell lo respeta y lo lee bien. No es problema.
    $tieneBomUtf16 = ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF)
    if ($tieneBomUtf16) { return '' }

    # Sin BOM y con bytes NUL: es UTF-16 sin marcar. Pasaria la validacion de UTF-8 (el NUL es un
    # byte UTF-8 valido) y se leeria como basura, asi que se chequea aparte.
    if ($bytes -contains 0) { return 'tiene bytes NUL: parece UTF-16 sin BOM' }

    $estricto = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        [void]$estricto.GetString($bytes)
        return ''
    } catch {
        return 'no es UTF-8 valido: parece guardado en la codificacion ANSI de Windows'
    }
}

# NOTA sobre el '\r?' del final de los dos patrones de abajo: '$' en modo multilinea matchea
# ANTES del '\n', y en un .md con fin de linea CRLF queda un '\r' en el medio que '[ \t]*' no come.
# MEDIDO: sin ese '\r?', en un repo destino cuyos .md se checkoutean en CRLF -- el default de Git
# para Windows cuando el repo no trae .gitattributes -- NINGUNA marca matchea: ni modelo-sugerido,
# ni effort-sugerido, ni las dos de -Unattended. Una marca que no se aplica en silencio es
# exactamente lo que este script no hace.
function Get-MarcaSugerida([string]$texto, [string]$marca, [string[]]$validos, [string]$archivo) {
    $m = [regex]::Match($texto, "(?im)^[ \t]*<!--[ \t]*(?:$marca):[ \t]*(\S+)[ \t]*-->[ \t]*\r?$")
    if (-not $m.Success) { return $null }

    $valor = $m.Groups[1].Value.ToLowerInvariant()
    if ($validos -notcontains $valor) {
        Write-Host "$archivo declara '$valor', que no es un valor valido para esa marca." -ForegroundColor Red
        Write-Host "Validos: $($validos -join ', ')." -ForegroundColor Red
        exit 1
    }
    return $valor
}

# Las dos marcas de -Unattended. Mismo criterio ANCHO que la de arriba -- captura cualquier valor y
# despues valida --, mas un motivo libre opcional despues de un '|':
#
#     <!-- runner-requerido: 2.0 -->
#     <!-- automatico: no | hace deploy a produccion -->
#
# Devuelve $null si la marca no esta, o un objeto con Valor (en minusculas) y Motivo.
function Get-MarcaConMotivo([string]$texto, [string]$marca) {
    $m = [regex]::Match($texto, "(?im)^[ \t]*<!--[ \t]*(?:$marca):[ \t]*([^|\s]+)[ \t]*(?:\|[ \t]*(.*?))?[ \t]*-->[ \t]*\r?$")
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{
        Valor  = $m.Groups[1].Value.ToLowerInvariant()
        Motivo = $m.Groups[2].Value.Trim()
    }
}

# La regla de arriba, una sola vez, para el modelo y para el effort.
# Devuelve el alias elegido y la nota que va al plan; aborta si asi lo pedis.
function Resolve-Sugerido([string]$nombrePrompt, [string]$que, [string]$sugerido, [string]$tope,
                          [hashtable]$rango, [hashtable]$etiquetas) {
    if (-not $sugerido) { return [pscustomobject]@{ Alias = $tope; Nota = '' } }

    if ($rango[$sugerido] -lt $rango[$tope]) {
        return [pscustomobject]@{
            Alias = $sugerido
            Nota  = "$que sugerido (baja desde $($etiquetas[$tope]))"
        }
    }

    if ($rango[$sugerido] -eq $rango[$tope]) {
        return [pscustomobject]@{ Alias = $tope; Nota = "coincide con el $que sugerido" }
    }

    Write-Host ""
    Write-Host ("$nombrePrompt sugiere $que {0} y la corrida esta en {1}." -f $etiquetas[$sugerido], $etiquetas[$tope]) -ForegroundColor Yellow
    Write-Host "  [1] Usar $($etiquetas[$sugerido]) en ESTA sesion (lo que pide el prompt)  (default)"
    Write-Host "  [2] Correrla igual con $($etiquetas[$tope])"
    Write-Host "  [3] Abortar"

    $ans = Read-Host "Elegi el numero (Enter = 1)"
    if ([string]::IsNullOrWhiteSpace($ans) -or $ans -eq '1') {
        return [pscustomobject]@{ Alias = $sugerido; Nota = "$que sugerido (SUBE, confirmado)" }
    }
    if ($ans -eq '2') {
        return [pscustomobject]@{ Alias = $tope; Nota = "IGNORA el $que sugerido ($($etiquetas[$sugerido])), confirmado" }
    }
    if ($ans -eq '3') {
        Write-Host "Abortado por el usuario." -ForegroundColor Red
        exit 1
    }

    Write-Host "Valor invalido: '$ans'. Tiene que ser 1, 2 o 3." -ForegroundColor Red
    exit 1
}

# --- Antes que nada: que los prompts esten en UTF-8 -----------------------
# Va PRIMERO, incluso antes de leer las marcas: leer una marca de un archivo mal decodificado no
# tiene sentido. Todos los problemas juntos, como con la configuracion.
$problemasEncoding = @()
foreach ($p in $prompts) {
    $motivo = Test-PromptNoEsUtf8 $p.FullName
    if ($motivo) { $problemasEncoding += "$($p.Name): $motivo" }
}

if ($problemasEncoding.Count -gt 0) {
    Write-Host "Estos prompts no estan guardados en UTF-8:" -ForegroundColor Red
    foreach ($m in $problemasEncoding) { Write-Host "  - $m" -ForegroundColor Red }
    Write-Host ""
    Write-Host "El runner los lee como UTF-8, asi que sus acentos llegarian a la sesion como" -ForegroundColor DarkGray
    Write-Host "caracteres de reemplazo, sin que nada falle. Para convertir uno:" -ForegroundColor DarkGray
    Write-Host "  `$t = Get-Content -LiteralPath <archivo> -Raw -Encoding ansi" -ForegroundColor DarkGray
    Write-Host "  Set-Content -LiteralPath <archivo> -Value `$t -Encoding utf8NoBOM" -ForegroundColor DarkGray
    exit 1
}

# --- Las marcas de -Unattended, antes de preguntar nada ---------------------
# Se VALIDAN siempre (una marca mal escrita es un error aunque la corrida sea interactiva) y se
# EXIGEN solo en -Unattended. Va antes del plan porque el plan puede parar a preguntar por el
# modelo o el effort: descubrir recien ahi que la serie ni siquiera puede correr sola seria
# hacerte contestar preguntas de una corrida que no va a existir.
# Todos los problemas juntos, como con la configuracion: uno por corrida es peor que verlos todos.
$marcasDesatendida  = @{}
$problemasMarcas = @()

foreach ($p in $prompts) {
    $textoMarcas = Get-Content -LiteralPath $p.FullName -Raw -Encoding UTF8

    $marcaVersion = Get-MarcaConMotivo $textoMarcas 'runner-requerido|required-runner'
    $marcaAuto    = Get-MarcaConMotivo $textoMarcas 'automatico|automatic'

    $versionPedida = $null
    if ($marcaVersion) {
        # '2' se lee como '2.0': [version] pide dos numeros y no vale hacer fallar a alguien
        # por eso.
        $crudo = if ($marcaVersion.Valor -match '^\d+$') { "$($marcaVersion.Valor).0" } else { $marcaVersion.Valor }
        try {
            $versionPedida = [version]$crudo
        } catch {
            $problemasMarcas += "$($p.Name): 'runner-requerido: $($marcaVersion.Valor)' no es un numero de version."
        }
    }

    $requiereHumano = $false
    $motivoHumano   = ''
    if ($marcaAuto) {
        if ($marcaAuto.Valor -eq 'no') {
            $requiereHumano = $true
            $motivoHumano   = $marcaAuto.Motivo
        } elseif ($marcaAuto.Valor -ne 'si') {
            $problemasMarcas += "$($p.Name): 'automatico: $($marcaAuto.Valor)' no es un valor valido. Validos: si, no."
        }
    }

    $marcasDesatendida[$p.Name] = [pscustomobject]@{
        Version        = $versionPedida
        RequiereHumano = $requiereHumano
        MotivoHumano   = $motivoHumano
    }
}

if ($problemasMarcas.Count -gt 0) {
    Write-Host "Hay marcas mal escritas en los prompts:" -ForegroundColor Red
    foreach ($m in $problemasMarcas) { Write-Host "  - $m" -ForegroundColor Red }
    Write-Host "Una marca que se ignora en silencio es justo lo que este script no hace." -ForegroundColor DarkGray
    exit 1
}

if ($desatendida) {
    $sinMarca = @($prompts | Where-Object { $null -eq $marcasDesatendida[$_.Name].Version })
    if ($sinMarca.Count -gt 0) {
        Write-Host "-Unattended solo corre series escritas para correr solas, y estos prompts no lo declaran:" -ForegroundColor Red
        foreach ($p in $sinMarca) { Write-Host "  - $($p.Name)" -ForegroundColor Red }
        Write-Host "" -ForegroundColor Red
        Write-Host "Cada prompt de la serie tiene que traer en su encabezado:" -ForegroundColor DarkGray
        Write-Host "    <!-- runner-requerido: $($script:VersionMinimaDesatendida) -->" -ForegroundColor DarkGray
        Write-Host "Es lo que dice que el prompt conoce el contrato del resultado ({ result, reason })." -ForegroundColor DarkGray
        Write-Host "Sin -Unattended la serie corre normal, con Remote Control y /exit." -ForegroundColor DarkGray
        exit 1
    }

    $viejos = @($prompts | Where-Object { $marcasDesatendida[$_.Name].Version -lt $script:VersionMinimaDesatendida })
    if ($viejos.Count -gt 0) {
        Write-Host "-Unattended necesita prompts escritos para la $($script:VersionMinimaDesatendida) o posterior:" -ForegroundColor Red
        foreach ($p in $viejos) {
            Write-Host "  - $($p.Name) declara $($marcasDesatendida[$p.Name].Version)" -ForegroundColor Red
        }
        exit 1
    }

    $nuevos = @($prompts | Where-Object { $marcasDesatendida[$_.Name].Version -gt [version]$script:RunnerVersion })
    if ($nuevos.Count -gt 0) {
        Write-Host "Estos prompts piden un runner mas nuevo que el instalado ($script:RunnerVersion):" -ForegroundColor Red
        foreach ($p in $nuevos) {
            Write-Host "  - $($p.Name) pide $($marcasDesatendida[$p.Name].Version)" -ForegroundColor Red
        }
        Write-Host "Actualiza con: pwsh -File .\Run-SessionPrompts.ps1 -Update" -ForegroundColor DarkGray
        exit 1
    }
}

$plan = @()
foreach ($p in $prompts) {
    # -Encoding UTF8 por el mismo motivo que al leer el prompt: los .md no tienen BOM.
    $texto = Get-Content -LiteralPath $p.FullName -Raw -Encoding UTF8

    $modeloSugerido = Get-MarcaSugerida $texto 'modelo-sugerido|suggested-model' $modelosPorRango $p.Name
    $effortSugerido = Get-MarcaSugerida $texto 'effort-sugerido|suggested-effort' $effortsPorRango $p.Name

    $decModelo = Resolve-Sugerido $p.Name 'modelo' $modeloSugerido $Model  $rangoModelo $etiquetaModelo
    $decEffort = Resolve-Sugerido $p.Name 'effort' $effortSugerido $Effort $rangoEffort $etiquetaEffort

    $notas = @($decModelo.Nota, $decEffort.Nota) | Where-Object { $_ }

    $plan += [pscustomobject]@{
        Prompt         = $p
        Modelo         = $modelos | Where-Object { $_.Alias -eq $decModelo.Alias } | Select-Object -First 1
        Effort         = $decEffort.Alias
        Nota           = ($notas -join '; ')
        RequiereHumano = $marcasDesatendida[$p.Name].RequiereHumano
        MotivoHumano   = $marcasDesatendida[$p.Name].MotivoHumano
    }
}

# --- La sesion que pide humano corta la corrida automatica ----------------
# Un prompt marcado 'automatico: no' no puede correr sin nadie. La serie corre automatica hasta
# la anterior y FRENA ahi, limpio: quedarse esperando a que vuelvas seria justo lo que este
# script promete que no pasa. Se decide ACA, antes de lanzar nada, asi sabes de entrada donde
# va a parar.
$frenoHumano = $null
if ($desatendida) {
    for ($i = 0; $i -lt $plan.Count; $i++) {
        if ($plan[$i].RequiereHumano) {
            $frenoHumano = $plan[$i]
            if ($i -eq 0) {
                $motivo = if ($frenoHumano.MotivoHumano) { ": $($frenoHumano.MotivoHumano)" } else { "" }
                Write-Host "$($frenoHumano.Prompt.Name) esta marcada 'automatico: no'$motivo" -ForegroundColor Red
                Write-Host "Es la primera de la corrida, asi que en -Unattended no queda nada que correr." -ForegroundColor Red
                Write-Host "Corre la serie sin -Unattended, o arranca despues de esa sesion con -StartFrom." -ForegroundColor DarkGray
                exit 1
            }
            $plan = @($plan[0..($i - 1)])
            break
        }
    }
}

# --- El plan, antes de arrancar -------------------------------------------
$desde = if ($StartFrom -gt 0) { " (desde el $StartFrom)" } else { "" }
Write-Host ""
Write-Host "Ejecutando $($plan.Count) prompts de la serie '$serie'$desde" -ForegroundColor Cyan
Write-Host "Prompts: $PromptsPath" -ForegroundColor DarkGray
if ($usaWorktree) {
    Write-Host "Worktree (directorio de trabajo): $worktreePath  |  rama: $branch (desde $BaseBranch)" -ForegroundColor DarkGray
} else {
    Write-Host "Proyecto (directorio de trabajo): $workDir" -ForegroundColor DarkGray
}
Write-Host "Tope de la corrida: $($modelo.Etiqueta) ($($modelo.Id))  |  effort $Effort" -ForegroundColor DarkGray
$quePermisos = if ($fullAuto) { '--dangerously-skip-permissions (no pregunta nada)' } else { "--permission-mode $modoPermiso" }
Write-Host "Permisos: $quePermisos" -ForegroundColor DarkGray
if ($desatendida) {
    Write-Host "Modo: -Unattended -- sin Remote Control y sin /exit; cada sesion dice si la serie sigue." -ForegroundColor Yellow
    if ($MaxBudgetUsd -gt 0) {
        Write-Host "Techo de gasto por sesion: USD $MaxBudgetUsd (--max-budget-usd)" -ForegroundColor DarkGray
    }
}
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
    $difiere = ($item.Modelo.Alias -ne $modelo.Alias) -or ($item.Effort -ne $Effort)
    $color = if ($difiere) { 'Yellow' } else { 'DarkGray' }
    Write-Host ("  {0,-34} {1,-8} effort {2,-6}{3}" -f $item.Prompt.Name, $item.Modelo.Etiqueta, $item.Effort, $detalle) -ForegroundColor $color
}

if ($frenoHumano) {
    $motivo = if ($frenoHumano.MotivoHumano) { " ($($frenoHumano.MotivoHumano))" } else { "" }
    $numero = Get-PromptNumber $frenoHumano.Prompt.Name
    Write-Host ""
    Write-Host "La corrida automatica FRENA antes de $($frenoHumano.Prompt.Name)$motivo" -ForegroundColor Yellow
    Write-Host "Esa sesion esta marcada 'automatico: no': necesita un humano." -ForegroundColor DarkGray
    Write-Host "Cuando termine lo de arriba, seguis a mano con:" -ForegroundColor DarkGray
    Write-Host "  pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath `"$PromptsPath`" -StartFrom $numero" -ForegroundColor DarkGray
}

if ($DryRun) {
    Write-Host ""
    Write-Host "-DryRun: no se lanza ninguna sesion. Lo que se ejecutaria:" -ForegroundColor Yellow
    foreach ($item in $plan) {
        $sessionName = "$serie/$($item.Prompt.BaseName)"
        $comunes = "$ClaudeCommand --model $($item.Modelo.Id) --effort $($item.Effort) $($claudeArgs -join ' ')"
        $linea = if ($desatendida) {
            # El esquema y el contrato van como marcador: pegados enteros, y por cada sesion, la
            # linea deja de poder leerse. Estan completos en el README y en el propio script.
            $techo = if ($MaxBudgetUsd -gt 0) { " --max-budget-usd $($MaxBudgetUsd.ToString([System.Globalization.CultureInfo]::InvariantCulture))" } else { "" }
            "$comunes -p --output-format stream-json --verbose --json-schema <esquema del resultado>" +
            " --append-system-prompt <contrato de -Unattended>$techo" +
            " --session-id <guid> --name $sessionName <prompt de $($item.Prompt.Name)>"
        } else {
            "$comunes --rc $sessionName --name $sessionName <prompt de $($item.Prompt.Name)>"
        }
        Write-Host "  $linea" -ForegroundColor DarkGray
    }
    exit 0
}

# --- -Unattended se confirma a mano -----------------------------------------
# Es lo ultimo que se pregunta y va ANTES del worktree: si abortas aca, no queda nada creado.
# Se pide escribir 'si' entero, no una tecla: este modo lanza una serie completa contra el repo
# sin nadie mirando, y eso no se acepta de un Enter distraido.
if ($desatendida) {
    Write-Host ""
    Write-Host "== -Unattended: la serie corre sola ==" -ForegroundColor Yellow
    Write-Host "  - NO hay Remote Control: no vas a poder mirar ni intervenir desde el celular" -ForegroundColor Yellow
    Write-Host "    mientras corre. Las sesiones quedan guardadas y se abren despues con 'claude --resume'." -ForegroundColor Yellow
    Write-Host "  - Los permisos los decide el clasificador de Claude Code (--permission-mode auto), no vos." -ForegroundColor Yellow
    Write-Host "  - Cada sesion dice si la serie sigue. Si una no deja resultado, la serie FRENA ahi." -ForegroundColor Yellow
    $cuantas = if ($plan.Count -eq 1) { "Es 1 sesion" } else { "Son $($plan.Count) sesiones" }
    Write-Host "  - $cuantas sobre $workDir" -ForegroundColor Yellow
    if ($MaxBudgetUsd -le 0) {
        Write-Host "  - Sin techo de gasto: una sesion trabada puede correr sin limite. Se pone con -MaxBudgetUsd." -ForegroundColor Yellow
    }
    Write-Host ""
    $confirma = Read-Host "Escribi 'si' para arrancar (cualquier otra cosa aborta)"
    if ("$confirma".Trim().ToLowerInvariant() -ne 'si') {
        Write-Host "Abortado: no se lanzo ninguna sesion." -ForegroundColor Red
        exit 1
    }
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

if ($desatendida) {
    Write-Host "Sin Remote Control y sin /exit: cada sesion termina sola y dice si la serie sigue.`n" -ForegroundColor DarkGray
} else {
    Write-Host "Cada sesion tiene Remote Control. Para pasar a la siguiente, cerra la actual con /exit.`n" -ForegroundColor DarkGray
}

# --- El loop --------------------------------------------------------------
$reloj = [System.Diagnostics.Stopwatch]::StartNew()

Push-Location -LiteralPath $workDir
try {

foreach ($item in $plan) {
    $p = $item.Prompt
    $modeloSesion = $item.Modelo
    $effortSesion = $item.Effort

    $comoTermina = if ($desatendida) { 'termina sola' } else { '/exit para pasar a la proxima' }
    Write-Host "== Sesion: $($p.Name)  [$($modeloSesion.Etiqueta), effort $effortSesion]  ($comoTermina) ==" -ForegroundColor Cyan

    # El contenido del prompt va como argumento posicional (mensaje inicial), NO por stdin:
    # si se pipea, claude pierde la TTY y no seria interactivo/RC.
    #
    # -Encoding UTF8 explicito: los .md son UTF-8 sin BOM. En 7.x ese ya es el default, pero
    # dejarlo escrito hace que la corrida no dependa de que el default no cambie. Se lee del
    # checkout donde viven los prompts ($p.FullName es absoluto); el cwd puede ser otro.
    $promptText = Get-Content -LiteralPath $p.FullName -Raw -Encoding UTF8

    # Ver el bloque "Como viaja el prompt hasta claude": en 7.3+ el modo esta fijado en
    # 'Standard' y PowerShell escapa solo, asi que meter escapado encima degradaria el prompt.
    $arg = if ($escapar) { ConvertTo-NativeArg $promptText } else { $promptText }

    # Tope propio del repo, si lo puso en la configuracion.
    if ($maxPromptChars -gt 0 -and $promptText.Length -gt $maxPromptChars) {
        Write-Host "$($p.Name) tiene $($promptText.Length) caracteres y la configuracion de este repo corta en $maxPromptChars (maxPromptChars). Partilo en dos sesiones." -ForegroundColor Red
        exit 1
    }

    # Nombre visible de la sesion en el celular y en Claude Code Desktop. Sin esto, Remote
    # Control genera uno al azar tipo 'mi-pc-snappy-emerson'.
    $sessionName = "$serie/$($p.BaseName)"

    $relojSesion = [System.Diagnostics.Stopwatch]::StartNew()

    # Se pone en cero para no arrastrar el exit code de un comando anterior si el destino no
    # llega a setearlo.
    $global:LASTEXITCODE = 0

    # La lista completa, para poder medirla antes de intentar lanzarla. En -Unattended el contrato
    # y el esquema tambien ocupan lugar en la linea: por eso se miden con todo lo demas y no
    # aparte.
    $sessionId = [guid]::NewGuid().ToString()
    $argsSesion = @('--model', $modeloSesion.Id, '--effort', $effortSesion) + $claudeArgs
    $argsSesion += if ($desatendida) {
        $argsDesatendida + @('--session-id', $sessionId, '--name', $sessionName, $arg)
    } else {
        @('--rc', $sessionName, '--name', $sessionName, $arg)
    }

    $entra, $largoLinea, $techoLinea = Test-EntraEnLaLineaDeComandos $ClaudeCommand $argsSesion
    if (-not $entra) {
        Write-Host "$($p.Name) no entra en la linea de comandos de Windows." -ForegroundColor Red
        Write-Host "  El prompt tiene $($promptText.Length) caracteres y, con la ruta del ejecutable, los flags y las" -ForegroundColor Red
        Write-Host "  comillas escapadas, la linea queda en $largoLinea (el maximo utilizable es $techoLinea)." -ForegroundColor Red
        Write-Host "  Partilo en dos sesiones." -ForegroundColor Red
        exit 1
    }

    $salida = $null
    if ($desatendida) {
        Write-Host "   claude --resume $sessionId   (para abrirla despues)" -ForegroundColor DarkGray
        $salida = Invoke-SesionDesatendida $ClaudeCommand $argsSesion
        $global:LASTEXITCODE = $salida.ExitCode
    } else {
        & $ClaudeCommand @argsSesion
    }

    $relojSesion.Stop()

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Fallo $($p.Name) (exit $LASTEXITCODE). Corto la ejecucion." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    # --- El semaforo de -Unattended -----------------------------------------
    # Sigue SOLO si se cumple todo: exit code 0 (ya chequeado), resultado estructurado presente,
    # y 'result' en 'ok'. Cualquier otra cosa frena. Los dos diagnosticos se imprimen DISTINTO
    # a proposito: "la sesion pidio frenar" es el mecanismo funcionando, "la sesion no dejo
    # resultado" es una sesion que se colgo o se fue por las ramas, y no se arreglan igual.
    if ($desatendida) {
        $estructurado = $salida.Estructurado
        if ($null -eq $estructurado) {
            $donde = if ($salida.Ultimo) { " Lo ultimo que hizo: $($salida.Ultimo)." } else { "" }
            $quePaso = if ($salida.HuboResult) {
                "termino sin el resultado estructurado"
            } else {
                "termino sin dejar ningun resultado"
            }
            Write-Host "$($p.Name) $quePaso. Corto la serie.$donde" -ForegroundColor Red
            Write-Host "  Para ver que paso: claude --resume $sessionId" -ForegroundColor DarkGray
            exit 1
        }

        $veredicto = "$($estructurado.result)".Trim().ToLowerInvariant()
        $porque    = "$($estructurado.reason)".Trim()

        if ($veredicto -ne 'ok') {
            $comoLoDijo = if ($veredicto -eq 'stop') { "pidio frenar" } else { "devolvio 'result: $veredicto', que no es un valor que este runner entienda" }
            Write-Host "$($p.Name) $comoLoDijo. Corto la serie." -ForegroundColor Red
            if ($porque) { Write-Host "  $porque" -ForegroundColor Yellow }
            Write-Host "  Para retomar ahi: -StartFrom $(Get-PromptNumber $p.Name)" -ForegroundColor DarkGray
            Write-Host "  Para ver que paso: claude --resume $sessionId" -ForegroundColor DarkGray
            exit 1
        }

        if ($porque) { Write-Host "  $porque" -ForegroundColor DarkGray }
    }

    Write-Host ("Cerrada {0} ({1:hh\:mm\:ss}).`n" -f $p.Name, $relojSesion.Elapsed) -ForegroundColor Green
}

}
finally {
    Pop-Location
}

$reloj.Stop()
Write-Host ("Todos los prompts se ejecutaron correctamente ({0} sesiones, {1:hh\:mm\:ss})." -f $plan.Count, $reloj.Elapsed) -ForegroundColor Green

if ($frenoHumano) {
    $numero = Get-PromptNumber $frenoHumano.Prompt.Name
    Write-Host ""
    Write-Host "La serie NO termino: $($frenoHumano.Prompt.Name) necesita un humano." -ForegroundColor Yellow
    Write-Host "  pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath `"$PromptsPath`" -StartFrom $numero" -ForegroundColor DarkGray
}

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

# --- Que -Unattended existe ------------------------------------------------
# Al FINAL de una corrida que salio bien, y una sola vez: el que acaba de cerrar nueve sesiones a
# mano es justo el que necesita enterarse, y ahi ya no esta esperando nada. Por sesion seria
# hostigarlo, y en una corrida que fallo seria lo ultimo que quiere leer (esa sale por otro lado).
#
# No se ofrece con una sola sesion: ahi no hay "cada sesion" que moleste.
#
# Y NO lleva un comando para copiar: esta serie acaba de terminar, nadie la va a correr de nuevo.
# Lo unico util aca es que el modo existe.
if (-not $desatendida -and $plan.Count -gt 1) {
    Write-Host ""
    Write-Host "Si cerrar con /exit te molesta, -Unattended corre la serie sola, pero te quedas sin" -ForegroundColor Yellow
    Write-Host "Remote Control mientras corre." -ForegroundColor Yellow
}

}
finally {
    if ($encodingPrevio) { try { [Console]::OutputEncoding = $encodingPrevio } catch { } }
}
