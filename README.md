# Run-SessionPrompts

Corre **series de prompts numerados** con Claude Code: un prompt por sesión, cada uno en contexto
limpio y con Remote Control, para que la serie entera avance sin que tengas que estar en la máquina.

## Un ejemplo

**Vos:** Vamos a planificar la continuación del circuito de invitaciones. El alcance es: desde que el
usuario la recibe y navega con el link (`/invitacion#t=<token>`) hasta que abre y configura su
cuenta. La idea es discutir y afinar acá, y después vos armás un plan de sesiones para la ejecución.

**Claude:** (...)

**Vos:** Cerrado, armá la serie verificando en el código nuestros supuestos.

**Claude:** Las nueve sesiones:

| # | Sesión | Modelo · effort |
| --- | --- | --- |
| 01 | El link, el token y la página de destino | `opus` · `xhigh` |
| 02 | El modelo: la invitación y la cuenta nueva | `opus` · `high` |
| (...) | (...) | (...) |
| 09 | Decisiones, invariantes y cierre | `opus` · `high` |

![Corrida de la serie 'invitaciones': el menú de series, el de modelo y el de effort, la
confirmación del effort que la sesión 01 pide por encima del tope, el plan de las nueve sesiones, y
el encadenado de la 01, la 02 y la 09 hasta el cierre.](docs/ejemplo-corrida.svg)

---

## Instalar

Parado en el repo donde lo quieras usar. No hace falta clonar nada: alcanza con bajar el
instalador, que después se trae el resto.

```bash
irm https://raw.githubusercontent.com/apanitsch/RunSessionPrompts/main/Install-SessionPrompts.ps1 -OutFile $env:TEMP\Install-SessionPrompts.ps1; pwsh -File $env:TEMP\Install-SessionPrompts.ps1
```

Eso deja el andamiaje en `<tu-repo>\docs\session-prompts\` y el repo listo para correr series.
Funciona igual desde cualquier subcarpeta del repo. Si querés instalarlo en **otro** repo sin
moverte, `-Repo C:\ruta\a\MiRepo`.

Después, desde el repo ya instalado:

```bash
pwsh -File .\docs\session-prompts\Run-SessionPrompts.ps1
```

> **Siempre con `pwsh`, nunca con `powershell`.** No es preferencia: bajo Windows PowerShell 5.1 los
> prompts llegan mutilados **en silencio**. El detalle, medido, está en
> [Cómo llega el prompt hasta Claude](#cómo-llega-el-prompt-hasta-claude).


### Qué hace ese comando

Como ese archivo quedó **solo** —sin el resto del producto al lado—, no tiene de dónde instalar: baja
el `.zip` del último release, lo descomprime y **se re-ejecuta desde adentro**. La instalación la
hace siempre la versión que se está instalando, así que el archivo que bajaste puede quedar viejo sin
que importe.

| Variante | Para qué |
| --- | --- |
| `-Repo C:\ruta\a\MiRepo` | instalar en otro repo sin moverte |
| `-FromRelease v1.2.3` | un tag concreto en vez del último |
| `-ReleaseZip <ruta>` | desde un `.zip` ya bajado, sin tocar la red |
| `-SkipClaudeMd` | no lanzar la sesión que actualiza el `CLAUDE.md` |

Deja en `MiRepo\docs\session-prompts\` (o `Docs\session-prompts\`, si el repo ya usa esa
convención):

| Qué | Para qué |
| --- | --- |
| `Run-SessionPrompts.ps1` | el runner |
| `README.md` | **la referencia para los agentes del repo**: qué es el andamiaje, cómo se corre, y los criterios para elegir modelo y effort de cada sesión |
| `_plantillas/` | los moldes de una serie y de un prompt |
| `series-estado.txt` | qué series están pendientes y en qué orden (sólo la primera vez) |
| `session-prompts.config.json` | lo que ese repo fija por defecto (sólo la primera vez) |
| `.session-prompts-version` | versión y hashes de lo instalado (del **contenido**, con los finales de línea normalizados: el checkout del repo destino puede cambiar CRLF por LF sin que nadie haya editado nada) |

Y después **lanza una sesión de Claude Code en el repo destino** para dejar el andamiaje
descubrible: que el `CLAUDE.md` de ese repo lo nombre, diga para qué sirve, cómo se corre y que la
referencia es ese `README.md`. La misma sesión **corrige las afirmaciones viejas** que el repo tenga
de versiones anteriores del script — `powershell` en vez de `pwsh`, "el script escapa siempre", "el
corte es 30000", un id de modelo viejo, "cada serie corre en un worktree". Los cambios quedan **sin
commitear**, para que los revises.

El prompt de esa sesión es [`templates/prompt-instalacion-claude-md.md`](templates/prompt-instalacion-claude-md.md)
y se puede editar. Con `-SkipClaudeMd` no se lanza; con `-Model` y `-Effort` se elige con qué corre
(por defecto `opus` y `high`).

Si tenés el clon del producto a mano, el instalador de ahí instala **desde el clon**, sin bajar nada
—porque tiene el producto al lado—. Con `-FromRelease latest` se lo puede forzar a usar el release
igual:

```bash
pwsh -File C:\ruta\a\RunSessionPrompts\Install-SessionPrompts.ps1 -Repo C:\ruta\a\MiRepo
```

### Actualizar

Desde el repo donde ya está instalado, sin acordarse de dónde vive el producto:

```bash
pwsh -File .\docs\session-prompts\Run-SessionPrompts.ps1 -Update
```

Y no hace falta acordarse ni de eso: **al arrancar, una vez por día, el runner chequea si hay una
versión nueva** y la ofrece antes de cualquier menú. Si no hay conexión, o si todavía no hay
releases, la corrida sigue igual — el chequeo tiene cinco segundos de paciencia y nunca corta nada.
Se apaga con `-SkipUpdateCheck`, o para siempre con `"checkForUpdates": false` en la configuración
del repo.

El instalador no pisa nada que no haya puesto él:

| Situación en el destino | Qué hace |
| --- | --- |
| El runner es idéntico al que instaló | Lo actualiza sin preguntar |
| El runner está **modificado a mano** | Avisa, muestra cómo diferenciarlo, y **no toca nada** (sale con código 2) |
| Hay un runner **sin marca de versión** (copiado a mano, de antes del instalador) | Igual: avisa y no toca nada. Desde el runner: `-Update -Force` |
| Las series, el `series-estado.txt`, el `session-prompts.config.json` | **Nunca** se pisan |
| Un `README.md` propio del repo (por ejemplo, con su índice de series) | Avisa y **no lo toca**; con `-Force` lo reemplaza dejando un `.bak` |

Con `-Force` pisa igual, dejando un `.bak` al lado. Con `-WhatIf` dice qué haría y no toca nada.

### Sin instalar

El runner también funciona desde donde esté: si la carpeta donde vive no tiene series adentro, busca
`docs/session-prompts` (o `Docs/`, o con guión bajo) en el repo git donde estés parado. O se lo decís
con `-SeriesRoot`.

---

## Qué hace

Una **serie** es una carpeta con prompts numerados:

```
docs/session-prompts/
├── Run-SessionPrompts.ps1
├── series-estado.txt              ← qué series están pendientes y en qué orden
├── _plantillas/                   ← moldes (las carpetas con "_" no son series)
└── mi-serie/
    ├── README.md                  ← contexto compartido de la serie (no se ejecuta)
    ├── ESTADO.md                  ← bitácora viva (no se ejecuta)
    ├── 01-primera-cosa.md         ← esto sí se ejecuta
    ├── 02-segunda-cosa.md
    └── 03-tercera-cosa.md
