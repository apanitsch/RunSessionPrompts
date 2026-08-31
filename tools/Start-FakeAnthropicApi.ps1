#Requires -Version 7.0
<#
.SYNOPSIS
    API falsa de Anthropic: maneja a claude.exe desde afuera, sin gastar cuota.

.DESCRIPTION
    Levanta un servidor HTTP minimo en loopback y contesta /v1/messages segun el escenario que
    diga su archivo de estado. Existe para MEDIR que hace el CLI de verdad -- que eventos emite,
    en que orden, cuanto reintenta, que manda en cada request -- en situaciones que de otro modo
    hay que esperar horas para reproducir, como pegarle al limite de uso de 5 horas.

    El CLI se apunta aca con ANTHROPIC_BASE_URL. El login normal (OAuth de suscripcion) se deja
    como esta a proposito: la extraccion de cuota de un 429 depende de que la sesion sea de
    suscripcion, no de a que host apunta, asi que cambiar la base URL no la apaga. Con una API
    key falsa, en cambio, ese camino puede no correr y la medicion daria un falso negativo.

    NO usa System.Net.HttpListener a proposito: en Windows sus prefijos piden una reserva de URL
    (netsh http add urlacl) o privilegios de administrador, y eso convertiria al arnes en algo
    que no se puede correr en cualquier maquina. Un TcpListener en loopback no pide nada, y el
    HTTP que hay que hablar aca es minimo.

    El escenario se cambia EN CALIENTE reescribiendo el archivo de estado: el servidor lo relee
    antes de contestar cada request. Asi una misma corrida puede empezar bien, pegarle al limite
    y despues reanudar, que es exactamente la secuencia que hay que medir.

.PARAMETER Port
    Puerto de escucha. 0 (default) toma uno libre; la primera linea que imprime el servidor dice
    cual quedo, con el formato 'LISTENING http://127.0.0.1:<puerto>'.

.PARAMETER StateFile
    Archivo JSON con el escenario. Se relee antes de cada respuesta.

.PARAMETER RequestLog
    Archivo JSONL donde se anota cada request recibida: metodo, path, cabeceras elegidas y el
    cuerpo entero. Es lo que permite verificar QUE manda el CLI -- system prompt, herramientas,
    esquema -- sin adivinar.

.PARAMETER Scenario
    Escenario inicial, que se escribe en el archivo de estado al arrancar:
      ok               respuesta valida; si la request declara la herramienta StructuredOutput,
                       contesta llamandola, asi la sesion termina con resultado estructurado
      five-hour-limit  429 con las cabeceras del limite de 5 horas (unified-status: rejected,
                       representative-claim: five_hour, unified-reset y retry-after)
      seven-day-limit  igual, pero el reclamo representativo es seven_day
      overloaded       529, para poder distinguir sobrecarga de limite de uso
      server-error     500

.PARAMETER ResetsInSeconds
    Cuanto falta para que venza el limite, en los escenarios de 429. Default 18000 (5 horas).

.EXAMPLE
    pwsh -File .\tools\Start-FakeAnthropicApi.ps1 -Scenario five-hour-limit -StateFile .\estado.json -RequestLog .\requests.jsonl

.NOTES
    Las credenciales NO se anotan: de la cabecera Authorization se registra solo si vino y con
    que esquema. Un arnes que deja el token en un archivo de log es un arnes que no se puede
    correr tranquilo.
#>

[CmdletBinding()]
param(
    [int]$Port = 0,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$RequestLog,
    [ValidateSet('ok', 'five-hour-limit', 'seven-day-limit', 'overloaded', 'server-error')]
    [string]$Scenario = 'ok',
    [int]$ResetsInSeconds = 18000
)

$ErrorActionPreference = 'Stop'

# Misma regla que el runner y el instalador, y por el mismo motivo: lo que este proceso imprime
# lo lee otro proceso. Arriba de todo, porque el host se queda con el encoding que tenia cuando
# escribio por primera vez.
$script:EncodingPrevio = $null
try {
    $script:EncodingPrevio = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
    Write-Warning "no pude fijar la consola en UTF-8: $($_.Exception.Message)"
}

# --- Estado ---------------------------------------------------------------

