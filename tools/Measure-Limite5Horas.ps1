#Requires -Version 7.0
<#
.SYNOPSIS
    Mide como se comporta claude.exe cuando le pega al limite de uso de 5 horas.

.DESCRIPTION
    Levanta la API falsa (tools\Start-FakeAnthropicApi.ps1), apunta el CLI ahi con
    ANTHROPIC_BASE_URL y corre la secuencia real de punta a punta: una sesion que choca contra
    el limite, y despues el resume de ESA misma sesion cuando el limite ya vencio.

    De ahi salen las tres respuestas de las que depende -ResumeWhen5HoursLimit, y ninguna estaba
    en la documentacion oficial:

      1. si el evento de limite llega ANTES del evento de cierre (el runner lee el stream en
         orden: si llegara despues, cuando decide ya no lo tendria),
      2. cuanto reintenta solo el CLI antes de rendirse (define si el corte le llega al runner en
         segundos o en minutos),
      3. si --json-schema y --append-system-prompt siguen aplicando en un --resume (si no
         aplicaran, la sesion reanudada terminaria sin resultado estructurado y el semaforo la
         leeria como "no dejo resultado", que es la misma pared contra la que se choco).

    No gasta cuota: ninguna request sale de la maquina. Se corre de nuevo cuando el CLI cambia de
    version -- que es cuando estas respuestas pueden dejar de ser ciertas.

    El login normal se deja como esta a proposito: ver el encabezado de Start-FakeAnthropicApi.ps1.

.PARAMETER ClaudeCommand
    Que ejecutable medir. Default: el 'claude' que este en el PATH.

.PARAMETER KeepTemp
    No borra la carpeta temporal con los logs y los streams capturados.

.EXAMPLE
    pwsh -File .\tools\Measure-Limite5Horas.ps1

.NOTES
    Devuelve exit code 1 si alguna de las tres respuestas dejo de ser la esperada. Asi el arnes
    tambien sirve de alarma cuando una version nueva del CLI cambia el contrato.
#>

