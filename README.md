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
convención): el runner, `_plantillas/`, un `series-estado.txt` y un `session-prompts.config.json` de
ejemplo, y un `.session-prompts-version` con la versión y el hash de lo instalado.

Para **actualizar**, el mismo comando. El instalador no pisa nada que no haya puesto él:

| Situación en el destino | Qué hace |
| --- | --- |
| El runner es idéntico al que instaló | Lo actualiza sin preguntar |
| El runner está **modificado a mano** | Avisa, muestra cómo diferenciarlo, y **no toca nada** (sale con código 2) |
| Hay un runner **sin marca de versión** (copiado a mano, como los ocho originales) | Igual: avisa y no toca nada |
| Las series, el `series-estado.txt`, el `session-prompts.config.json` | **Nunca** se pisan |

Con `-Force` pisa igual, dejando un `.bak` al lado. Con `-WhatIf` dice qué haría y no toca nada.

### Sin instalar

El runner también funciona desde donde esté: si la carpeta donde vive no tiene series adentro, busca
`docs/session-prompts` (o `Docs/`, o con guión bajo) en el repo git donde estés parado. O se lo decís
con `-SeriesRoot`.

---

## Uso

> **Siempre con `pwsh`, nunca con `powershell`.** Ver [Por qué PowerShell 7](#por-qué-powershell-7-y-no-51).

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
| `-Model` | `opus` (default) o `sonnet`. Es el modelo **base**: cada prompt puede sugerir el suyo. |
| `-Effort` | `low`, `medium`, `high` (default), `xhigh`, `max`. |
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

### Modelo sugerido por sesión

Un prompt declara con qué modelo se pensó, en una marca del `.md`:

```markdown
<!-- modelo-sugerido: sonnet -->
```

Con el rango `sonnet < opus`:

- **sugerido menor que el base** → manda el de la sesión, sin preguntar. Bajar es barato, y si el
  prompt dice que con Sonnet alcanza, no hay motivo para gastar Opus.
- **sugerido mayor que el base** → el script **para y pregunta**, antes de arrancar. Correr una
  sesión con menos de lo que pide no es una decisión que se tome sola.
- **igual, o sin marca** → el base, sin ruido.

Regla práctica al escribir prompts: la sesión que **escribe** con el criterio ya resuelto va con
`sonnet`; la que **juzga** va con `opus`.

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

## Por qué PowerShell 7, y no 5.1

El prompt entero viaja como **un argumento** hacia `claude`, y casi todos los prompts citan algo
entre comillas. Medido en esta máquina con un fragmento real de prompt:

| Intérprete | Lo que recibe el ejecutable |
| --- | --- |
| Windows PowerShell 5.1, sin escapar | `el legacy loguea Session` ← **se corta en la primera comilla** |
| Windows PowerShell 5.1, escapando a mano | el texto entero, pero **sin las comillas** |
| PowerShell 7.x | el texto **intacto**, comillas incluidas |

O sea que bajo 5.1 todo prompt que cite algo entre comillas dobles llega mutilado **en silencio**:
nada falla, nada se pone rojo, y la sesión lee una cita distinta de la que se escribió. Por eso el
script tiene `#Requires -Version 7.0`: falla con un error claro en vez de degradar el prompt.

Y por eso el escapado manual heredado de 5.1 **no se aplica siempre**. Bajo 7.x con un `claude.exe`
nativo, PowerShell ya escapa por su cuenta y sumar escapado encima **corrompe** (cada `"` llega como
`\"`). El script decide una vez, al arrancar, y **lo escribe en el log**:

```
Argumentos nativos: NO escapa (lo hace PowerShell) -- modo Windows y 'claude' no es un shim .cmd/.bat
```

Escapa sólo en los dos casos donde hace falta: `$PSNativeCommandArgumentPassing` en `Legacy`, o un
`claude` que sea un shim `.cmd`/`.bat` (instalación por npm) bajo el modo `Windows`.

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
