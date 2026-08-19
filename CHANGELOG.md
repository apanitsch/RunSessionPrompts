# Changelog

Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), versionado
[semver](https://semver.org/lang/es/). Qué cuenta como major, minor y patch para este script está en
el [README](README.md#versionado-y-releases).

## [No publicado]

## [1.7.0] — 2026-08-19

### Cambiado

- **El `session-prompts.config.json` se valida entero antes de arrancar.** Hasta ahora el runner
  leía las claves que le interesaban y todo lo demás se ignoraba: un `"modelo"` donde va `"model"`,
  o un `"worktree": "true"` con el booleano entre comillas, no cambiaba nada visible — el script
  simplemente preguntaba el modelo, o corría sin aislar— y se descubría con media serie corrida
  donde no era. Ahora una clave desconocida o un valor del tipo equivocado **cortan**, nombrando
  todos los problemas juntos, sugiriendo la clave parecida (`'modelo'. Quisiste decir 'model'?`) y
  diciendo qué se esperaba (`true o false, sin comillas`). Es el mismo criterio que ya tenían las
  marcas `modelo-sugerido` y las líneas de `series-estado.txt`.
  - Las claves que empiezan con `_` siguen siendo comentarios y no se miran: es lo que le permite al
    archivo de ejemplo documentarse a sí mismo.
  - `null` sigue queriendo decir "no la fijo", en cualquier clave.
  - **Al actualizar:** si el `session-prompts.config.json` de un repo tiene una clave que el runner
    no reconoce, la próxima corrida corta y la nombra. Se arregla borrándola, corrigiéndola, o
    poniéndole un `_` adelante si era un comentario.
- **`-BaseBranch`, `-BranchPrefix` y `-WorktreeRoot` pasados sin `-Worktree` avisan que no se
  aplican**, en vez de no hacer nada. La corrida sigue igual: es exactamente lo que se pidió, pero
  quien los pasó creía que la serie iba a salir de esa rama.
- **`Install-SessionPrompts.ps1` con `-ReleaseZip` y `-FromRelease` a la vez dice cuál usa** y cuál
  ignora, con su valor. Son dos orígenes distintos y sólo se usa uno; elegir en silencio deja a quien
  lo corrió creyendo que instaló el release que nombró.

### Corregido

- **El menú de modelo y el de effort ya no abortan la corrida.** Sin `-Model` / `-Effort` y sin esas
  claves en `session-prompts.config.json` —que es como viene la plantilla, con las dos en `null`—, el
  script cortaba antes de mostrar el menú con `The variable cannot be validated because the value  is
  not a valid value for the Model variable`. PowerShell revalida el `ValidateSet` del parámetro en
  **cada** asignación a esa variable, y el script le asignaba el `''` que devuelve la resolución
  cuando no hay ni parámetro ni configuración. Ahora el valor se resuelve en una variable aparte y a
  `$Model` / `$Effort` sólo se le asigna un valor ya válido. Estaba desde la 1.0.0: todo repo que no
  fijara modelo y effort en su configuración no podía correr una serie a mano.
- Por el mismo motivo, **un modelo o un effort desconocido en la configuración ahora sí imprime su
  error** (`Modelo desconocido en la configuracion: 'gpt'`) en vez de morir con el mensaje de
  validación de PowerShell, que no dice de dónde salió el valor.
- **Cuando no hay ninguna serie que correr, el script corta ahí.** Si el menú no tiene nada que
  ofrecer —todas terminadas, o ninguna serie todavía— pregunta por una carpeta a mano; un Enter en
  esa pregunta dejaba la carpeta vacía y el script **seguía**: preguntaba modelo, preguntaba effort,
  y recién entonces moría con `No existe la carpeta: `, sin carpeta. Ahora dice
  `No elegiste ninguna carpeta` y termina.
- **`-StartFrom` negativo corta con un error** en vez de correr la serie entera desde el primer
  prompt. El menú sólo acepta dígitos, pero por parámetro entraba cualquier cosa: empezar en `-3` no
  es lo mismo que empezar en el primero, y hacerlo igual, sin decir nada, es justo lo que este
  script no hace.
- **`Install-SessionPrompts.ps1 -ClaudeCommand ''` ya no revienta al final.** El vacío ahora se
  toma como "no me lo pasaron" —el default `claude`—, igual que en el runner. Antes instalaba todo
  bien y después cortaba con un `Cannot validate argument on parameter 'Name'` de PowerShell,
  saliendo con código 1 sobre una instalación que en realidad había salido bien.

## [1.6.0] — 2026-08-19

### Cambiado

- **Una línea mal escrita en `series-estado.txt` ahora corta con un error**, diciendo en qué línea
  está y cuál es, en vez de ignorarse. Era el último lugar del script que degradaba en silencio: una
  serie mal anotada aparece como pendiente estando terminada —o al revés— y eso no se nota mirando
  el menú. Es el mismo criterio que ya tenían las marcas `modelo-sugerido` y `effort-sugerido`.
- Con eso, **un nombre de serie con espacios se detecta** en vez de leerse truncado:
  `terminada - mi serie` se tomaba como la serie `mi`, y nadie se enteraba.
- La validación corre al arrancar, no al abrir el menú: con `-PromptsPath` el menú no se abre, pero
  el archivo igual se reescribe al cerrar la serie.

### Corregido

- **Un checkout normal del repo destino ya no hace pasar el andamiaje por "modificado a mano".** El
  instalador reconoce lo que instaló comparando un hash contra el que dejó anotado en
  `.session-prompts-version`, y ese hash era de los **bytes**. Si el repo destino tiene
  `core.autocrlf=true` y no tiene `.gitattributes` —el default de Git for Windows— git reescribe los
  finales de línea al hacer checkout: el contenido es idéntico, el runner ni se entera (no lee el
  README), pero los bytes cambian. Verificado end to end: instalar, commitear y clonar alcanzaba
  para que la actualización siguiente cortara con `el runner del destino esta MODIFICADO` y
  `exit 2`, y para que el README dejara de actualizarse por `el destino ya tiene uno propio` —
  o sea, **en silencio**. Ahora el hash es del contenido con los finales de línea normalizados
  (y sin BOM), así que un cambio de checkout no cuenta como edición y una edición de verdad se
  sigue detectando igual.
- Las marcas que escribieron las versiones anteriores —hash de los bytes— se siguen aceptando, y la
  marca queda reescrita en el formato nuevo, que ahora dice `"hashDe": "contenido"`.

### Nota

- El formato no cambió. Los `series-estado.txt` que ya existen se leen sin una sola queja:
  verificado pasando dos archivos reales, de 2 y de 56 series, por el runner nuevo.

## [1.5.0] — 2026-08-18

### Cambiado

- **Bajar el release es el comportamiento por defecto cuando el instalador está solo.** Si
  `Install-SessionPrompts.ps1` no tiene el producto al lado —que es como queda cuando lo bajás por
  tu cuenta— no tiene de dónde instalar, así que baja el último release sin que se lo pidan, y lo
  dice. Con el producto al lado (un clon, o el release ya descomprimido) sigue instalando desde ahí,
  sin tocar la red. `-FromRelease` queda para pedir un tag distinto del último, o para forzar la
  descarga teniendo el producto al lado.
- El comando de instalación del README quedó en lo mínimo: sin `-FromRelease latest` y sin `-Repo`,
  que ya salía del directorio donde estés parado (o de cualquier subcarpeta del repo).

### Corregido

- El instalador caía a `gh` para averiguar el último release **aunque le hubieran apuntado a otro
  origen** con `SESSION_PROMPTS_RELEASES_URL`: terminaba instalando un release distinto del pedido,
  en silencio. Ahora ese fallback sólo corre cuando el origen es la API de GitHub, como ya hacía el
  runner. Lo encontró un test que empezó a fallar cuando se publicó el primer release de verdad.

## [1.4.1] — 2026-08-18

### Cambiado

- El [README](README.md) arranca con **cómo instalar**: el repo es público, así que la primera cosa
  que ve alguien que llega tiene que ser el comando que lo pone a andar. El contexto de de dónde
  salió el producto bajó a su propia sección.
- Los documentos ya no hablan de una etapa privada: la descarga es anónima. El fallback a `gh` que
  tienen el runner y el instalador queda por si el repo vuelve a ser privado, o para pasar el
  límite de la API anónima.
- Cuando no se puede averiguar cuál es el último release, el instalador ahora dice que **puede que
  todavía no haya ninguno publicado** —además de la posibilidad de que no haya conexión— y ofrece
  las dos salidas: `-FromRelease <tag>` y `-ReleaseZip <ruta>`.

## [1.4.0] — 2026-08-18

Hasta acá, instalar y actualizar necesitaba tener el clon del producto en la máquina. Ahora no.

### Agregado

- **`Install-SessionPrompts.ps1 -FromRelease [tag]`**: baja el release publicado en GitHub (el
  último, o el tag que se le pase), lo descomprime y **se re-ejecuta desde adentro** — la
  instalación la hace siempre la versión que se está instalando, así que el archivo que bajaste
  puede quedar viejo sin que importe. Alcanza con ese archivo suelto: no hace falta clonar nada.
  Con `-ReleaseZip <ruta>` instala desde un `.zip` ya bajado, sin tocar la red.
- **`Run-SessionPrompts.ps1 -Update`**: desde el repo donde ya está instalado, baja el release y lo
  instala con el instalador que viene adentro. Con `-SkipClaudeMd` no corre la sesión que pone al
  día el `CLAUDE.md`; con `-Force` pisa un runner que el instalador no reconozca como suyo.
- **Chequeo de versión al arrancar**: una vez por día, antes de cualquier menú, el runner mira si
  hay una versión nueva publicada y la **ofrece**. Nunca actualiza solo. El chequeo tiene cinco
  segundos de paciencia, se anota en el perfil de la máquina (no en el repo, que está commiteado),
  y si falla —sin conexión, sin releases todavía— la corrida sigue igual. Se apaga con
  `-SkipUpdateCheck` o con `"checkForUpdates": false`.
- Mientras el repo del producto sea privado, la API anónima de GitHub contesta 404 y tanto el
  runner como el instalador caen a `gh`, que usa la credencial del usuario. Cuando sea público,
  funciona sin `gh`.

### Nota

- Un bug que encontró el test de la actualización: la salida del instalador se colaba en el **valor
  de retorno** de la función que lo invoca (en PowerShell, lo que un comando nativo escribe adentro
  de una función va al stream de salida), y un array no vacío es verdadero — así que un instalador
  que se negaba a pisar el runner se reportaba como «Actualizado». Ahora esa salida va a la consola
  con `Out-Host` y el resultado se lee del exit code. Verificado por mutación.

## [1.3.0] — 2026-08-18

Instalar los archivos no alcanzaba: si el `CLAUDE.md` del repo no nombra el andamiaje, ningún agente
lo encuentra; y si el repo venía de una copia vieja, lo que ahí dice puede ser falso hoy.

### Agregado

- **La instalación deja un `README.md` en la carpeta de series**, escrito para los agentes que
  trabajen en ese repo: qué es el andamiaje, cómo se corre, cómo se arma una serie, y —lo que no
  estaba en ningún lado— **los criterios para elegir modelo y effort de cada sesión**, con una tabla
  de qué usar según la sesión *escriba*, *repita*, *juzgue* o *juzgue algo difícil*, y las dos
  advertencias que importan (que el effort alto no arregla un prompt vago, y que una sesión que
  tiene que adivinar el criterio en realidad juzga).
- **La instalación lanza una sesión de Claude Code en el repo destino** que deja el andamiaje
  descubrible en su `CLAUDE.md` y **corrige las afirmaciones viejas** de versiones anteriores del
  script (`powershell` en vez de `pwsh`, "escapa las comillas siempre", "corta en 30000 caracteres",
  un id de modelo viejo, "cada serie corre en un worktree", "editá el script para cambiar la rama
  base"). Corre con `-p`, deja los cambios sin commitear, y usa las mismas reglas de transporte que
  el runner. Se saltea con `-SkipClaudeMd`; el modelo y el effort se eligen con `-Model` y `-Effort`.
  El prompt vive en `templates/prompt-instalacion-claude-md.md` y se puede editar.

### Corregido

- El instalador guardaba en `.session-prompts-version` el hash de un `README.md` **propio del repo**
  aunque no lo hubiera puesto él. La siguiente actualización lo tomaba por suyo y lo pisaba sin
  avisar ni dejar copia. Ahora sólo registra el hash de lo que instaló. (Lo encontró el test que
  verifica que un README ajeno no se pisa.)
- El instalador reporta la carpeta de series con **el nombre que tiene en disco** (`Docs` o `docs`),
  y no el de la variante con la que la encontró: en Windows las dos existen para `Test-Path`, y esas
  rutas terminan escritas en el `CLAUDE.md` del destino.
- La sesión de instalación cierra stdin, así `claude -p` no se queda tres segundos esperando datos
  que nunca van a llegar.

## [1.2.1] — 2026-08-18

Salió de pasar los **439 prompts reales** que existían cuando esto se unificó por el runner, contra
el `.exe` de prueba. **436 llegaron byte a byte.** Los otros tres no los corrió el runner: pesan
35201, 40023 y 45712 caracteres, o sea que están por encima del techo de Windows (32767 para toda
la línea de comandos) y hay que partirlos. Eso no tiene arreglo posible del lado del script.

### Corregido

- **El corte por tamaño ahora mide la línea de comandos completa** —ruta del ejecutable, flags,
  nombre de la sesión y prompt ya escapado— contra el techo real de Windows, en vez de comparar el
  largo crudo del prompt contra un 30000 fijo. Ese número se equivocaba **en las dos direcciones**,
  y las dos aparecieron midiendo:
  - rechazaba un prompt real de 31697 caracteres, que entra perfectamente (medido: con texto plano entra un prompt de 32500 y falla uno de 32600);
  - habría aceptado un prompt bastante más corto pero lleno de comillas, que no entra: cada `"`
    viaja como `\"`, así que 22000 caracteres de `"a"` ocupan casi el doble.

### Cambiado

- `maxPromptChars` pasó a ser un **tope propio del repo** (opcional, para quien quiera prompts
  cortos por política) en vez del límite del sistema, que ahora el runner calcula solo. La
  plantilla de configuración viene con la clave en `null`.

### Nota

- Verificado por mutación: volver a cortar por el largo crudo del prompt pone en rojo el caso del
  prompt grande que sí entra y el del prompt lleno de comillas.

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

Primera versión con control de cambios. Es la **suma** de las ocho copias que vivían, divergiendo,
en la carpeta `docs/session-prompts/` de otros tantos repositorios. Qué aportó cada una está en
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

- **`-Worktree` es opcional y viene apagado.** Una de las copias lo hacía siempre, y con la rama
  base escrita en el código. Para reproducir ese comportamiento: `"worktree": true` y
  `"baseBranch": "<la rama>"` en el `session-prompts.config.json` del repo.
- **Las carpetas que empiezan con `_` ya no son series**, en todos los repos. Si alguno tenía una
  serie ejecutable con nombre así, hay que renombrarla.

> Las versiones anteriores a la 1.4.1 no tienen tag: existieron el mismo dia, mientras el producto
> se armaba, y no hay a que volver. El unico tag que hace falta es el de la version publicada, que
> es la que buscan `-FromRelease latest` y `-Update`.

[No publicado]: https://github.com/apanitsch/RunSessionPrompts/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/apanitsch/RunSessionPrompts/releases/tag/v1.7.0
[1.6.0]: https://github.com/apanitsch/RunSessionPrompts/releases/tag/v1.6.0
[1.5.0]: https://github.com/apanitsch/RunSessionPrompts/releases/tag/v1.5.0
[1.4.1]: https://github.com/apanitsch/RunSessionPrompts/releases/tag/v1.4.1