```

El runner recorre los `.md` **que empiezan con número**, en orden numérico (`10-` va después de
`02-`, no después de `01-`), y por cada uno lanza:

```
claude --model <modelo> --effort <effort> --permission-mode acceptEdits --rc <serie/NN-nombre> --name <serie/NN-nombre> "<el prompt entero>"
```

Cada sesión es interactiva y con **Remote Control**: aparece en el celular y en Claude Code Desktop,
te puede preguntar y le respondés desde ahí. **No se cierra sola**: cuando la cerrás con `/exit`, el
script lanza la siguiente. Si una sesión sale con error, la corrida se corta ahí.

La excepción es [`-Unattended`](#-unattended-la-serie-corre-sola), donde no hay Remote Control ni `/exit`
y la serie avanza sola. Es opt-in: sin ese parámetro, lo de arriba es todo lo que pasa.

**Todo lo que hay que decidir se pregunta al principio**, antes de la primera sesión. Es la única
promesa que el script no puede romper: contestás una vez y te vas.

---

## Uso

> **Siempre con `pwsh`, nunca con `powershell`.** Ver [Cómo llega el prompt hasta Claude](#cómo-llega-el-prompt-hasta-claude).

```bash
pwsh -File .\Run-SessionPrompts.ps1
```

Sin parámetros muestra menús —serie, desde qué número, modelo, effort— y arranca. Todo eso se puede
fijar por parámetro para saltear los menús:

```bash
pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -StartFrom 1 -Model sonnet -Effort max
```

```bash
pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Worktree -BaseBranch main
```

```bash
pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -DryRun
```

### Parámetros

| Parámetro | Qué hace |
| --- | --- |
| `-PromptsPath` | La serie. Autocompleta con Tab. Sin él, menú de series. |
| `-SeriesRoot` | Dónde viven las series. Default: la carpeta del script, o la del repo donde estés. |
| `-StartFrom` | Número desde el cual empezar (`3` arranca en `03-…`). Es el **número**, no el nombre. |
| `-Model` | `opus` (default) o `sonnet`. Es el **tope**: cada prompt puede pedir menos, y para pedir más el script confirma. |
| `-Effort` | `low`, `medium`, `high` (default), `xhigh`, `max`. También es un **tope**, con la misma regla. |
| `-PermissionMode` | El modo de permisos de toda la corrida: `acceptEdits` (default), `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`. Se pasa tal cual a `--permission-mode`. |
| `-Auto` | Atajo de `-PermissionMode auto`, el modo **Auto** de Claude Code Desktop. Ojo: `auto` **no** es `acceptEdits`, son dos modos distintos del CLI. |
| `-FullAuto` | `--dangerously-skip-permissions` en vez de `--permission-mode`. Junto con `-Auto` o `-PermissionMode` es un error, no una precedencia. |
| `-Unattended` | La serie corre **sola**: sin Remote Control, sin `/exit`, y cada sesión dice si la serie sigue. Opt-in y se confirma a mano. Ver [`-Unattended`](#-unattended-la-serie-corre-sola). |
| `-MaxBudgetUsd` | Techo de gasto por sesión (`--max-budget-usd`). Sólo con `-Unattended`. |
| `-ResumeWhen5HoursLimit` | Si una sesión se corta por el límite de uso de 5 horas, espera a que venza y la reanuda. Una vez por sesión. Opt-in y sólo con `-Unattended`. Ver [`-ResumeWhen5HoursLimit`](#-resumewhen5hourslimit-cuando-le-pega-al-límite-de-uso-de-5-horas). |
| `-Todas` | El menú incluye también las series ya terminadas. |
| `-Worktree` | La serie corre aislada en su propio git worktree. |
| `-BaseBranch`, `-BranchPrefix`, `-WorktreeRoot` | Detalles del worktree. |
| `-ClaudeCommand` | Otro ejecutable de Claude Code. |
| `-DryRun` | Imprime el plan y la línea de comandos de cada sesión, y **no lanza nada**. |
| `-Version` | La versión del runner. |

---

## Las piezas

### `series-estado.txt` — qué series muestra el menú

Vive al lado del runner. El menú muestra **sólo las pendientes**, **en el orden de ejecución
propuesta**:

```
pendiente 1 la-que-va-primero
pendiente 2 la-que-sigue
terminada - una-que-ya-cerro   # cerrada 2026-01-31
```

Una serie que no figura se considera pendiente y va al final: una carpeta nueva aparece en el menú
sin que haya que acordarse de anotarla. **El script lo escribe solo**: cuando una corrida termina
bien y llegó hasta el último prompt de la serie, la marca `terminada` con la fecha. Es exclusivo del
runner: nada más lo lee, y si lo borrás el script sigue andando (vuelve a mostrar todas, alfabético).

La línea se alinea con la columna de comentario que ya usa el archivo, y **si ya decía exactamente
eso, el archivo no se toca**: la última sesión de una serie suele cerrarla ella misma y comitear, y
este paso del runner corre después — reescribir ahí dejaría una diferencia que es sólo espaciado.

Cuando el runner **sí** cambia algo, ese cambio **queda sin comitear**: se escribe después del
último commit de la serie, así que no hay nada que se lo lleve puesto. El runner **no commitea en el
repo destino** — el commit lo hace quien lo mantiene —, pero imprime el comando, acotado a ese único
archivo:

```
git -C "<carpeta de series>" commit -m "docs(series): cerrar <mi-serie>" -- series-estado.txt
```

### Modelo y effort sugeridos por sesión

Un prompt declara con qué modelo y con cuánto esfuerzo se pensó, en dos marcas del `.md`:

```markdown
<!-- modelo-sugerido: sonnet -->
<!-- effort-sugerido: xhigh -->
```

El modelo y el effort de la corrida (`opus` y `high` por defecto) son el **tope**, y para los dos
vale la misma regla:

- **la sesión pide menos que el tope** → se usa lo que pide, sin preguntar. Bajar es barato, y la
  sesión sabe lo que necesita: si un prompt dice que con Sonnet y `low` alcanza, no hay motivo para
  gastar Opus en `high`.
- **la sesión pide más que el tope** → el script **para y pregunta**, antes de arrancar. Correr una
  sesión con menos de lo que pide no es una decisión que se tome sola.
- **igual, o sin marca** → el tope, sin ruido.

Con los defaults, entonces: cualquier sesión puede abaratarse sola, y ninguna puede pedir Opus con
la corrida en Sonnet, ni `xhigh` o `max` con la corrida en `high`, sin que lo confirmes. Para
levantar el tope de toda la corrida, `-Model` y `-Effort`.

Los valores son los mismos que aceptan los parámetros: `opus` y `sonnet` para el modelo; `low`,
`medium`, `high`, `xhigh` y `max` para el effort. **Una marca con un valor que no es ninguno de
esos corta con un error** — una marca mal escrita que se ignora en silencio es exactamente lo que
este script no hace.

Regla práctica al escribir prompts: la sesión que **escribe** con el criterio ya resuelto va con
`sonnet` y poco effort; la que **juzga** va con `opus`, y con `xhigh` o `max` si además el problema
es difícil.

Todo esto se resuelve **antes de la primera sesión**, y el plan que se imprime muestra el modelo y
el effort de cada una, con el porqué:

```
  01-arranque.md                     Opus 5   effort high
  02-tramite.md                      Sonnet 5 effort low     <- modelo sugerido (baja desde Opus 5); effort sugerido (baja desde high)
  03-dificil.md                      Opus 5   effort max     <- effort sugerido (SUBE, confirmado)
