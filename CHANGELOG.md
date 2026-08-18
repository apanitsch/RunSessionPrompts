# Changelog

Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), versionado
[semver](https://semver.org/lang/es/). Qué cuenta como major, minor y patch para este script está en
el [README](README.md#versionado-y-releases).

## [No publicado]

## [1.2.0] — 2026-08-18

Salió de probar el transporte del prompt con payloads hostiles: comillas dobles pares e impares,
backticks, acentos agudos y comillas tipográficas, `<caso>\'</caso>`, XML, HTML, JSON con sus
escapes internos, combinaciones, metacaracteres de shell, `%VARIABLES%`, multilínea, unicode y
emoji. **En el camino normal (`claude.exe` bajo `pwsh`) los 21 payloads ya llegaban intactos.** Los
otros dos caminos no.

### Cambiado

- **El modo de pasaje de argumentos ahora se fija, no se adivina.** El runner pone
  `$PSNativeCommandArgumentPassing = 'Standard'` para su propio ámbito, en vez de detectar que
  alguien lo dejó en `Legacy` y compensarlo escapando a mano. Medido: además de ser más simple,
  arregla el único payload que el escapado manual todavía deformaba (un `\` al final del prompt
  llegaba duplicado). El escapado a mano quedó sólo para PowerShell 7.0–7.2, donde esa variable
  todavía no existe.

### Corregido

- **Un `claude` que resuelve a un shim `.cmd`/`.bat` ya no corrompe la corrida en silencio.** Medido
  por ese camino: un prompt **multilínea llega truncado en su primera línea** sin aviso —y todos los
  prompts son multilínea—, `%PATH%` lo expande cmd, y un `<` o un `>` (cualquier prompt con XML o
  HTML) hace fallar la invocación. Ahora el runner busca el `.exe` equivalente (mismo nombre en el
  `PATH`, o al lado del shim) y lo usa; si no hay ninguno, **no arranca** y explica qué hacer. Pasa
  con instalaciones por npm, que dejan un `claude.cmd` en el `PATH`.

### Agregado

- Los 21 payloads hostiles como caso de la suite, más uno que verifica que el nombre de la serie y
  del archivo del prompt —que viajan a `--rc` y `--name`— sobrevivan a caracteres como `&`, `^`,
  `%VAR%`, comillas simples, backticks y `!`.
- Casos para los dos caminos nuevos del shim: con `.exe` al lado (lo usa) y sin `.exe` (no arranca).

### Nota

- Los tests nuevos están verificados por mutación: no fijar el modo pone en rojo el caso de
  `Legacy`; aceptar el shim tal cual pone en rojo los dos casos de shim; escapar siempre pone en
  rojo los payloads y el `.exe` nativo.

## [1.1.1] — 2026-08-18

Sin cambios de comportamiento: lo que cambia es cuánto de esto está *verificado*.

### Agregado

- **Cuatro casos que cubren el problema de las comillas de punta a punta**, corriendo el runner
  contra un `.exe` nativo compilado para la prueba, que anota cada argumento tal como se lo entregó
  el sistema operativo: el prompt cruza intacto hacia un `.exe`, hacia un shim `.cmd`, y en modo
  `Legacy`; y Windows PowerShell 5.1 no puede correr el runner. Hasta acá la suite sólo probaba
  esto contra un doble en PowerShell, que se invoca **dentro del mismo proceso** y por lo tanto
  nunca cruza una línea de comandos de Windows: probaba la decisión, no el transporte.
- Los casos que no se pueden correr en una máquina ahora se **omiten con el motivo impreso**, en
  vez de fallar o saltearse en silencio.

### Corregido

- La tabla de mediciones del encabezado del runner decía «comillas PERDIDAS» donde lo que pasa es
  que el argumento se **parte en varios**: los pedazos de atrás llegan como argumentos sueltos. Y
  la fila del shim `.cmd`, que venía inferida de la documentación en una de las copias de origen y
  medida en otra, ahora está medida acá y cubierta por un test.

## [1.1.0] — 2026-08-18

### Agregado

- **Effort sugerido por sesión**, con la marca `<!-- effort-sugerido: xhigh -->` en el `.md` del
  prompt. Vale la misma regla que ya tenía el modelo, con el effort de la corrida (`high` por
  defecto, `-Effort` para cambiarlo) haciendo de **tope**: la sesión que pide menos o lo mismo
  arranca sola; la que pide más para y pregunta, antes de la primera sesión. Los valores son los
  cinco de `claude --effort`: `low`, `medium`, `high`, `xhigh`, `max`.
- `--effort` pasó a ser **por sesión**, como `--model`. El plan impreso y el `-DryRun` muestran los
  dos.

### Cambiado

- Una marca `modelo-sugerido` o `effort-sugerido` con un valor que no existe **corta con un error**
  en vez de ignorarse. Antes, `<!-- modelo-sugerido: haiku -->` se ignoraba en silencio y la sesión
  corría con el modelo base sin que nadie se enterara.
- El encabezado del plan dice «Tope de la corrida» en vez de «Modelo base», que es lo que de verdad
  es.

## [1.0.0] — 2026-08-18

Primera versión con control de cambios. Es la **suma** de las ocho copias que vivían en
`docs/session-prompts/` de Agentada, AtlasVDT, Buspack, Chat, Chat-usuarios-meta, ChatNet,
ncore-wingo y SRT.Kairos. Qué aportó cada una está en
[`docs/analisis-de-versiones.md`](docs/analisis-de-versiones.md).

### Agregado

- **Runner unificado** (`Run-SessionPrompts.ps1`) con todo lo que tenía cualquiera de las ocho:
  - menú de series, menú de modelo y menú de effort, todos por número;
  - `series-estado.txt`: el menú muestra sólo las series pendientes, en el orden de ejecución
    propuesta, y una corrida completa marca la serie terminada con la fecha;
  - marca `<!-- modelo-sugerido: … -->` por prompt, con la regla de bajar solo y preguntar para
    subir, resuelta **antes** de la primera sesión;
  - escapado de argumentos nativos condicionado a los dos casos donde hace falta
    (`$PSNativeCommandArgumentPassing = Legacy`, o `claude` como shim `.cmd`/`.bat`), con el motivo
    impreso en el log;
  - aislamiento opcional por git worktree (`-Worktree`), con reutilización al reanudar y guarda
    contra crear el worktree adentro del checkout principal;
  - `Ctrl+C` corta toda la corrida, no sólo la sesión en curso;
  - corte por tamaño del prompt antes de lanzar, para que nunca se trunque en silencio;
  - las sesiones corren paradas en la raíz del repo (o del worktree), no en la carpeta de series;
  - exclusión de las carpetas que empiezan con `_`, que son andamiaje y no series.
- **Portabilidad**, que es lo que ninguna de las ocho tenía:
  - `-SeriesRoot`, y descubrimiento automático de la carpeta de series cuando el runner vive fuera
    del repo;
  - `session-prompts.config.json`: los valores que diferían entre repos (rama base, prefijo de rama,
    worktree sí/no, modelo, effort) se escriben una vez por repo en vez de editar el script;
  - `-ClaudeCommand`, `-DryRun` y `-Version`.
- **`Install-SessionPrompts.ps1`**: instala y actualiza el runner y las plantillas en otro repo, sin
  pisar nunca las series ni la configuración, y negándose a pisar un runner modificado a mano salvo
  con `-Force`.
- **Plantillas genéricas** de serie (`README.md`, `ESTADO.md`) y de prompt de sesión.
- **Suite de tests** sin dependencias (`tests/Run-Tests.ps1`): repo git de juguete y un doble de
  `claude` que registra lo que recibió.

### Notas de migración

Un repo que ya tenga su copia del script sigue funcionando igual: la copia unificada acepta todos los
parámetros que aceptaba cualquiera de las ocho, con los mismos defaults. Las dos diferencias a mirar
antes de actualizar:

- **`-Worktree` es opcional y viene apagado.** Buspack lo hacía siempre y con la rama base fija en
  `Features-TMS`. Para reproducir ese comportamiento: `"worktree": true` y
  `"baseBranch": "Features-TMS"` en el `session-prompts.config.json` del repo.
- **Las carpetas que empiezan con `_` ya no son series**, en todos los repos. Si alguno tenía una
  serie ejecutable con nombre así, hay que renombrarla.

[No publicado]: https://github.com/apanitsch/RunSessionPrompts/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/apanitsch/RunSessionPrompts/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/apanitsch/RunSessionPrompts/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/apanitsch/RunSessionPrompts/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/apanitsch/RunSessionPrompts/releases/tag/v1.0.0
