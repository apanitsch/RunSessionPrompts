#Requires -Version 7.0
# Ver la nota de encoding de Run-SessionPrompts.ps1: este archivo tambien se mantiene en ASCII puro.

<#
.SYNOPSIS
    Instala (o actualiza) Run-SessionPrompts.ps1 y sus plantillas en otro repositorio.

.DESCRIPTION
    Copia el runner, el README del andamiaje, las plantillas y -- la primera vez -- el
    series-estado.txt y el session-prompts.config.json de ejemplo, a la carpeta de series del
    repo destino (por defecto docs/session-prompts, o Docs/session-prompts si el repo ya usa esa).

    Al final, y salvo que se pase -SkipClaudeMd, lanza UNA sesion de Claude Code en el repo
    destino para que deje el andamiaje descubrible en su CLAUDE.md y corrija lo que haya quedado
    de versiones viejas del script. El prompt de esa sesion es
    templates/prompt-instalacion-claude-md.md, y se puede editar.

    Deja un archivo .session-prompts-version con la version instalada y el hash del runner.
    Con eso, una actualizacion posterior puede distinguir tres situaciones:
      - el runner del destino es identico al que instalamos  -> se pisa sin preguntar,
      - esta MODIFICADO a mano                               -> avisa y no pisa (salvo -Force),
      - no hay marca de version (instalacion vieja, copiada
        y pegada a mano)                                     -> avisa y no pisa (salvo -Force).

    Lo que NUNCA se pisa: las series (las carpetas con los prompts), el series-estado.txt, el
    session-prompts.config.json, y un README.md propio del repo que no haya puesto este
    instalador. Ahi vive el trabajo del repo destino.

.PARAMETER FromRelease
    Baja un release publicado en GitHub y instala desde ahi, en vez de instalar desde la carpeta
    donde esta este archivo. 'latest' para el ultimo, o un tag ('v1.2.3') para uno concreto.

    NO hace falta pasarlo para el caso normal: si este archivo esta SOLO -- sin el resto del
    producto al lado, que es como queda cuando lo bajas por su cuenta -- baja el ultimo release
    igual. El parametro esta para pedir un tag distinto del ultimo, o para forzar la descarga
    teniendo el producto al lado.

.PARAMETER ReleaseZip
    Instala desde un .zip del release ya bajado, sin tocar la red. Es lo que usa -FromRelease por
    debajo, y sirve para una maquina sin salida a internet.

.PARAMETER Repo
    Raiz del repo destino. Default: el directorio actual.

.PARAMETER SeriesRoot
    Carpeta de series del destino. Default: la que ya exista (docs/session-prompts o
    Docs/session-prompts), o docs/session-prompts si no hay ninguna.

.PARAMETER SkipClaudeMd
    No lanza la sesion de Claude Code que documenta el andamiaje en el CLAUDE.md del destino.
    (Con -WhatIf tampoco se lanza.)

.PARAMETER Model
    Modelo de esa sesion: 'opus' (default) o 'sonnet'.

.PARAMETER Effort
    Effort de esa sesion: low, medium, high (default), xhigh, max.

.PARAMETER Force
    Pisa el runner aunque este modificado a mano o no tenga marca de version. Antes de
    pisarlo deja una copia al lado, con extension .bak.

.PARAMETER WhatIf
    Dice que haria y no toca nada.

.EXAMPLE
    # Instalar en el repo donde estas parado. Si este archivo esta solo, baja el ultimo release.
    pwsh -File .\Install-SessionPrompts.ps1

.EXAMPLE
    # Instalar en otro repo.
    .\Install-SessionPrompts.ps1 -Repo C:\Users\andre\source\repos\MiProyecto

.EXAMPLE
    # Ver que haria una actualizacion, sin tocar nada.
    .\Install-SessionPrompts.ps1 -Repo C:\...\MiProyecto -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$FromRelease,
    [string]$ReleaseZip,
    [string]$Repo,
    [string]$SeriesRoot,
    [switch]$Force,
    [switch]$SkipClaudeMd,

    [ValidateSet('opus', 'sonnet')]
    [string]$Model = 'opus',

    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')]
    [string]$Effort = 'high',

    # Se expone para poder apuntarlo a otra instalacion, o a un doble de prueba.
    [string]$ClaudeCommand = 'claude'
)

$ErrorActionPreference = 'Stop'