function Write-Estado([string]$ruta, [string]$escenario, [int]$resetEnSegundos) {
    $estado = [ordered]@{
        scenario        = $escenario
        resetsInSeconds = $resetEnSegundos
        # Lo que la sesion "devuelve" cuando el escenario es 'ok' y la request trae el esquema.
        result          = 'ok'
        reason          = 'la sesion falsa hizo lo suyo'
        text            = 'listo'
    }
    Set-Content -LiteralPath $ruta -Encoding UTF8 -Value ($estado | ConvertTo-Json -Depth 5)
}

function Read-Estado([string]$ruta) {
    # Se relee por request, asi el escenario se puede cambiar en caliente. Si justo lo estan
    # reescribiendo, se usa lo ultimo bueno en vez de reventar la conexion.
    try {
        return (Get-Content -LiteralPath $ruta -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $script:UltimoEstado
    }
}

# --- HTTP a mano ----------------------------------------------------------

function Find-FinCabecera($bytes, [int]$desde) {
    for ($i = [Math]::Max(3, $desde); $i -lt $bytes.Count; $i++) {
        if ($bytes[$i - 3] -eq 13 -and $bytes[$i - 2] -eq 10 -and $bytes[$i - 1] -eq 13 -and $bytes[$i] -eq 10) {
            return $i
        }
    }
    return -1
}

function Read-Peticion($stream) {
    $acumulado = [System.Collections.Generic.List[byte]]::new()
    $chunk = [byte[]]::new(16384)
    $fin = -1

    while ($fin -lt 0) {
        $n = $stream.Read($chunk, 0, $chunk.Length)
        if ($n -le 0) { return $null }
        $parcial = [byte[]]::new($n)
        [Array]::Copy($chunk, 0, $parcial, 0, $n)
        $desde = [Math]::Max(3, $acumulado.Count)
        $acumulado.AddRange($parcial)
        $fin = Find-FinCabecera $acumulado $desde
    }

    $bytesCabecera = [byte[]]::new($fin - 3)
    $acumulado.CopyTo(0, $bytesCabecera, 0, $fin - 3)
    $textoCabecera = [System.Text.Encoding]::ASCII.GetString($bytesCabecera)
    $lineas = $textoCabecera -split "`r`n"

    $partes = $lineas[0] -split ' '
    $metodo = $partes[0]
    $path   = if ($partes.Count -gt 1) { $partes[1] } else { '/' }

    $cabeceras = @{}
    if ($lineas.Count -gt 1) {
        foreach ($linea in $lineas[1..($lineas.Count - 1)]) {
            $corte = $linea.IndexOf(':')
            if ($corte -gt 0) {
                $cabeceras[$linea.Substring(0, $corte).Trim().ToLowerInvariant()] = $linea.Substring($corte + 1).Trim()
            }
        }
    }

    # El cuerpo: lo que ya vino pegado a la cabecera, mas lo que falte segun Content-Length.
    $yaLeido = $acumulado.Count - ($fin + 1)
    $largo = 0
    if ($cabeceras.ContainsKey('content-length')) { $largo = [int]$cabeceras['content-length'] }

    $cuerpo = [byte[]]::new($largo)
    if ($largo -gt 0) {
        $copiar = [Math]::Min($yaLeido, $largo)
        if ($copiar -gt 0) { $acumulado.CopyTo($fin + 1, $cuerpo, 0, $copiar) }
        $leido = $copiar
        while ($leido -lt $largo) {
            $n = $stream.Read($cuerpo, $leido, $largo - $leido)
            if ($n -le 0) { break }
            $leido += $n
        }
    }

    return [pscustomobject]@{
        Metodo    = $metodo
        Path      = $path
        Cabeceras = $cabeceras
        Cuerpo    = [System.Text.Encoding]::UTF8.GetString($cuerpo)
    }
}

function Write-Respuesta($stream, [int]$codigo, [string]$razon, [hashtable]$cabeceras, [string]$cuerpo, [switch]$SinContentLength) {
    $bytesCuerpo = [System.Text.Encoding]::UTF8.GetBytes($cuerpo)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("HTTP/1.1 $codigo $razon`r`n")
    foreach ($clave in $cabeceras.Keys) {
        [void]$sb.Append("${clave}: $($cabeceras[$clave])`r`n")
    }
    if (-not $SinContentLength) {
        [void]$sb.Append("Content-Length: $($bytesCuerpo.Length)`r`n")
    }
    [void]$sb.Append("Connection: close`r`n`r`n")

    $bytesCabecera = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $stream.Write($bytesCabecera, 0, $bytesCabecera.Length)
    if ($bytesCuerpo.Length -gt 0) { $stream.Write($bytesCuerpo, 0, $bytesCuerpo.Length) }
    $stream.Flush()
}

# --- Las respuestas de cada escenario -------------------------------------

function New-EventoSse([string]$tipo, $datos) {
    return "event: $tipo`n" + "data: " + ($datos | ConvertTo-Json -Depth 12 -Compress) + "`n`n"
}

# Un stream de Messages API valido. Si la request declara la herramienta StructuredOutput -- que
# es como el CLI implementa --json-schema -- se contesta LLAMANDOLA, para que la sesion termine
# dejando el resultado estructurado que el runner espera.
function New-StreamMensajes($estado, [string]$cuerpoPeticion) {
    $usaEsquema = $cuerpoPeticion -match '"StructuredOutput"'

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append((New-EventoSse 'message_start' ([ordered]@{
        type    = 'message_start'
        message = [ordered]@{
            id            = 'msg_arnes'
            type          = 'message'
            role          = 'assistant'
            model         = 'claude-opus-5'
            content       = @()
            stop_reason   = $null
            stop_sequence = $null
            usage         = [ordered]@{ input_tokens = 10; output_tokens = 1 }
        }
    })))

    if ($usaEsquema) {
        $entrada = ([ordered]@{ result = "$($estado.result)"; reason = "$($estado.reason)" } | ConvertTo-Json -Compress)
        [void]$sb.Append((New-EventoSse 'content_block_start' ([ordered]@{
            type          = 'content_block_start'
            index         = 0
            content_block = [ordered]@{ type = 'tool_use'; id = 'toolu_arnes'; name = 'StructuredOutput'; input = @{} }
        })))
        [void]$sb.Append((New-EventoSse 'content_block_delta' ([ordered]@{
            type  = 'content_block_delta'
            index = 0
            delta = [ordered]@{ type = 'input_json_delta'; partial_json = $entrada }
        })))
        $motivoCorte = 'tool_use'
    } else {
        [void]$sb.Append((New-EventoSse 'content_block_start' ([ordered]@{
            type          = 'content_block_start'
            index         = 0
            content_block = [ordered]@{ type = 'text'; text = '' }
        })))
        [void]$sb.Append((New-EventoSse 'content_block_delta' ([ordered]@{
            type  = 'content_block_delta'
            index = 0
            delta = [ordered]@{ type = 'text_delta'; text = "$($estado.text)" }
        })))
        $motivoCorte = 'end_turn'
    }

    [void]$sb.Append((New-EventoSse 'content_block_stop' ([ordered]@{ type = 'content_block_stop'; index = 0 })))
    [void]$sb.Append((New-EventoSse 'message_delta' ([ordered]@{
        type  = 'message_delta'
        delta = [ordered]@{ stop_reason = $motivoCorte; stop_sequence = $null }
        usage = [ordered]@{ output_tokens = 20 }
    })))
    [void]$sb.Append((New-EventoSse 'message_stop' ([ordered]@{ type = 'message_stop' })))

    return $sb.ToString()
}

# Las cabeceras del 429 son el corazon del arnes: son exactamente las que el CLI mira para saber
# QUE limite se alcanzo y CUANDO vence.
function Get-CabecerasLimite([string]$reclamo, [int]$resetEnSegundos) {
    $vence = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $resetEnSegundos
    return @{
        'Content-Type'                                     = 'application/json'
        'anthropic-ratelimit-unified-status'               = 'rejected'
        'anthropic-ratelimit-unified-representative-claim' = $reclamo
        'anthropic-ratelimit-unified-reset'                = "$vence"
        'retry-after'                                      = "$resetEnSegundos"
    }
}

function Invoke-Peticion($peticion, $estado, $stream) {
    if ($peticion.Path -match '^/v1/messages/count_tokens') {
        Write-Respuesta $stream 200 'OK' @{ 'Content-Type' = 'application/json' } '{"input_tokens":42}'
        return 200
    }

    if ($peticion.Path -notmatch '^/v1/messages(\?|$)') {
        # Todo lo demas -- sondeos de arranque, telemetria, preferencias -- se contesta vacio y
        # queda en el log. Un 404 aca haria ruido que no es el que se esta midiendo.
        Write-Respuesta $stream 200 'OK' @{ 'Content-Type' = 'application/json' } '{}'
        return 200
    }

    switch ("$($estado.scenario)") {
        'five-hour-limit' {
            $cuerpo = '{"type":"error","error":{"type":"rate_limit_error","message":"You have hit your 5-hour usage limit."}}'
            Write-Respuesta $stream 429 'Too Many Requests' (Get-CabecerasLimite 'five_hour' ([int]$estado.resetsInSeconds)) $cuerpo
            return 429
        }
        'seven-day-limit' {
            $cuerpo = '{"type":"error","error":{"type":"rate_limit_error","message":"You have hit your weekly usage limit."}}'
            Write-Respuesta $stream 429 'Too Many Requests' (Get-CabecerasLimite 'seven_day' ([int]$estado.resetsInSeconds)) $cuerpo
            return 429
        }
        'overloaded' {
            $cuerpo = '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
            Write-Respuesta $stream 529 'Overloaded' @{ 'Content-Type' = 'application/json' } $cuerpo
            return 529
        }
        'server-error' {
            $cuerpo = '{"type":"error","error":{"type":"api_error","message":"Internal server error"}}'
            Write-Respuesta $stream 500 'Internal Server Error' @{ 'Content-Type' = 'application/json' } $cuerpo
            return 500
        }
        default {
            $sse = New-StreamMensajes $estado $peticion.Cuerpo
            Write-Respuesta $stream 200 'OK' @{ 'Content-Type' = 'text/event-stream'; 'Cache-Control' = 'no-cache' } $sse -SinContentLength
            return 200
        }
    }
}

# --- Log de requests ------------------------------------------------------

function Write-Registro($peticion, $estado, [int]$codigo, [string]$archivo) {
    $auth = $peticion.Cabeceras['authorization']
    $entrada = [ordered]@{
        ts         = [DateTimeOffset]::UtcNow.ToString('o')
        method     = $peticion.Metodo
        path       = $peticion.Path
        scenario   = "$($estado.scenario)"
        status     = $codigo
        # De la credencial se anota SOLO si vino y con que esquema. Nunca el valor.
        authScheme = if ($auth) { ($auth -split ' ')[0] } else { $null }
        beta       = $peticion.Cabeceras['anthropic-beta']
        userAgent  = $peticion.Cabeceras['user-agent']
        body       = $peticion.Cuerpo
    }
    Add-Content -LiteralPath $archivo -Encoding UTF8 -Value ($entrada | ConvertTo-Json -Depth 6 -Compress)
}

# --- Arranque -------------------------------------------------------------

Write-Estado $StateFile $Scenario $ResetsInSeconds
$script:UltimoEstado = Read-Estado $StateFile
if (Test-Path -LiteralPath $RequestLog) { Remove-Item -LiteralPath $RequestLog -Force }

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
$puerto = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

# La primera linea es el contrato con quien lo arranca: de aca sale el ANTHROPIC_BASE_URL.
Write-Output "LISTENING http://127.0.0.1:$puerto"

try {
    while ($true) {
        $cliente = $listener.AcceptTcpClient()
        try {
            # Se atiende de a una conexion por vez a proposito, para que el arnes no tenga hilos.
            # El timeout es lo que impide que una conexion que el pool del cliente abre y deja
            # ociosa trabe el servidor entero.
            $cliente.ReceiveTimeout = 15000
            $cliente.SendTimeout    = 15000
            $stream = $cliente.GetStream()

            $peticion = Read-Peticion $stream
            if ($null -eq $peticion) { continue }

            $estado = Read-Estado $StateFile
            $script:UltimoEstado = $estado

            $codigo = Invoke-Peticion $peticion $estado $stream
            Write-Registro $peticion $estado $codigo $RequestLog
            Write-Output "$($peticion.Metodo) $($peticion.Path) -> $codigo [$($estado.scenario)]"
        } catch {
            Write-Output "ERROR $($_.Exception.Message)"
        } finally {
            $cliente.Close()
            $cliente.Dispose()
        }
    }
} finally {
    $listener.Stop()
    if ($script:EncodingPrevio) {
        try { [Console]::OutputEncoding = $script:EncodingPrevio } catch { }
    }
}