```

### `-Unattended`: la serie corre sola

Con `-Unattended` la serie corre **sin supervisión**. Cada sesión se lanza con `claude -p` en vez de
una sesión interactiva:

```
claude --model <modelo> --effort <effort> --permission-mode auto -p --output-format stream-json --verbose        --json-schema <esquema del resultado> --append-system-prompt <el contrato>        --session-id <guid> --name <serie/NN-nombre> "<el prompt entero>"
```

**Es opt-in y se confirma a mano**: el runner imprime lo que se pierde y hay que escribir `si` para
arrancar. Sin el parámetro no cambia absolutamente nada del comportamiento de siempre.

#### Cómo decide si sigue

El runner le pide a cada sesión un resultado estructurado, por `--append-system-prompt` y no por
ningún archivo del repo destino: así llega **siempre**, sin depender de que el agente lea algo ni de
que el autor del prompt se acuerde.

```json
{ "result": "ok" | "stop", "reason": "una o dos frases" }
```

**La serie sigue sólo si se cumple todo**: exit code 0, resultado presente y parseable, y `result`
en `ok`. Todo lo demás frena, **incluida la ausencia de resultado**. Esa asimetría es deliberada:
un agente que dice "no pude" casi nunca se equivoca, pero un `ok` vale poco —el modo de falla más
común es la sesión que entendió mal y está convencida de que hizo bien—. Así que el JSON es un
**freno que la sesión puede tirar**, no un certificado de calidad. Y si la falta de señal se leyera
como "seguí", una sesión que se colgó le arrastraría el error a todas las que vienen.

Los dos diagnósticos se imprimen distinto a propósito: *la sesión pidió frenar* es el mecanismo
funcionando; *la sesión no dejó resultado* es una sesión que se colgó, y no se arreglan igual. El
`reason` se imprime siempre, también cuando dice `ok`.

El mismo contrato le dice a la sesión, además, que **su turno es toda la sesión**: cuando devuelve
el resultado se cierra, y lo que haya dejado corriendo en segundo plano se muere con ella. Sin esa
línea el modo tiene un agujero que se vio en una corrida real: la sesión mandó una suite de catorce
minutos al fondo, programó un despertador para volver después, y cerró el turno con `ok` y un
`reason` que decía *"en progreso, no listo para cerrar todavía"*. La serie siguió sobre un working
tree a medias. El runner **no** puede detectarlo —el `reason` se imprime, nunca se parsea—, así que
lo único que se puede hacer es que la sesión sepa dónde está.

#### Las dos marcas del prompt

| Marca | Obligatoria | Qué hace |
| --- | --- | --- |
| `<!-- runner-requerido: 2.0 -->` | **sí**, en `-Unattended` | Dice que el prompt se escribió conociendo el contrato. Sin ella el runner no corre la serie sin supervisión. Un repo con las plantillas de una versión anterior no tiene documentado el contrato, así que sus prompts no pueden cumplirlo aunque quieran. |
| `<!-- automatico: no \| motivo -->` | no | Esta sesión **necesita** un humano. La serie corre hasta la anterior y frena ahí, limpio, diciendo con qué `-StartFrom` seguir. |

Las dos se validan siempre —una marca mal escrita corta, con o sin `-Unattended`— y se exigen sólo en
este modo. El `automatico: no` se detecta **al arrancar**: antes de la primera sesión ya sabés dónde
va a parar la corrida.

#### Qué se pierde y qué no

- **Se pierde la ventana en vivo.** Remote Control es interactivo por definición, así que no hay
  sesión en el celular mientras corre. Pasás de "miro mientras" a "miro después".
- **No se pierden las sesiones.** Quedan guardadas igual que las interactivas —mismo lugar, mismo
  nombre— y el runner imprime el `claude --resume <id>` de cada una.
- **La consola muestra el stream de eventos**, no el dibujo de la TUI: ese lo hace la TUI, que en
  `-p` no existe. A cambio queda un log parejo entre sesiones, que el modo interactivo no deja.
- **El modo de permisos no se elige**: es `auto`, y pasar `-PermissionMode` o `-FullAuto` junto con
  `-Unattended` es un error. Un clasificador ocupa el lugar que ocupabas vos. Lo que no aprueba queda
  denegado, la sesión no puede hacer el trabajo, y lo reporta — que es el mismo freno de arriba.
- **No hay techo de gasto** salvo `-MaxBudgetUsd`. Sin nadie mirando, una sesión trabada puede
  correr sin límite.

#### `-ResumeWhen5HoursLimit`: cuando le pega al límite de uso de 5 horas

Una serie larga que corre de noche se puede quedar sin cuota a la mitad. Sin este parámetro eso
frena la serie como cualquier otra falla. Con él, el runner **espera a que el límite venza y reanuda
esa misma sesión** donde quedó.

**Una sola espera por sesión.** Si la sesión reanudada vuelve a pegarle al límite, la serie frena.
La segunda vez ya no es mala suerte con el reloj: es una sesión que necesita más cuota de la que
hay, y esperar de nuevo la deja dando vueltas toda la noche.

**Cómo se da cuenta de que fue *ese* límite.** El CLI emite un evento propio en el stream —
`rate_limit_event` — y ahí está lo único que dice qué límite fue y cuándo vence:

```json
{ "type": "rate_limit_event", "rate_limit_info": {
    "status": "rejected", "rateLimitType": "five_hour", "resetsAt": 1788233335 } }