# El producto vive aca. La misma constante esta en el runner, para su chequeo de version.
$script:RepoGitHub = 'apanitsch/RunSessionPrompts'

# --- Instalar desde un release en vez de desde esta carpeta ----------------
# La idea es que ESTE archivo solo alcance: lo bajas suelto, lo corres, y el se encarga de traer
# el resto. Lo que hace es bajar el .zip del tag, descomprimirlo, y REEJECUTAR el instalador que
# viene adentro -- no el de aca. Asi la instalacion la hace siempre la version que se esta
# instalando, y este archivo puede quedar viejo sin que importe.
#
# Se dispara solo cuando hace falta: si el producto esta al lado (un clon, o el release ya
# descomprimido) se instala desde ahi, sin tocar la red. Si no esta, no hay de donde instalar,
# asi que se baja -- por eso el caso normal no necesita ningun parametro.
$productoAlLado = Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Run-SessionPrompts.ps1')

if ($FromRelease -or $ReleaseZip -or -not $productoAlLado) {
    # Cinturon contra un lazo infinito: si el zip bajado no trajera el producto, el instalador
    # de adentro volveria a bajar, y asi para siempre.
    if ($env:SESSION_PROMPTS_INSTALANDO -eq '1') {
        Write-Host "El release que baje no trae Run-SessionPrompts.ps1 al lado del instalador." -ForegroundColor Red
        exit 1
    }

    if (-not $productoAlLado -and -not $FromRelease -and -not $ReleaseZip) {
        Write-Host "No tengo el producto al lado de este archivo, asi que lo bajo del ultimo release." -ForegroundColor DarkGray
    }

    $zip = $ReleaseZip

    # Mismo override que el runner: un zip ya bajado, para una maquina sin salida a internet
    # (y para poder probar todo esto sin red).
    if (-not $zip -and -not [string]::IsNullOrWhiteSpace($env:SESSION_PROMPTS_RELEASE_ZIP)) {
        $zip = $env:SESSION_PROMPTS_RELEASE_ZIP
    }

    if (-not $zip) {
        $tag = if ($FromRelease -eq 'latest') { $null } else { [string]$FromRelease }

        if (-not $tag) {
            # Override para probar, o para apuntar a un mirror interno. URL o ruta a un JSON.
            $fuente = $env:SESSION_PROMPTS_RELEASES_URL
            if ([string]::IsNullOrWhiteSpace($fuente)) { $fuente = "https://api.github.com/repos/$script:RepoGitHub/releases/latest" }

            try {
                if ($fuente -notmatch '^https?://') {
                    $json = Get-Content -LiteralPath $fuente -Raw -Encoding UTF8 | ConvertFrom-Json
                } else {
                    $json = Invoke-RestMethod -Uri $fuente -TimeoutSec 10 -Headers @{ 'User-Agent' = 'Install-SessionPrompts' }
                }
                $tag = [string]$json.tag_name
            } catch { }

            # Si no se pudo por HTTP, 'gh' usa la credencial del usuario (sirve si el repo
            # vuelve a ser privado, o para pasar el limite de la API anonima).
            #
            # SOLO cuando el origen es el de siempre: si alguien apunto a un mirror o a un
            # archivo, caer a GitHub instalaria un release DISTINTO del que pidio, y en
            # silencio.
            if (-not $tag -and $fuente -match '^https?://api\.github\.com') {
                $gh = Get-Command gh -ErrorAction SilentlyContinue
                if ($gh) {
                    $salida = & $gh.Source api "repos/$script:RepoGitHub/releases/latest" 2>$null
                    if ($LASTEXITCODE -eq 0 -and $salida) {
                        try { $tag = [string]((($salida | ForEach-Object { "$_" }) -join '') | ConvertFrom-Json).tag_name } catch { }
                    }
                }
            }

            if (-not $tag) {
                Write-Host "No pude averiguar cual es el ultimo release de $script:RepoGitHub." -ForegroundColor Red
                Write-Host "Puede que todavia no haya ninguno publicado, o que no haya conexion." -ForegroundColor DarkGray
                Write-Host "Salidas: -FromRelease v1.2.3 (un tag concreto)  |  -ReleaseZip <ruta> (un zip ya bajado)" -ForegroundColor DarkGray
                exit 1
            }
        }

        Write-Host "Bajando el release $tag de $script:RepoGitHub..." -ForegroundColor Cyan
        $zip = Join-Path ([System.IO.Path]::GetTempPath()) "run-session-prompts-$tag.zip"
        $bajado = $false
        try {
            Invoke-WebRequest -Uri "https://github.com/$script:RepoGitHub/archive/refs/tags/$tag.zip" -OutFile $zip -TimeoutSec 120 -Headers @{ 'User-Agent' = 'Install-SessionPrompts' }
            $bajado = Test-Path -LiteralPath $zip
        } catch { }

        if (-not $bajado) {
            $gh = Get-Command gh -ErrorAction SilentlyContinue
            if ($gh) {
                & $gh.Source release download $tag --repo $script:RepoGitHub --archive=zip --output $zip --clobber 2>$null | Out-Null
                $bajado = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $zip))
            }
        }

        if (-not $bajado) {
            Write-Host "No pude bajar el release $tag." -ForegroundColor Red
            Write-Host "Mira https://github.com/$script:RepoGitHub/releases" -ForegroundColor DarkGray
            exit 1
        }
    }

    if (-not (Test-Path -LiteralPath $zip)) {
        Write-Host "No existe el zip: $zip" -ForegroundColor Red
        exit 1
    }

    $carpeta = Join-Path ([System.IO.Path]::GetTempPath()) ("rsp-release-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Expand-Archive -LiteralPath $zip -DestinationPath $carpeta -Force

    $inst = @(Get-ChildItem -LiteralPath $carpeta -Filter 'Install-SessionPrompts.ps1' -Recurse -Depth 2 | Select-Object -First 1)
    if ($inst.Count -eq 0) {
        Write-Host "El zip no trae Install-SessionPrompts.ps1: $zip" -ForegroundColor Red
        exit 1
    }

    # Se reejecuta el instalador del release con los mismos argumentos MENOS los que trajeron
    # hasta aca (si no, se llamaria a si mismo para siempre).
    $paraPasar = @()
    foreach ($clave in $PSBoundParameters.Keys) {
        if ($clave -in @('FromRelease', 'ReleaseZip')) { continue }
        $valor = $PSBoundParameters[$clave]
        if ($valor -is [switch]) { if ($valor.IsPresent) { $paraPasar += "-$clave" } }
        else { $paraPasar += @("-$clave", [string]$valor) }
    }

    Write-Host "Instalando desde $($inst[0].DirectoryName)" -ForegroundColor DarkGray
    Write-Host ""
    $env:SESSION_PROMPTS_INSTALANDO = '1'
    try {
        & pwsh -NoProfile -File $inst[0].FullName @paraPasar
        $code = $LASTEXITCODE
    } finally {
        Remove-Item Env:\SESSION_PROMPTS_INSTALANDO -ErrorAction SilentlyContinue
    }
    exit $code
}