[CmdletBinding()]
param(
    [string]$ClaudeCommand = 'claude',
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

$script:EncodingPrevio = $null
try {
    $script:EncodingPrevio = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

$script:Servidor = Join-Path $PSScriptRoot 'Start-FakeAnthropicApi.ps1'
$script:Hallazgos = [System.Collections.Generic.List[object]]::new()

# El contrato real del runner, copiado tal cual: si se mide con otro esquema, no se esta midiendo
# lo que el producto hace.
$script:Esquema  = '{"type":"object","properties":{"result":{"type":"string","enum":["ok","stop"]},"reason":{"type":"string"}},"required":["result","reason"],"additionalProperties":false}'
$script:Marca    = 'MARCA-CONTRATO-ARNES-9137'

function Add-Hallazgo([string]$pregunta, [string]$esperado, [string]$obtenido, [bool]$bien) {
    $script:Hallazgos.Add([pscustomobject]@{
        Pregunta = $pregunta
        Esperado = $esperado
        Obtenido = $obtenido
        Bien     = $bien
    })
}

# --- El ejecutable a medir ------------------------------------------------

# Un 'claude' que resuelve a un shim .cmd no sirve para medir nada (es la misma razon por la que
# el runner no arranca con uno): se busca el .exe al lado, como hace el runner.
function Resolve-Claude([string]$comando) {
    $cmd = Get-Command $comando -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    $ruta = $cmd.Source
    if ($ruta -match '\.(cmd|bat)$') {
        $alLado = [System.IO.Path]::ChangeExtension($ruta, 'exe')
        if (Test-Path -LiteralPath $alLado) { return $alLado }
        return $null
    }
    return $ruta
}

# --- El servidor ----------------------------------------------------------

function Start-Servidor([string]$estado, [string]$log, [string]$escenario) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName  = (Get-Command pwsh).Source
    $psi.Arguments = "-NoProfile -File `"$script:Servidor`" -Scenario $escenario -StateFile `"$estado`" -RequestLog `"$log`""
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false

    $proceso = [System.Diagnostics.Process]::Start($psi)

    # La primera linea dice en que puerto quedo. Sin eso no hay a donde apuntar el CLI.
    $primera = $proceso.StandardOutput.ReadLine()
    if ($primera -notmatch '^LISTENING (\S+)$') {
        throw "el servidor no anuncio su puerto (dijo: '$primera')"
    }

    return [pscustomobject]@{ Proceso = $proceso; BaseUrl = $Matches[1] }
}

function Set-Escenario([string]$estado, [string]$escenario) {
    $j = Get-Content -LiteralPath $estado -Raw -Encoding UTF8 | ConvertFrom-Json
    $j.scenario = $escenario
    $j | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $estado -Encoding UTF8
}

# --- Correr una sesion ----------------------------------------------------

function Invoke-Sesion([string]$exe, [string[]]$argumentos, [string]$dondeGuardar) {
    $inicio = Get-Date
    $lineas = & $exe @argumentos 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $duracion = ((Get-Date) - $inicio).TotalSeconds

    Set-Content -LiteralPath $dondeGuardar -Value $lineas -Encoding UTF8

    $eventos = @()
    foreach ($linea in $lineas) {
        try { $eventos += ($linea | ConvertFrom-Json) } catch { }
    }

    return [pscustomobject]@{
        Lineas   = $lineas
        Eventos  = $eventos
        ExitCode = $code
        Duracion = $duracion
    }
}

function Get-Requests([string]$log) {
    if (-not (Test-Path -LiteralPath $log)) { return @() }
    return @(Get-Content -LiteralPath $log -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

# No toda request grande es EL TURNO. Ademas del turno, una corrida manda un sondeo de arranque y
# alguna llamada auxiliar del propio CLI (el titulo de la sesion, por ejemplo), que son legitimas
# y NO llevan el contrato porque no son la conversacion. Se distinguen por la caja de
# herramientas: el turno va con la del agente entero, las auxiliares con una sola o ninguna.
# Medir contra un umbral de bytes las confunde, y confundirlas da un falso negativo.
function Select-Turnos($requests) {
    return @($requests | Where-Object {
        if ($_.path -notlike '/v1/messages*') { return $false }
        try { return (@(($_.body | ConvertFrom-Json).tools).Count -gt 5) } catch { return $false }
    })
}

# --- La medicion ----------------------------------------------------------

$exe = Resolve-Claude $ClaudeCommand
if (-not $exe) {
    Write-Host "No encontre un ejecutable nativo para '$ClaudeCommand'." -ForegroundColor Red
    Write-Host "Si tu 'claude' es un shim .cmd, tiene que haber un .exe con el mismo nombre al lado." -ForegroundColor DarkGray
    exit 2
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-arnes-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $temp -Force | Out-Null

$estado = Join-Path $temp 'estado.json'
$log    = Join-Path $temp 'requests.jsonl'

Write-Host ""
Write-Host "== Arnes del limite de 5 horas ==" -ForegroundColor Cyan
Write-Host "  ejecutable medido : $exe"
Write-Host "  version           : $((& $exe --version 2>&1 | Select-Object -First 1))"
Write-Host "  carpeta temporal  : $temp"
Write-Host ""

$servidor = Start-Servidor $estado $log 'five-hour-limit'
$baseUrlPrevio = $env:ANTHROPIC_BASE_URL
$env:ANTHROPIC_BASE_URL = $servidor.BaseUrl

$comunes = @(
    '-p',
    '--output-format', 'stream-json',
    '--verbose',
    '--json-schema', $script:Esquema,
    '--append-system-prompt', $script:Marca
)

try {
    Push-Location -LiteralPath $temp

    # --- Sesion 1: choca contra el limite ---------------------------------
    Write-Host "1. Una sesion que le pega al limite de 5 horas..." -ForegroundColor Yellow
    $choque = Invoke-Sesion $exe ($comunes + @('sesion que choca')) (Join-Path $temp 'stream-choque.txt')

    $tipos = @($choque.Eventos | ForEach-Object { $_.type })
    $iLimite = $tipos.IndexOf('rate_limit_event')
    $iResult = $tipos.IndexOf('result')
    $limite  = @($choque.Eventos | Where-Object { $_.type -eq 'rate_limit_event' })[0]
    $result  = @($choque.Eventos | Where-Object { $_.type -eq 'result' })[0]
    $sesion  = $result.session_id

    Add-Hallazgo 'el evento de limite llega antes que el de cierre' `
        'rate_limit_event antes de result' `
        "rate_limit_event en la posicion $iLimite, result en la $iResult" `
        ($iLimite -ge 0 -and $iResult -ge 0 -and $iLimite -lt $iResult)

    Add-Hallazgo 'el limite de 5 horas se distingue de los demas' `
        'rateLimitType=five_hour y status=rejected' `
        "rateLimitType=$($limite.rate_limit_info.rateLimitType) status=$($limite.rate_limit_info.status)" `
        ($limite.rate_limit_info.rateLimitType -eq 'five_hour' -and $limite.rate_limit_info.status -eq 'rejected')

    $vence = $null
    if ($limite.rate_limit_info.resetsAt) {
        $vence = [DateTimeOffset]::FromUnixTimeSeconds([long]$limite.rate_limit_info.resetsAt).ToLocalTime()
    }
    Add-Hallazgo 'el evento dice cuando vence el limite' `
        'resetsAt presente, epoch en segundos' `
        $(if ($vence) { "resetsAt=$($limite.rate_limit_info.resetsAt) (hora local: $($vence.ToString('yyyy-MM-dd HH:mm:ss')))" } else { 'sin resetsAt' }) `
        ($null -ne $vence)

    # Los reintentos: cuantas veces se mando el TURNO, no los sondeos ni las auxiliares.
    $intentos = @(Select-Turnos (Get-Requests $log) | Where-Object { $_.status -eq 429 })
    Add-Hallazgo 'cuanto reintenta solo el CLI' `
        'un solo intento: el corte le llega al runner en segundos' `
        "$($intentos.Count) intento(s) del turno, $([Math]::Round($choque.Duracion, 1))s en total" `
        ($intentos.Count -eq 1)

    Add-Hallazgo 'como cierra la sesion que choco' `
        'exit code distinto de cero, terminal_reason=api_error, api_error_status=429' `
        "exit=$($choque.ExitCode) terminal_reason=$($result.terminal_reason) api_error_status=$($result.api_error_status)" `
        ($choque.ExitCode -ne 0 -and $result.terminal_reason -eq 'api_error' -and $result.api_error_status -eq 429)

    Add-Hallazgo 'la sesion que choco no deja resultado estructurado' `
        'sin structured_output (por eso el semaforo la leeria como "sin resultado")' `
        $(if ($null -eq $result.structured_output) { 'sin structured_output' } else { 'dejo structured_output' }) `
        ($null -eq $result.structured_output)

    # --- Sesion 2: el resume, con el limite ya vencido ---------------------
    Write-Host "2. El resume de esa misma sesion, con el limite ya vencido..." -ForegroundColor Yellow
    Set-Escenario $estado 'ok'
    $antes = (Get-Requests $log).Count

    $resume = Invoke-Sesion $exe (@('-p', '--resume', $sesion, '--output-format', 'stream-json', '--verbose',
                                    '--json-schema', $script:Esquema, '--append-system-prompt', $script:Marca,
                                    'Le pegaste al limite de 5 horas. Continua.')) (Join-Path $temp 'stream-resume.txt')

    $resResume = @($resume.Eventos | Where-Object { $_.type -eq 'result' })[0]

    Add-Hallazgo 'una sesion cortada por limite se puede reanudar' `
        'exit code 0 y el mismo session_id' `
        "exit=$($resume.ExitCode) sesion=$($resResume.session_id) (la que choco: $sesion)" `
        ($resume.ExitCode -eq 0 -and $resResume.session_id -eq $sesion)

    Add-Hallazgo 'la sesion reanudada deja el resultado estructurado' `
        'structured_output con result y reason' `
        "$($resResume.structured_output | ConvertTo-Json -Compress)" `
        ($null -ne $resResume.structured_output -and $null -ne $resResume.structured_output.result)

    # Lo que de verdad importa: que el contrato viaje en la request del resume, no solo que el
    # comando lo acepte sin quejarse.
    $nuevas     = @(Get-Requests $log | Select-Object -Skip $antes)
    $delResume  = Select-Turnos $nuevas
    $auxiliares = @($nuevas | Where-Object { $_.path -like '/v1/messages*' }).Count - $delResume.Count
    $conMarca   = @($delResume | Where-Object { $_.body -match $script:Marca })
    $conEsquema = @($delResume | Where-Object { $_.body -match '"StructuredOutput"' })

    Add-Hallazgo 'el contrato sigue aplicando en el resume' `
        'la request del resume lleva el system prompt agregado y la herramienta del esquema' `
        ("$($conMarca.Count)/$($delResume.Count) turno(s) con el system prompt, " +
         "$($conEsquema.Count)/$($delResume.Count) con la herramienta " +
         "(mas $auxiliares llamada(s) auxiliar(es) del CLI, que no llevan contrato)") `
        ($delResume.Count -gt 0 -and $conMarca.Count -eq $delResume.Count -and $conEsquema.Count -eq $delResume.Count)

    # El costo del resume, medido: la conversacion entera se vuelve a mandar.
    $mensajesResume = 0
    if ($delResume.Count -gt 0) {
        $mensajesResume = @(($delResume[0].body | ConvertFrom-Json).messages).Count
    }
    Add-Hallazgo 'que se re-manda en el resume' `
        'la conversacion entera (por eso el resume no es gratis)' `
        "$mensajesResume mensajes en la request del resume" `
        ($mensajesResume -gt 1)

} finally {
    Pop-Location
    $env:ANTHROPIC_BASE_URL = $baseUrlPrevio
    if ($servidor.Proceso -and -not $servidor.Proceso.HasExited) {
        $servidor.Proceso.Kill()
        $servidor.Proceso.WaitForExit(5000) | Out-Null
    }
}

# --- El informe -----------------------------------------------------------

Write-Host ""
Write-Host "== Lo que se midio ==" -ForegroundColor Cyan
$fallados = 0
foreach ($h in $script:Hallazgos) {
    if ($h.Bien) {
        Write-Host "  OK    $($h.Pregunta)" -ForegroundColor Green
    } else {
        $fallados++
        Write-Host "  CAMBIO $($h.Pregunta)" -ForegroundColor Red
        Write-Host "         esperado: $($h.Esperado)" -ForegroundColor DarkRed
    }
    Write-Host "         $($h.Obtenido)" -ForegroundColor DarkGray
}

Write-Host ""
if ($fallados -gt 0) {
    Write-Host "$fallados de $($script:Hallazgos.Count) respuestas cambiaron respecto de lo medido." -ForegroundColor Red
    Write-Host "-ResumeWhen5HoursLimit se apoya en ellas: revisa el runner antes de confiar en el flag." -ForegroundColor Yellow
} else {
    Write-Host "Las $($script:Hallazgos.Count) respuestas siguen siendo las mismas." -ForegroundColor Green
}

if ($KeepTemp) {
    Write-Host ""
    Write-Host "Logs y streams capturados en: $temp" -ForegroundColor DarkGray
} else {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:EncodingPrevio) {
    try { [Console]::OutputEncoding = $script:EncodingPrevio } catch { }
}

exit $(if ($fallados -gt 0) { 1 } else { 0 })