```

Se exigen las dos cosas, `rejected` y `five_hour`. No alcanza con el exit code, y tampoco con el
evento de cierre: ahí el `terminal_reason` dice `api_error` y el `api_error_status` dice `429`, que
es lo mismo que dicen el límite semanal, el de Opus y una sobrecarga del servidor — y ninguno de
esos se destraba esperando. Los demás límites **también se avisan** por consola, con su nombre y su
vencimiento; lo que no hacen es disparar la espera.

**Se despierta en `resetsAt` más cinco minutos.** El corte del lado del servidor no es exacto al
segundo: despertarse justo en el vencimiento es pedirle al CLI que vuelva a chocar por unos
segundos y gastar la única espera de esa sesión. Y la espera se mide contra el reloj absoluto en
cada vuelta, no con un `Start-Sleep` largo, para que una máquina que suspende en el medio no se
despierte antes de tiempo.

**Un vencimiento absurdo no deja la serie dormida.** Si el evento dijera que un límite de 5 horas
vence dentro de veinte, algo no es lo que creemos: el runner corta diciéndolo, en vez de esperar.

**Qué recibe la sesión reanudada.** Un prompt corto de continuación — *"Le pegaste al límite de 5
horas. Continuá."* — y **el mismo contrato de siempre**: el `--json-schema` y el
`--append-system-prompt` viajan otra vez. Sin eso la sesión reanudada no dejaría resultado
estructurado y el semáforo la leería como una sesión colgada, que es la misma pared contra la que
se acababa de chocar.

**Lo que esto cuesta, dicho antes de arrancar.** Reanudar re-manda la conversación entera, así que
lo primero que hace la sesión reanudada es gastar parte del límite recién renovado. Y
`-MaxBudgetUsd` es un techo **por invocación**: una sesión que espera y reanuda puede gastar hasta
el doble de ese techo. Las dos cosas aparecen en la confirmación de `-Unattended`.

Nada de esto es deducción: está [medido contra el CLI real](#el-arnés-del-límite-de-5-horas), y la
medición se rehace sin gastar cuota.

### Aislamiento por worktree (`-Worktree`)

La serie obtiene un git worktree propio (`<repo>\..\worktrees\<serie>`) con una rama nueva
`sesiones/<serie>` partiendo de `-BaseBranch` (default: la rama actual). Todas las sesiones corren
paradas ahí y comparten ese árbol, así que:

- el checkout principal no se toca —útil cuando algo lo está sirviendo (IIS, un watcher);
- un arnés de testing que se aísle por ruta de disco (base y puerto propios) se auto-aísla;
- las sesiones se encadenan: la 02 construye sobre lo que commiteó la 01.

El worktree **no se borra** al terminar: queda con sus commits, y el script imprime cómo mergearlo y
cómo limpiarlo. Al reanudar la serie con `-StartFrom`, reutiliza el que ya existe. Se niega a crear
el worktree adentro del checkout principal.

### `session-prompts.config.json`

Opcional, al lado del runner. Lo que cambia de repo a repo —la rama base, si las series corren
aisladas, el modelo de siempre— se escribe una vez y no se vuelve a tipear. Precedencia:
**parámetro explícito > configuración > default del script**. El archivo de ejemplo
([`templates/session-prompts.config.json`](templates/session-prompts.config.json)) documenta cada
clave.

El runner lo **valida entero al arrancar**, contra la lista de claves que realmente mira
(`model`, `effort`, `fullAuto`, `permissionMode`, `worktree`, `baseBranch`, `branchPrefix`, `worktreeRoot`,
`checkForUpdates`, `claudeCommand`, `maxPromptChars`) y contra el tipo de cada una. Una clave
desconocida corta con un error que la nombra y sugiere la parecida (`'modelo'. Quisiste decir
'model'?`); un valor del tipo equivocado dice qué se esperaba (`true o false, sin comillas`). Salen
todos los problemas juntos, no de a uno por corrida. Las claves que empiezan con `_` son comentarios
y se ignoran: es lo que le permite al archivo de ejemplo documentarse a sí mismo.

Un `null` es "no la fijo": vale para cualquier clave y es como viene la plantilla.

### Plantillas

[`templates/_plantillas/`](templates/_plantillas) trae los moldes de una serie: el `README.md` de la
serie (contexto compartido), el `ESTADO.md` (bitácora viva) y el prompt de una sesión. Las carpetas
que empiezan con `_` nunca se toman por series, así que las plantillas y una serie de ejemplo pueden
convivir con las de verdad sin ensuciar el menú.

---

## Cómo llega el prompt hasta Claude

El prompt entero viaja como **un argumento**. Casi todos citan algo entre comillas, muchos traen
JSON o XML con sus escapes, y **todos son multilínea**. Que eso cruce intacto la línea de comandos
de Windows es lo único que garantiza que la sesión lea lo que escribiste.

Hay tres cosas que lo pueden romper, y el runner se ocupa de las tres.

### 1. Windows PowerShell 5.1 no puede correr esto

Medido: bajo 5.1 un argumento con comillas dobles llega **mutilado** — sin escapar se parte en la
primera comilla; escapando a mano llega entero pero sin las comillas. Bajo 7.x llega intacto. Como
degrada **en silencio**, el script tiene `#Requires -Version 7.0` y falla con un error claro.

