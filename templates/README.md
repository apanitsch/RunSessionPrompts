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
  (La excepción es [`-Unattended`](#-unattended-la-serie-corre-sola), donde no hay `/exit` ni Remote
  Control y la serie avanza sola.)
- **Los prompts se guardan en UTF-8.** El runner los lee así, y si un `.md` quedó en la ANSI de
  Windows **corta la corrida nombrando el archivo**, en vez de mandarle a la sesión un texto con
  los acentos rotos. UTF-8 con o sin BOM, y UTF-16 con BOM, sirven todos.
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

## `-Unattended`: la serie corre sola

Con `-Unattended` la serie corre **sin supervisión**: no hay Remote Control, no hay `/exit`, y es cada
sesión la que dice si la serie puede seguir. Es opt-in, se confirma a mano antes de arrancar, y sin
el parámetro no cambia nada de lo de arriba.

```bash
pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Unattended
```

### El contrato: qué tiene que devolver una sesión

Cada sesión termina devolviendo un resultado estructurado:

```json
{ "result": "ok", "reason": "una o dos frases" }
```

El runner se lo pide a la sesión por el system prompt, así que **no hay que escribirlo en el
prompt**: llega solo. Lo que sí conviene que el prompt haga es dejar claro **qué cuenta como
terminado**, porque eso es lo que la sesión va a juzgar.

| `result` | Cuándo | Qué hace el runner |
| --- | --- | --- |
| `"ok"` | la sesión hizo lo que el prompt pedía y la siguiente puede construir sobre eso | sigue con la próxima |
| `"stop"` | no lo logró, quedó a medias, o seguir sería una mala idea | **frena la serie** e imprime el motivo |

El `reason` se imprime **siempre**, también cuando dice `ok`: es el registro de lo que pasó en cada
sesión, que en el modo interactivo se pierde con el scrollback.

**La serie sigue sólo si se cumple todo**: exit code 0, resultado presente y parseable, y `result`
en `ok`. Cualquier otra cosa frena —incluida la ausencia de resultado—. Es a propósito: si la falta
de señal se leyera como "seguí", una sesión que se colgó le arrastraría el error a todas las que
vienen.

### No hay un "después": el turno es toda la sesión

Cuando la sesión devuelve el resultado se cierra, y **lo que haya dejado corriendo en segundo plano
se muere con ella**. No hay despertador que la vuelva a llamar ni segunda vuelta donde terminar lo
que quedó. Eso el runner se lo dice a cada sesión en el mismo system prompt, así que no hay que
escribirlo en el prompt.

Lo que sí cambia es **cómo se escribe el prompt**: lo que la sesión tenga que esperar, lo espera
adentro del turno. Si el cierre depende de una suite de catorce minutos, esos catorce minutos son
parte de la sesión. Un prompt que no entra en un turno se parte en dos sesiones — no se deja que la
sesión se lo arregle mandando el trabajo al fondo, porque de ahí no vuelve.

### Las dos marcas que necesitan los prompts

**`runner-requerido` es obligatoria** para correr en este modo, en cada prompt:

```markdown
<!-- runner-requerido: 2.0 -->
```

Es lo que dice que el prompt fue escrito conociendo el contrato de arriba. Sin ella, `-Unattended` no
corre la serie y te nombra los prompts a los que les falta. Sin `-Unattended` la marca no molesta.

**`automatico: no` es opcional**, y sirve para la sesión que **necesita** un humano: la que hace un
deploy, la que borra algo, la que termina en una decisión tuya.

```markdown
<!-- automatico: no | hace deploy a producción -->
```

El motivo después del `|` es opcional y se imprime. La serie corre automática hasta la sesión
anterior y **frena ahí, limpio**, diciéndote con qué `-StartFrom` seguir a mano. Se detecta al
arrancar: antes de lanzar la primera sesión ya sabés dónde va a parar.

### Lo que se pierde, y lo que no

- **Se pierde la ventana en vivo.** No hay sesión en el celular mientras corre: pasás de "miro
  mientras" a "miro después".
- **No se pierden las sesiones.** Quedan guardadas igual que las interactivas, con su nombre, y el
  runner imprime el `claude --resume <id>` de cada una.
- **Los permisos los decide un clasificador** (`--permission-mode auto`), no vos. En este modo el
  modo de permisos no se elige: pasar `-PermissionMode` o `-FullAuto` junto con `-Unattended` es un
  error.
- **No hay techo de gasto** salvo que se lo pongas con `-MaxBudgetUsd 5`. Sin nadie mirando, una
  sesión trabada puede correr sin límite.

### Si te quedás sin cuota a la mitad

Una serie larga que corre de noche puede pegarle al **límite de uso de 5 horas**. Por default eso
frena la serie como cualquier otra falla, diciendo cuál fue el límite y cuándo vence.

Con `-ResumeWhen5HoursLimit` el runner **espera a que ese límite venza y reanuda esa misma sesión**
donde quedó:

```bash
pwsh -File .\Run-SessionPrompts.ps1 -PromptsPath .\mi-serie -Unattended -ResumeWhen5HoursLimit
```

Una sola espera por sesión: si la reanudada vuelve a chocar, la serie frena. Sólo aplica al límite
de 5 horas — el semanal y los demás se avisan igual, pero no se destraban esperando un rato. Y sólo
vale junto con `-Unattended`.

Para vos, como autor de un prompt, no cambia nada: la sesión reanudada recibe el mismo contrato y
tiene que devolver el mismo `{ "result", "reason" }` de siempre.

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