$origen = $PSScriptRoot
$runnerOrigen = Join-Path $origen 'Run-SessionPrompts.ps1'

# A esta altura el runner tiene que estar: si no estaba, arriba se bajo el release y este
# archivo ya no es el que sigue.
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

# Windows no distingue mayusculas, asi que Test-Path acierta con 'docs' aunque en disco diga
# 'Docs'. Para los mensajes -- y sobre todo para las rutas que van al prompt del CLAUDE.md del
# destino, que despues quedan escritas ahi -- queremos el nombre tal cual esta en disco.
function Get-RutaReal([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $path }
    $item = Get-Item -LiteralPath $path
    $padre = Split-Path -Parent $item.FullName
    if ([string]::IsNullOrEmpty($padre)) { return $item.FullName }

    $real = @(Get-ChildItem -LiteralPath $padre -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -ieq $item.Name } | Select-Object -First 1)
    if ($real.Count -gt 0) { return (Join-Path (Get-RutaReal $padre) $real[0].Name) }
    return $item.FullName
}

$SeriesRoot = Get-RutaReal $SeriesRoot

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

# La marca de la instalacion anterior, si la hay: dice que version quedo y con que hash, tanto
# del runner como del README.
$marcaPrevia = $null
if (Test-Path -LiteralPath $marcaPath) {
    try { $marcaPrevia = Get-Content -LiteralPath $marcaPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}

if (-not $esInstalacionNueva) {
    if ($marcaPrevia) {
        $marca = $marcaPrevia
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

# --- El README del andamiaje ----------------------------------------------
# Es la referencia que van a leer los agentes del repo destino: que es esto, como se corre, y con
# que criterio se elige el modelo y el effort de cada sesion. Se instala como el runner, pero con
# una diferencia: si el destino ya tiene un README.md que NO puso este instalador, no se toca.
# Los repos que venian usando una copia vieja tienen ahi su indice de series y su contexto.
$readmeOrigen = Join-Path $origen 'templates\README.md'
$readmeDestino = Join-Path $SeriesRoot 'README.md'

# El hash que va a la marca. SOLO se completa si lo instalamos nosotros: si el destino tiene un
# README propio y no lo pisamos, guardar su hash lo convertiria en "nuestro" y la proxima corrida
# lo pisaria sin avisar ni dejar copia.
$readmeHashParaMarca = if ($marcaPrevia) { $marcaPrevia.readmeHash } else { $null }

if (Test-Path -LiteralPath $readmeOrigen) {
    $ponerReadme = $true
    $motivoReadme = 'nuevo'

    if (Test-Path -LiteralPath $readmeDestino) {
        $hashActualReadme = Get-HashArchivo $readmeDestino
        if ($marcaPrevia -and $marcaPrevia.readmeHash -eq $hashActualReadme) {
            $motivoReadme = 'lo habia puesto este instalador, sin modificar'
        } elseif ($Force) {
            $motivoReadme = 'propio del repo, pisado por -Force'
            $bakReadme = "$readmeDestino.bak"
            if ($PSCmdlet.ShouldProcess($bakReadme, 'guardar copia del README actual')) {
                Copy-Item -LiteralPath $readmeDestino -Destination $bakReadme -Force
                Write-Host "Copia del README anterior: $bakReadme" -ForegroundColor DarkGray
            }
        } else {
            $ponerReadme = $false
            Write-Host "README.md: el destino ya tiene uno propio, no lo piso." -ForegroundColor Yellow
            Write-Host "  Los criterios de modelo y effort estan en $readmeOrigen" -ForegroundColor DarkGray
            Write-Host "  (-Force lo reemplaza, dejando un .bak al lado)." -ForegroundColor DarkGray
        }
    }

    if ($ponerReadme -and $PSCmdlet.ShouldProcess($readmeDestino, "instalar el README del andamiaje ($motivoReadme)")) {
        Copy-Item -LiteralPath $readmeOrigen -Destination $readmeDestino -Force
        Write-Host "README.md instalado ($motivoReadme)" -ForegroundColor Green
        $readmeHashParaMarca = Get-HashArchivo $readmeDestino
    }
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
        readmeHash  = $readmeHashParaMarca
        instaladoEl = (Get-Date).ToString('yyyy-MM-dd')
        origen      = $origen
    }
    Set-Content -LiteralPath $marcaPath -Value ($marca | ConvertTo-Json) -Encoding UTF8
}

# --- La sesion que hace descubrible el andamiaje --------------------------
# Instalar los archivos no alcanza: si el CLAUDE.md del repo no lo nombra, ningun agente lo va a
# encontrar, y si el repo venia de una copia vieja puede tener afirmaciones que hoy son falsas
# (que se corre con 'powershell', que el script escapa las comillas siempre, que el corte es de
# 30000 caracteres). Esta sesion arregla las dos cosas.
function Invoke-SesionClaudeMd {
    $promptPath = Join-Path $origen 'templates\prompt-instalacion-claude-md.md'
    if (-not (Test-Path -LiteralPath $promptPath)) {
        Write-Host "No encuentro $promptPath; salteo el paso del CLAUDE.md." -ForegroundColor Yellow
        return
    }

    # Mismas reglas de transporte que el runner (ahi esta el porque, medido, y los tests):
    # el modo se FIJA, y un 'claude' que sea un shim .cmd/.bat trunca los prompts multilinea.
    if ($null -ne (Get-Variable -Name PSNativeCommandArgumentPassing -ErrorAction SilentlyContinue)) {
        $PSNativeCommandArgumentPassing = 'Standard'
    }

    $resuelto = Get-Command $ClaudeCommand -ErrorAction SilentlyContinue
    if (-not $resuelto) {
        Write-Host "No encontre '$ClaudeCommand': salteo el paso del CLAUDE.md." -ForegroundColor Yellow
        Write-Host "  Podes hacerlo despues con: pwsh -File `"$PSCommandPath`" -Repo `"$repoRoot`"" -ForegroundColor DarkGray
        return
    }
    $exe = $resuelto.Source
    if ($resuelto.CommandType -ne 'Application') { $exe = $ClaudeCommand }
    elseif ($exe -match '\.(cmd|bat)$') {
        $hermano = [System.IO.Path]::ChangeExtension($exe, '.exe')
        $otro = @(Get-Command $ClaudeCommand -All -ErrorAction SilentlyContinue |
                  Where-Object { $_.CommandType -eq 'Application' -and $_.Source -notmatch '\.(cmd|bat)$' } |
                  Select-Object -First 1)
        if ($otro.Count -gt 0) { $exe = $otro[0].Source }
        elseif (Test-Path -LiteralPath $hermano) { $exe = $hermano }
        else {
            Write-Host "'$ClaudeCommand' es un shim $([IO.Path]::GetExtension($exe)) y no hay un .exe equivalente:" -ForegroundColor Yellow
            Write-Host "  por ese camino el prompt llegaria truncado. Salteo el paso del CLAUDE.md." -ForegroundColor Yellow
            return
        }
    }

    $texto = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    # El comentario de encabezado es para quien edite la plantilla, no para la sesion.
    $texto = [regex]::Replace($texto, '(?s)^\s*<!--.*?-->\s*', '')

    $texto = $texto.
        Replace('{{RUTA_SERIES}}', $SeriesRoot).
        Replace('{{RUTA_README}}', $readmeDestino).
        Replace('{{RUTA_RUNNER}}', $runnerDestino).
        Replace('{{RUTA_REPO}}',   $repoRoot).
        Replace('{{VERSION}}',     $versionOrigen)

    $modelos = @{ 'opus' = 'claude-opus-5'; 'sonnet' = 'claude-sonnet-5' }

    Write-Host ""
    Write-Host "Lanzo una sesion de Claude Code para dejar esto documentado en el CLAUDE.md de $repoRoot" -ForegroundColor Cyan
    Write-Host "  (modelo $Model, effort $Effort; -SkipClaudeMd para saltearlo)" -ForegroundColor DarkGray

    Push-Location -LiteralPath $repoRoot
    try {
        $global:LASTEXITCODE = 0
        # -p: una sola pasada, sin sesion interactiva. acceptEdits para que pueda escribir el
        # CLAUDE.md sin preguntar por cada edicion.
        #
        # El '$null |' cierra stdin: sin eso, 'claude -p' se queda tres segundos esperando datos
        # por ahi y avisa ("no stdin data received in 3s"). Todo lo que necesita ya va en el
        # argumento.
        $null | & $exe -p --model $modelos[$Model] --effort $Effort --permission-mode acceptEdits $texto
        $code = $LASTEXITCODE
    } finally { Pop-Location }

    Write-Host ""
    if ($code -ne 0) {
        Write-Host "La sesion salio con codigo $code. Los archivos quedaron instalados igual;" -ForegroundColor Yellow
        Write-Host "revisa a mano el CLAUDE.md de $repoRoot." -ForegroundColor Yellow
    } else {
        Write-Host "Listo. Los cambios del CLAUDE.md quedaron SIN COMMITEAR, para que los revises." -ForegroundColor Green
    }
}

if ($SkipClaudeMd) {
    Write-Host ""
    Write-Host "-SkipClaudeMd: no toco el CLAUDE.md del destino." -ForegroundColor DarkGray
} elseif ($WhatIfPreference) {
    Write-Host ""
    Write-Host "What if: lanzaria una sesion de Claude Code para documentar el andamiaje en el CLAUDE.md de $repoRoot." -ForegroundColor DarkGray
} else {
    Invoke-SesionClaudeMd
}

Write-Host ""
if ($esInstalacionNueva) {
    Write-Host "Listo. Para arrancar:" -ForegroundColor Cyan
    Write-Host "  1. Crea la carpeta de tu primera serie: $SeriesRoot\<mi-serie>\" -ForegroundColor DarkGray
    Write-Host "  2. Copia _plantillas\plantilla-session-prompt.md a <mi-serie>\01-....md y completala." -ForegroundColor DarkGray
    Write-Host "     (los criterios de modelo y effort estan en $readmeDestino)" -ForegroundColor DarkGray
    Write-Host "  3. pwsh -File `"$runnerDestino`"" -ForegroundColor DarkGray
} else {
    Write-Host "Actualizado a $versionOrigen. Revisa el CHANGELOG del runner por si cambio algo que uses." -ForegroundColor Cyan
}