Por eso: **`pwsh -File …`, nunca `powershell -File …`**.

### 2. El modo de pasaje de argumentos se fija, no se adivina

`$PSNativeCommandArgumentPassing` decide si PowerShell escapa los argumentos nativos. Un perfil, o
quien te llame, lo puede haber dejado en `Legacy` — y ahí el prompt se parte igual que en 5.1.

Hasta la 1.1.1 el runner detectaba eso y lo compensaba escapando a mano. Ahora hace algo más
simple y más seguro: **lo fija en `Standard` para sí mismo**. Medido: con el llamador en `Legacy`,
fijarlo alcanza para que todo llegue intacto, incluso el backslash final que el escapado manual
duplicaba. El escapado a mano quedó sólo para PowerShell 7.0–7.2, donde esa variable todavía no
existe.

### 3. Un `claude` que sea un shim `.cmd` no sirve — y el runner no arranca

Si Claude Code se instaló por npm, en el `PATH` queda un `claude.cmd`. Pasar el prompt por ahí lo
rompe, y de la peor manera posible. Medido con 21 payloads hostiles:

- un prompt **multilínea llega truncado en su primera línea**, sin error ni aviso — y todos los
  prompts de sesión son multilínea, así que eso solo no deja nada en pie;
- `%PATH%` y compañía los **expande cmd**: al prompt le entra el PATH de la máquina;
- un `<` o un `>` (o sea, cualquier prompt con XML o HTML) hace **fallar** la invocación;
- un `\` final llega duplicado.

No hay escapado que arregle eso: son reglas de `cmd.exe`, no de `CommandLineToArgvW`. Así que el
runner primero busca el `.exe` equivalente (mismo nombre en el `PATH`, o al lado del shim) y lo
usa; si no hay ninguno, **no arranca** y explica qué hacer. Es la misma regla que el corte por
tamaño: mejor una corrida que no empieza que una serie entera leyendo la primera línea de cada
prompt.

### 4. El corte por tamaño mide la línea, no el prompt

Windows corta en **32767 caracteres toda la línea de comandos**: la ruta del ejecutable, los flags,
el nombre de la sesión y el prompt **ya escapado**. Por eso el runner no corta por el largo del
prompt, sino por lo que la línea va a ocupar de verdad.

Medido: con texto plano entra un prompt de 32500 caracteres y falla uno de 32600; con un texto que
trae una comilla cada diez caracteres, el mismo prompt ocupa mucho más y ya falla en 30000, porque
cada `"` viaja como `\"`. Un corte fijo se equivoca **en las dos direcciones** — y el que este
script traía (30000 sobre el prompt crudo) se equivocaba en las dos: rechazaba un prompt real de
31697 caracteres que entra perfectamente, y habría aceptado uno de 25000 lleno de comillas que no
entra.

