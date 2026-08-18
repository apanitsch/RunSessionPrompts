# Run-SessionPrompts

Corre **series de prompts numerados** con Claude Code: un prompt por sesión, cada uno en contexto
limpio y con Remote Control, para que la serie entera avance sin que tengas que estar en la máquina.

Este repo es el **producto**: la versión con control de cambios de un script que hasta ahora vivía
copiado y pegado —y divergiendo— en `docs/session-prompts/` de ocho repositorios distintos. Lo que
hay acá es la **suma** de todas esas versiones, más lo que hace falta para instalarlo y actualizarlo
en cualquier repo. Qué aportó cada una está en [`docs/analisis-de-versiones.md`](docs/analisis-de-versiones.md).

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

**Todo lo que hay que decidir se pregunta al principio**, antes de la primera sesión. Es la única
promesa que el script no puede romper: contestás una vez y te vas.

---

## Instalación

Una vez, en el repo donde quieras usarlo:

```bash
pwsh -File C:\Users\andre\source\repos\RunSessionPrompts\Install-SessionPrompts.ps1 -Repo C:\ruta\a\MiRepo
```

Eso deja en `MiRepo\docs\session-prompts\` (o `Docs\session-prompts\`, si el repo ya usa esa
convención):

| Qué | Para qué |
| --- | --- |
| `Run-SessionPrompts.ps1` | el runner |
| `README.md` | **la referencia para los agentes del repo**: qué es el andamiaje, cómo se corre, y los criterios para elegir modelo y effort de cada sesión |
| `_plantillas/` | los moldes de una serie y de un prompt |
| `series-estado.txt` | qué series están pendientes y en qué orden (sólo la primera vez) |
| `session-prompts.config.json` | lo que ese repo fija por defecto (sólo la primera vez) |
| `.session-prompts-version` | versión y hashes de lo instalado |

Y después **lanza una sesión de Claude Code en el repo destino** para dejar el andamiaje
descubrible: que el `CLAUDE.md` de ese repo lo nombre, diga para qué sirve, cómo se corre y que la
referencia es ese `README.md`. La misma sesión **corrige las afirmaciones viejas** que el repo tenga
de versiones anteriores del script — `powershell` en vez de `pwsh`, "el script escapa siempre", "el
corte es 30000", un id de modelo viejo, "cada serie corre en un worktree". Los cambios quedan **sin
commitear**, para que los revises.

El prompt de esa sesión es [`templates/prompt-instalacion-claude-md.md`](templates/prompt-instalacion-claude-md.md)
y se puede editar. Con `-SkipClaudeMd` no se lanza; con `-Model` y `-Effort` se elige con qué corre
(por defecto `opus` y `high`).

Para **actualizar**, el mismo comando. El instalador no pisa nada que no haya puesto él:

| Situación en el destino | Qué hace |
| --- | --- |
| El runner es idéntico al que instaló | Lo actualiza sin preguntar |
| El runner está **modificado a mano** | Avisa, muestra cómo diferenciarlo, y **no toca nada** (sale con código 2) |
| Hay un runner **sin marca de versión** (copiado a mano, como los ocho originales) | Igual: avisa y no toca nada |
| Las series, el `series-estado.txt`, el `session-prompts.config.json` | **Nunca** se pisan |
| Un `README.md` propio del repo (los ocho originales tienen el suyo, con su índice de series) | Avisa y **no lo toca**; con `-Force` lo reemplaza dejando un `.bak` |

Con `-Force` pisa igual, dejando un `.bak` al lado. Con `-WhatIf` dice qué haría y no toca nada.

### Sin instalar

El runner también funciona desde donde esté: si la carpeta donde vive no tiene series adentro, busca
`docs/session-prompts` (o `Docs/`, o con guión bajo) en el repo git donde estés parado. O se lo decís
con `-SeriesRoot`.

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
| `-FullAuto` | `--dangerously-skip-permissions` en vez de `--permission-mode acceptEdits`. |
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

El `.exe` de prueba lo compila **Windows PowerShell 5.1**, que viene con Windows: PowerShell 7 no
puede generar ejecutables de consola. Es el único uso de 5.1 en el proyecto, y es para construir el
doble, nunca para correr el runner. En una máquina sin 5.1 esos casos se **omiten con el motivo a
la vista**, no en silencio.

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
5. En los repos que lo usen, `Install-SessionPrompts.ps1` para actualizar.
