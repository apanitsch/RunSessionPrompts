#Requires -Version 7.0
<#
.SYNOPSIS
    Genera docs/ejemplo-corrida.svg, la captura de terminal del ejemplo del README.

.DESCRIPTION
    El bloque de consola del ejemplo va como imagen porque GitHub no renderiza colores en un
    bloque de codigo, y los colores del runner distinguen la pregunta (cyan) del detalle
    (gris), lo que pide atencion (amarillo) y lo que cerro bien (verde).

    Como es una imagen, nada lo verifica: si cambia una cadena que Run-SessionPrompts.ps1
    imprime, hay que actualizar la lista de $lineas de aca abajo y volver a correr esto. El
    texto de cada linea es EXACTO al del runner -- si lo editas, copialo del script, no de
    memoria.

.EXAMPLE
    pwsh -File .\docs\gen-ejemplo-corrida.ps1
#>

$ErrorActionPreference = 'Stop'

# Esquema Campbell, el default de Windows Terminal y pwsh. Los nombres son los ConsoleColor
# que el runner le pasa a Write-Host -ForegroundColor.
$col = @{
    fg       = '#cccccc'   # sin color: el foreground del host (Read-Host y lo que sale del propio claude)
    cyan     = '#61d6d6'
    yellow   = '#f9f1a5'
    darkgray = '#767676'
    green    = '#16c60c'
    bg       = '#0c0c0c'
}

# La corrida de ejemplo: nueve sesiones, de las que se muestran la 01, la 02 y la 09.
$lineas = @(
    @('fg',       'PS C:\repos\MiApp> pwsh -File .\docs\session-prompts\Run-SessionPrompts.ps1'),
    @('fg',       ''),
    @('cyan',     'Series pendientes (en orden de ejecucion propuesta):'),
    @('fg',       '  [1] invitaciones (9 prompts)'),
    @('fg',       '  [2] limpiar-appsettings (3 prompts)'),
    @('fg',       'Elegi el numero (o pega una ruta): 1'),
    @('darkgray', 'Serie: invitaciones'),
    @('fg',       'Empezar desde el numero (Enter = desde el primero; la serie llega hasta el 9):'),
    @('cyan',     'Modelo:'),
    @('fg',       '  [1] Opus 5 (default)'),
    @('fg',       '  [2] Sonnet 5'),
    @('fg',       'Elegi el numero (Enter = Opus 5):'),
    @('cyan',     'Effort:'),
    @('fg',       '  [1] high (default)'),
    @('fg',       '  [2] low'),
    @('fg',       '  [3] medium'),
    @('fg',       '  [4] xhigh'),
    @('fg',       '  [5] max'),
    @('fg',       'Elegi el numero (Enter = high):'),
    @('fg',       ''),
    @('yellow',   '01-link-token-y-destino.md sugiere effort xhigh y la corrida esta en high.'),
    @('fg',       '  [1] Usar xhigh en ESTA sesion (lo que pide el prompt)  (default)'),
    @('fg',       '  [2] Correrla igual con high'),
    @('fg',       '  [3] Abortar'),
    @('fg',       'Elegi el numero (Enter = 1):'),
    @('fg',       ''),
    @('cyan',     "Ejecutando 9 prompts de la serie 'invitaciones'"),
    @('darkgray', 'Prompts: C:\repos\MiApp\docs\session-prompts\invitaciones'),
    @('darkgray', 'Proyecto (directorio de trabajo): C:\repos\MiApp'),
    @('darkgray', 'Tope de la corrida: Opus 5 (claude-opus-5)  |  effort high'),
    @('darkgray', 'Permisos: --permission-mode acceptEdits'),
    @('darkgray', "Argumentos nativos: NO escapa (lo hace PowerShell) -- modo fijado en 'Standard' por el script; PowerShell escapa"),
    @('yellow',   '  01-link-token-y-destino.md         Opus 5   effort xhigh   <- effort sugerido (SUBE, confirmado)'),
    @('darkgray', '  02-modelo-de-la-invitacion.md      Opus 5   effort high'),
    @('darkgray', '  (...)'),
    @('darkgray', '  09-decisiones-y-cierre.md          Opus 5   effort high'),
    @('darkgray', 'Cada sesion tiene Remote Control. Para pasar a la siguiente, cerra la actual con /exit.'),
    @('fg',       ''),
    @('cyan',     '== Sesion: 01-link-token-y-destino.md  [Opus 5, effort xhigh]  (/exit para pasar a la proxima) =='),
    @('fg',       '(...)'),
    @('green',    'Cerrada 01-link-token-y-destino.md (00:41:02).'),
    @('fg',       ''),
    @('cyan',     '== Sesion: 02-modelo-de-la-invitacion.md  [Opus 5, effort high]  (/exit para pasar a la proxima) =='),
    @('fg',       '(...)'),
    @('green',    'Cerrada 02-modelo-de-la-invitacion.md (00:33:57).'),
    @('fg',       ''),
    @('fg',       '(...)'),
    @('fg',       ''),
    @('cyan',     '== Sesion: 09-decisiones-y-cierre.md  [Opus 5, effort high]  (/exit para pasar a la proxima) =='),
    @('fg',       '(...)'),
    @('green',    'Cerrada 09-decisiones-y-cierre.md (00:21:40).'),
    @('fg',       ''),
    @('green',    'Todos los prompts se ejecutaron correctamente (9 sesiones, 06:12:44).'),
    @('darkgray', "series-estado.txt: 'invitaciones' marcada terminada.")
)

# Sin fuente embebida: un SVG que GitHub muestra como <img> no puede bajar una externa, y
# embeberla pesaria mas que todo el resto junto. Cualquier monoespaciada del sistema alinea
# las columnas del plan, porque cada linea es su propio <text>.
$fontFamily = "ui-monospace, 'Cascadia Mono', 'Cascadia Code', Consolas, 'DejaVu Sans Mono', 'Courier New', monospace"
$fontSize   = 13
$lineHeight = 19
$padX       = 18
$padY       = 24
$charW      = $fontSize * 0.6   # avance tipico de una monoespaciada

$maxChars = ($lineas | ForEach-Object { $_[1].Length } | Measure-Object -Maximum).Maximum
$width    = [math]::Ceiling($maxChars * $charW) + (2 * $padX)
$height   = ($lineas.Count * $lineHeight) + (2 * $padY) - ($lineHeight - $fontSize)

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`" font-family=`"$fontFamily`" font-size=`"$fontSize`">")
[void]$sb.AppendLine('  <title>Run-SessionPrompts.ps1: una corrida de nueve sesiones</title>')
[void]$sb.AppendLine("  <rect width=`"$width`" height=`"$height`" rx=`"8`" fill=`"$($col.bg)`"/>")

$y = $padY + $fontSize - 3
foreach ($linea in $lineas) {
    $texto = $linea[1]
    if ($texto -ne '') {
        $esc = $texto -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
        [void]$sb.AppendLine("  <text x=`"$padX`" y=`"$y`" fill=`"$($col[$linea[0]])`" xml:space=`"preserve`">$esc</text>")
    }
    $y += $lineHeight
}
[void]$sb.AppendLine('</svg>')

$destino = Join-Path $PSScriptRoot 'ejemplo-corrida.svg'
[IO.File]::WriteAllText($destino, $sb.ToString(), [Text.UTF8Encoding]::new($false))
Write-Host "Escrito $destino ($width x $height, $($lineas.Count) lineas)" -ForegroundColor Green
