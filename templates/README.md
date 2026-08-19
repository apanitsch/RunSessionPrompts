# `session-prompts/` — series de sesiones

Esta carpeta es el **andamiaje de series de sesiones** del repo. Una *serie* es un plan partido en
sesiones: cada sesión es un prompt numerado que se ejecuta en **contexto limpio**, sin memoria de
las anteriores. Las corre `Run-SessionPrompts.ps1`, una por vez, y cada una aparece en el celular y
en Claude Code Desktop con Remote Control.

> **Si sos un agente y llegaste acá:** esto es lo que tenés que saber para *escribir* o *ejecutar*
> una serie. La regla que gobierna todo lo demás está en la sección
> [Cada prompt es autocontenido](#cada-prompt-es-autocontenido).

---

## Anatomía

```
session-prompts/
├── Run-SessionPrompts.ps1        el runner (no se edita — ver "Si algo hay que cambiar")
├── README.md                     este archivo
├── series-estado.txt             qué series están pendientes y en qué orden
├── session-prompts.config.json   lo que este repo fija por defecto
├── _plantillas/                  moldes (las carpetas con "_" no son series)
└── mi-serie/
    ├── README.md                 contexto compartido de la serie (no se ejecuta)
    ├── ESTADO.md                 bitácora viva (no se ejecuta)
    ├── 01-primera-cosa.md        esto sí se ejecuta
    ├── 02-segunda-cosa.md
    └── 03-tercera-cosa.md
```

Sólo los `.md` **que empiezan con número** son prompts ejecutables, y corren en orden numérico
(`10-` va después de `02-`). El `README.md` y el `ESTADO.md` de una serie no se ejecutan: son el
contexto que las sesiones leen.

---

## Cómo se corre

```bash
pwsh -File .\Run-SessionPrompts.ps1
```

Sin parámetros pregunta todo por menú: qué serie, desde qué número, con qué modelo y con qué
effort. Todo eso se puede fijar por parámetro:

```bash
pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -StartFrom 1 -Model sonnet -Effort max
```

```bash
pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -DryRun
```

Tres cosas que conviene saber antes de la primera vez:

- **`pwsh`, nunca `powershell`.** El runner exige PowerShell 7 y falla con un error claro si lo
  corrés con la 5.1. No es preferencia: bajo 5.1 un prompt con comillas dobles llega mutilado **en
  silencio**.
- **Las sesiones no se cierran solas.** Son interactivas y con Remote Control: cuando la sesión
  terminó su trabajo, la cerrás con `/exit` —desde el celular si querés— y ahí arranca la siguiente.
- **Todo lo que hay que decidir se pregunta al principio.** Contestás una vez y te podés ir de la
  máquina. Si una sesión falla, la corrida se corta ahí.

---

## Modelo y effort: los criterios

El modelo y el effort que elegís al arrancar son el **tope de la corrida**. Cada prompt puede
declarar lo suyo con dos marcas, en las primeras líneas del `.md`:

```markdown
<!-- modelo-sugerido: sonnet -->
<!-- effort-sugerido: xhigh -->
```

Y la regla es la misma para los dos:

| La sesión pide… | Qué hace el runner |
| --- | --- |
| **menos** que el tope | usa lo que pide, sin preguntar — bajar es barato y la sesión sabe lo que necesita |
| **lo mismo**, o no trae marca | el tope, sin ruido |
| **más** que el tope | **para y pregunta**, antes de lanzar la primera sesión |

Con los defaults (`opus` y `high`): cualquier sesión puede abaratarse sola, y ninguna puede pedir
Opus con la corrida en Sonnet, ni `xhigh`/`max` con la corrida en `high`, sin que lo confirmes.

**Una marca con un valor que no existe corta con un error.** Los valores son `opus` y `sonnet` para
el modelo, y `low`, `medium`, `high`, `xhigh`, `max` para el effort.

### Cómo elegir, al escribir el prompt

La pregunta útil no es "qué tan importante es esta sesión" sino **qué tipo de trabajo hace**:

| Si la sesión… | Modelo | Effort |
| --- | --- | --- |
| **Escribe** con el criterio ya resuelto en el prompt: implementar algo especificado, portar, aplicar un patrón que ya está decidido | `sonnet` | `medium`–`high` |
| **Repite** algo mecánico y verificable: renombrar, mover, actualizar documentación a partir de un cambio ya hecho | `sonnet` | `low`–`medium` |
| **Juzga**: decidir cómo se modela algo, resolver algo que el prompt dejó abierto, elegir entre dos diseños, escribir una decisión que cuesta revertir | `opus` | `high` |
| **Juzga algo difícil**: diagnosticar un bug que nadie entiende, diseñar el corte de un módulo, reconciliar dos fuentes que se contradicen | `opus` | `xhigh`–`max` |

Dos advertencias que valen más que la tabla:

- **El effort alto no arregla un prompt vago.** Si la sesión no sabe contra qué verificar, `max` sólo
  la hace dudar más caro. Antes de subir el effort, revisá si lo que falta es contexto en el prompt.
- **Una sesión que "escribe" pero tiene que adivinar el criterio en realidad juzga.** Si al escribir
  el prompt no pudiste dejar el criterio resuelto, la marca honesta es `opus`.

---

## `series-estado.txt` — qué muestra el menú

El menú muestra **sólo las series pendientes**, y **en el orden de ejecución propuesta**:

```
pendiente 1 la-que-va-primero
pendiente 2 la-que-sigue
terminada - una-que-ya-cerro   # cerrada 2026-01-31
```

Una serie que no figura se considera pendiente y va al final: una carpeta nueva aparece sin que
haya que acordarse de anotarla. **El script lo escribe solo**: cuando una corrida termina bien y
llegó hasta el último prompt, marca la serie `terminada` con la fecha. Con `-Todas` se ven todas.

Es un archivo exclusivo del runner: nada más lo lee, y si lo borrás el script sigue andando.

---

## Cómo se arma una serie nueva

1. Creá la carpeta: `session-prompts/<mi-serie>/`, en `kebab-case`.
2. Copiá `_plantillas/plantilla-serie-README.md` → `<mi-serie>/README.md` y
   `_plantillas/plantilla-serie-ESTADO.md` → `<mi-serie>/ESTADO.md`. Ahí va el contexto
   **compartido**: los hallazgos ya verificados y las decisiones ya tomadas, para que ninguna sesión
   los re-investigue ni los re-litigue.
3. Por cada sesión, copiá `_plantillas/plantilla-session-prompt.md` → `<mi-serie>/NN-descripcion.md`.
4. Anotá la serie en `series-estado.txt` con su orden.

### Cada prompt es autocontenido

Es **la** regla. Cada sesión arranca sin memoria de las anteriores y sin la conversación en la que
se planificó la serie. Un prompt que sólo se entiende "si estuviste en la charla anterior" es un
prompt roto.

Lo que la sesión necesita saber tiene que estar en uno de estos cuatro lugares, y el prompt tiene
que nombrarlos:

- el propio prompt;
- el `README.md` de la serie (contexto compartido: hallazgos, decisiones, reglas);
- el `ESTADO.md` de la serie (qué dejó la sesión anterior);
- un archivo del repo que el prompt cite explícitamente, con su ruta.

Y dos consecuencias prácticas:

- **Decí contra qué se verifica**, con los comandos concretos. "Que ande" no es un criterio.
- **Cerrá con documentación al día.** La sesión que no actualiza el `ESTADO.md` obliga a la
  siguiente a adivinar dónde quedó todo.

---

## Aislamiento por worktree (opcional)

```bash
pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Worktree
```

Con `-Worktree`, la serie corre en su propio git worktree (`<repo>\..\worktrees\<serie>`), en una
rama nueva `sesiones/<serie>`. Sirve cuando el checkout principal no se puede mover —porque lo está
sirviendo IIS, o un watcher— o cuando el arnés de tests se aísla por ruta de disco. Las sesiones se
encadenan igual: la 02 construye sobre lo que commiteó la 01. El worktree **no se borra** al
terminar, y el script imprime cómo mergearlo y cómo limpiarlo.

Viene apagado. Si este repo lo necesita siempre, se pone en la configuración en vez de acordarse
del parámetro.

---

## `session-prompts.config.json`

Lo que este repo fija por defecto: modelo, effort, permisos, si las series corren aisladas, la rama
base de los worktrees. **La precedencia es: parámetro explícito > configuración > default del
script.** El archivo trae cada clave documentada adentro.

El runner **valida el archivo entero antes de arrancar**: una clave que no reconoce —un `"modelo"`
donde va `"model"`— o un valor del tipo equivocado —`"true"` entre comillas donde va un booleano—
corta con un error que las nombra a todas, y sugiere la clave parecida. Las que empiezan con `_` son
comentarios y no se miran. Es a propósito: una clave mal escrita no cambia nada visible, y se
descubre cuando ya corrió media serie con el modelo o el aislamiento que no era.

---

## Si algo hay que cambiar

**No edites `Run-SessionPrompts.ps1`.** Es un producto versionado que vive en su propio repositorio
y se instala acá; una edición local se pierde en la próxima actualización, y —peor— convierte a este
repo en una variante divergente, que es exactamente el problema que ese producto vino a resolver.

- Si es algo **de este repo**: va al `session-prompts.config.json`.
- Si es algo **del runner** (un bug, una capacidad que falta): se arregla en el repositorio del
  producto, sale una versión nueva, y se actualiza acá con su instalador.

La versión instalada está en `.session-prompts-version`. Para actualizar:

```bash
pwsh -File <ruta-al-producto>\Install-SessionPrompts.ps1 -Repo <ruta-a-este-repo>
```

El instalador **no pisa** las series, ni `series-estado.txt`, ni la configuración, ni un runner que
alguien haya tocado a mano (avisa y corta).