Cuando no entra, la falla del sistema es ruidosa (`The filename or extension is too long`), no un
truncado en silencio. El runner corta antes igual, porque ese mensaje no dice qué prompt fue ni qué
hacer.

La clave `maxPromptChars` del `session-prompts.config.json` sigue existiendo, pero ahora es un
**tope propio del repo** para quien quiera mantener sus prompts cortos por política. Sin ella manda
el techo del sistema.

### Qué de todo esto está testeado

Todo se mide contra un `.exe` nativo escrito para eso, que anota cada argumento tal como se lo
entregó el sistema operativo — ya parseado con `CommandLineToArgvW`, igual que `claude.exe`. Los
casos de la suite:

| Caso | Qué verifica |
| --- | --- |
| **21 payloads hostiles** | comillas dobles pares (`""`) e impares, comillas simples, backticks (`` ` ``, ``` `` ```), acentos agudos (`´´`) y comillas tipográficas, `<caso>\'</caso>`, XML con atributos y `CDATA`, HTML con entidades, JSON escapado (`{ "p": "v \n \" \' v" }`), JSON con rutas `C:\\temp\\`, un bloque ` ```json ` multilínea, todo combinado, backslash final, metacaracteres de shell (`& \| > < ^ ( ) ;`), `%PATH%`/`%1`/`!DELAYED!`, multilínea, unicode y emoji, y un prompt que empieza con `--dangerously-skip-permissions` |
| **Nombres de serie y de archivo** | también viajan (a `--rc` y `--name`): una serie llamada `rara & ^ %PATH% 'sim' ``bt`` (p) #h $p ~t !b …` llega entera |
| **`.exe` nativo** | el prompt cruza intacto y **ningún pedazo** queda suelto como otro argumento |
| **Shim `.cmd` con `.exe` al lado** | el runner esquiva el shim y usa el ejecutable |
| **Shim `.cmd` sin `.exe`** | el runner **no arranca**, y dice por qué |
| **Modo `Legacy` heredado** | el runner fija el modo y el prompt cruza intacto igual |
| **Windows PowerShell 5.1** | no puede correr el runner: falla por el `#Requires` |
| **Tamaño** | un prompt grande que entra se corre; uno que no entra corta con los números; y un prompt de 22000 caracteres **lleno de comillas** se rechaza, porque escapado ocupa el doble |

Verificado por mutación — un test que no puede fallar no prueba nada:

| Si se rompe el runner así… | …se ponen en rojo |
| --- | --- |
| escapar siempre | el `.exe` nativo, los 21 payloads, el shim y `Legacy` |
| cortar por el largo crudo del prompt | el prompt grande que sí entra, y el lleno de comillas |
| no escapar nunca | los casos que dependen del escapado en 7.0–7.2 |
| no fijar el modo | el caso de `Legacy` |
| aceptar el shim `.cmd` tal cual | los dos casos de shim |
| no poner la consola en UTF-8 en `-Unattended` | el caso del `reason` que se **lee** con acentos |
| ponerla en UTF-8 **después** de la primera línea impresa | el caso del `reason` que se **escribe** — el host se queda con el encoding que tenía al escribir por primera vez |
| ponerla en UTF-8 **sólo** con `-Unattended` | el caso de la corrida normal, donde lo que escribe la sesión pasa derecho a la pantalla |
| que la ponga el runner pero no el instalador | el caso de la sesión del `CLAUDE.md` |
| que el aviso de "viniendo de una versión vieja" salga siempre, o no salga nunca | el caso del aviso — sale sólo con la consola en ANSI, la salida redirigida y una versión previa anterior a la 2.0.1 |
| leer la ausencia de resultado como `ok` | los dos casos de sesión que no deja resultado |
| sacarle al contrato el párrafo del "no hay un después" | el caso que lo busca en el `--append-system-prompt` que recibe la sesión |
| no exigir la marca `runner-requerido` | el caso de la serie que no la declara |
| ignorar `automatico: no` | el caso de la corrida que frena antes de esa sesión |
| sacarle el `\r?` al patrón de las marcas | el caso de los prompts en CRLF — las cuatro marcas dejan de aplicar |
| no validar que los `.md` estén en UTF-8 | el caso del prompt guardado en ANSI |
| no mirar los bytes NUL | el caso del prompt en UTF-16 sin BOM |
| despertarse justo en el vencimiento, sin el margen | el caso de la espera, que mide que haya esperado el margen |
| reanudar sin el contrato (`--json-schema` y `--append-system-prompt`) | el caso del resume, que los busca en la invocación |
| esperar por cualquier límite y no sólo por el de 5 horas | el caso del límite semanal |
| permitir más de una espera por sesión | el caso de la sesión que vuelve a chocar después de reanudar |

Los casos de `-Unattended` corren contra el mismo doble, que además emite el stream NDJSON como lo
emite `claude -p`. Los del `reason` con acentos usan el `.exe` nativo y arrancan el proceso hijo con
la consola en Windows-1252: si el runner no la pone en UTF-8, los bytes del `.exe` se leen como
mojibake — **y el JSON parsea igual**, que es lo que hace peligrosa a esa falla.

Son **dos** casos y no uno porque el canal tiene dos lados que se rompen distinto, y **un solo caso
dejaba pasar una de las dos mutaciones**: si el runner lee mal y escribe mal con la *misma*
codificación equivocada, los bytes que salen son iguales a los que entraron y el error se cancela.
El caso de lectura desvía la escritura a un archivo en UTF-8 explícito; el de escritura hace que el
`.exe` emita la línea en ASCII puro, con los acentos como escapes del JSON, para que lo único
medido sea con qué codificación imprime el runner.

Los otros dos casos miran el mismo canal cuando **nadie lo parsea** —una corrida normal, y el
informe de la sesión del `CLAUDE.md`—, donde lo que se rompe es cómo se ve. Son dos, uno por
ejecutable, porque cada proceso tiene que arreglarse solo: **medido**, con el runner en la ANSI y
el instalador en UTF-8 la salida sale rota lo mismo, porque manda el proceso pegado a la consola.

Esos dos **no** se miden por el pipe del proceso hijo, y no es un detalle: por ese pipe un hijo
arreglado se ve roto y uno roto se ve bien, según cómo esté la consola donde corre la suite. Se
miden con un archivo que escribe el propio hijo, en UTF-8 explícito.

El `.exe` de prueba lo compila **Windows PowerShell 5.1**, que viene con Windows: PowerShell 7 no
puede generar ejecutables de consola. Es el único uso de 5.1 en el proyecto, y es para construir el
doble, nunca para correr el runner. En una máquina sin 5.1 esos casos se **omiten con el motivo a
la vista**, no en silencio.

---

## De dónde salió

Este repo es el **producto**: la versión con control de cambios de un script que hasta agosto de 2026
vivía copiado y pegado —y divergiendo— en `docs/session-prompts/` de ocho repositorios distintos. Lo
que hay acá es la **suma** de todas esas versiones, más lo que hace falta para instalarlo y
actualizarlo en cualquier repo. Qué aportó cada una, y qué se descartó, está en
[`docs/analisis-de-versiones.md`](docs/analisis-de-versiones.md).

---

## Desarrollo

### Tests

```bash
pwsh -File .\tests\Run-Tests.ps1
```

Sin dependencias: PowerShell 7 y git. Cada caso arma un repo git de juguete en una carpeta temporal y
corre el runner de verdad contra un **doble de `claude`** que anota lo que recibió (argumentos y
directorio de trabajo). Verifica orden, nombres de sesión, modelo por sesión, texto del prompt
intacto, `cwd`, exit codes, worktree, configuración y menús. Con `-KeepTemp` no borra los temporales.

Todo cambio al runner entra con su caso.

### El arnés del límite de 5 horas

La suite corre contra un doble de `claude`, que es lo que la hace rápida y repetible — pero un doble
sólo puede afirmar lo que ya sabemos. Cómo se comporta **el CLI de verdad** cuando le pega al límite
de uso de 5 horas no está en la documentación oficial, y esperar a quedarse sin cuota para
averiguarlo no es un método.

Para eso hay un arnés propio, en `tools/`:

```bash
pwsh -File .\tools\Measure-Limite5Horas.ps1
```

Levanta una **API falsa de Anthropic** en loopback ([`tools/Start-FakeAnthropicApi.ps1`](tools/Start-FakeAnthropicApi.ps1)),
apunta el CLI ahí con `ANTHROPIC_BASE_URL` y corre la secuencia completa: una sesión que choca contra
el límite, y después el resume de esa misma sesión con el límite ya vencido. **No gasta cuota**:
ninguna request sale de la máquina. Devuelve exit code distinto de cero si alguna de las respuestas
medidas dejó de ser la que era, así que también sirve de alarma cuando sale una versión nueva del
CLI.

Lo que quedó medido contra `claude` 2.1.229:

| Pregunta | Respuesta medida |
| --- | --- |
| ¿El evento de límite llega antes que el de cierre? | Sí, y por lejos: llega **incluso antes del `init`** |
| ¿Se distingue el límite de 5 horas de los demás? | Sí: `rateLimitType: "five_hour"` con `status: "rejected"` |
| ¿Dice cuándo vence? | Sí: `resetsAt`, epoch en segundos |
| ¿Cuánto reintenta solo el CLI? | **Nada.** Un intento, corta en segundos, exit code 1 |
| ¿Qué dice el evento de cierre? | `terminal_reason: "api_error"`, `api_error_status: 429` — no distingue qué límite fue |
| ¿La sesión cortada deja resultado estructurado? | No |
| ¿Se puede reanudar? | Sí, con su mismo id |
| ¿`--json-schema` y `--append-system-prompt` siguen aplicando en el `--resume`? | Sí, si se los vuelve a pasar |
| ¿Qué se re-manda al reanudar? | La conversación entera |

El servidor sirve para más que esto: tiene escenarios de límite semanal, sobrecarga y error del
servidor, el escenario se cambia **en caliente** reescribiendo su archivo de estado, y anota el
cuerpo entero de cada request — que es lo que permite verificar *qué* manda el CLI en vez de
suponerlo. No usa `System.Net.HttpListener` a propósito: sus prefijos piden una reserva de URL o
privilegios de administrador, y eso volvería al arnés algo que no se puede correr en cualquier
máquina.

De las credenciales no anota nada: de la cabecera `Authorization` guarda sólo si vino y con qué
esquema, nunca el valor.

### La captura del ejemplo

La consola del [ejemplo](#un-ejemplo) va como imagen porque GitHub no renderiza colores en un bloque
de código, y los colores son parte de lo que se está mostrando. La arma
[`docs/gen-ejemplo-corrida.ps1`](docs/gen-ejemplo-corrida.ps1) desde una lista de líneas con su
color: nada verifica que ese texto siga coincidiendo con lo que el runner imprime, así que si cambiás
una cadena del script, actualizá la lista y volvé a correrlo.

```bash
pwsh -File .\docs\gen-ejemplo-corrida.ps1
```

### Versionado y releases

[Semver](https://semver.org/lang/es/). La versión vive en **un solo lugar**: `$script:RunnerVersion`,
adentro del runner. El instalador la lee de ahí, y el `CHANGELOG.md` la registra.

Qué es cada cosa, para este script:

- **major** — algo que ya andaba deja de andar igual: un parámetro que cambia de significado, un
  default distinto, un formato de archivo que las instalaciones viejas no entienden.
- **minor** — una capacidad nueva que no rompe nada (un parámetro nuevo, una clave de configuración).
- **patch** — un bug, un mensaje, una aclaración.

Para publicar:

1. Los tests en verde.
2. `$script:RunnerVersion` al número nuevo.
3. `CHANGELOG.md`: la sección `[No publicado]` pasa a ser la versión, con fecha.
4. Commit y tag: `git tag -a v1.2.0 -m "v1.2.0"` y `git push --tags`.
5. **Publicar el release**, que es lo que hace que `-FromRelease` y `-Update` vean la versión nueva:

   ```bash
   gh release create v1.2.0 --title "v1.2.0" --notes-file <(sed -n '/## \[1.2.0\]/,/^## \[/p' CHANGELOG.md)
   ```

   No hace falta subir ningún archivo: el instalador usa el `.zip` del código del tag, que GitHub
   arma solo. El repo es público, así que la descarga es anónima; queda un fallback a `gh` por si
   alguna vez vuelve a ser privado, o para pasar el límite de la API anónima.
6. En los repos que lo usen: `Run-SessionPrompts.ps1 -Update`, o esperar a que lo ofrezca solo.
