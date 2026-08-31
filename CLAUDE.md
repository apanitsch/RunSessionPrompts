# CLAUDE.md — RunSessionPrompts

## 1. Qué es este repo

El **producto** `Run-SessionPrompts.ps1`: el runner de series de prompts que hasta agosto de 2026
vivía copiado y pegado en `docs/session-prompts/` de ocho repositorios, divergiendo en cada uno. Acá
está la versión unificada, con control de cambios, tests e instalador.

Dos objetivos, y todo cambio se juzga contra ellos:

1. **Reutilizable en cualquier repo, sin editarlo.** Si algo hay que cambiar por repo, va al
   `session-prompts.config.json` o a un parámetro — nunca a una edición del script. Cada vez que una
   copia se edita a mano, nace una novena versión divergente.
2. **Versionado y releases normales.** Semver, `CHANGELOG.md`, tag. El procedimiento está en el
   [README](README.md#versionado-y-releases).

## 2. Reglas duras

- **PowerShell 7, siempre.** El runner tiene `#Requires -Version 7.0` y la documentación dice
  `pwsh -File …`, nunca `powershell -File …`. No es preferencia: bajo Windows PowerShell 5.1 un
  argumento nativo con comillas dobles llega mutilado **en silencio**, y los prompts citan textos
  entre comillas todo el tiempo. Está medido y explicado en el
  [README](README.md#por-qué-powershell-7-y-no-51) y en el encabezado del propio script. **Esto ya
  está resuelto en este repo**: si tocás un `.ps1` o un ejemplo de la documentación, mantenelo así.
- **Los `.ps1` en ASCII puro**, sin acentos ni eñes. Los `.md` sí llevan acentos.
- **Todo cambio de comportamiento entra con su caso en `tests/Run-Tests.ps1`**, y la suite queda en
  verde. Correrla no cuesta nada y no lanza ninguna sesión real:

  ```bash
  pwsh -File .\tests\Run-Tests.ps1
  ```

- **La versión vive en un solo lugar:** `$script:RunnerVersion`, adentro del runner. El instalador la
  lee de ahí. No la dupliques.
- **Todo lo que hay que decidir se pregunta antes de la primera sesión.** Es la única promesa que el
  script no puede romper: el usuario contesta una vez y se va de la máquina. Ninguna pregunta nueva
  puede quedar adentro del loop.
- **Nada se degrada en silencio.** Si una marca de un prompt está mal escrita, si el prompt no entra
  en la línea de comandos, si el escapado de comillas puede corromper el texto: error claro o
  motivo impreso, nunca seguir con algo distinto de lo que se pidió.

## 3. Decisiones ya tomadas — no re-litigar

- **El modo de pasaje de argumentos se fija (`Standard`), no se adivina.** Bajo `pwsh` con un
  `claude.exe` nativo, PowerShell escapa solo y sumar escapado a mano **corrompe** cada `"` del
  prompt. Medido cuatro veces: dos independientes en dos de las copias de origen, y dos acá contra
  un `.exe` nativo hecho para la prueba, la segunda con 21 payloads hostiles. El escapado manual
  quedó **sólo** para PowerShell 7.0–7.2, donde `$PSNativeCommandArgumentPassing` no existe.
- **Un `claude` que resuelve a un shim `.cmd`/`.bat` no sirve, y el runner no arranca.** Medido: por
  ese camino un prompt multilínea llega truncado en su primera línea, en silencio. El runner primero
  busca el `.exe` equivalente; si no hay, corta. No lo «arregles» agregando escapado: son reglas de
  `cmd.exe`, no de `CommandLineToArgvW`.
- **Todo esto tiene test contra un `.exe` nativo, y los tests están verificados por mutación** (no
  fijar el modo, aceptar el shim, escapar siempre y no escapar nunca ponen en rojo los casos que
  corresponden). Si tocás `Resolve-ComandoClaude`, `ConvertTo-NativeArg` o el bloque que fija el
  modo, corré la suite: es lo único que separa este script de degradar prompts en silencio.
- **`-Worktree` es opcional y viene apagado.** Una de las copias de origen lo hacía siempre; la
  mayoría de los repos no lo necesita.
- **`-Unattended` es opt-in, se confirma a mano, y el modo de permisos ahí no se elige: es `auto`.**
  Todo lo demás sigue exactamente igual sin el parámetro. Las decisiones que no se re-litigan:
  - **El JSON de resultado es un freno, no un certificado.** `stop` vale mucho (un agente que dice
    "no pude" casi nunca se equivoca); `ok` vale poco (el modo de falla más común es la sesión que
    entendió mal y está convencida de que hizo bien). Por eso no se confía más, sólo se corta antes.
  - **La ausencia de resultado es `stop`.** Medido: en headless el exit code es 0 aunque el agente
    no haya podido hacer nada. Si la falta de señal se leyera como "seguí", una sesión colgada le
    arrastraría el error a toda la serie.
  - **El contrato viaja por `--append-system-prompt`, no por el README del repo destino.** Así llega
    siempre, sin depender de que el agente lea un archivo ni de que el autor del prompt se acuerde,
    y queda versionado con el runner.
  - **El vocabulario es chico y no ejecutable**: enum de dos valores y un `reason` que se imprime,
    nunca se parsea. El JSON lo escribe un agente que estuvo leyendo el repo; darle verbos sería
    darle a ese contenido un canal para dirigir el runner.
  - **`[Console]::OutputEncoding` se fija en UTF-8, y se fija ARRIBA DE TODO.** (Desde la 2.0.1 se
    fija siempre, no sólo acá, y también en el instalador — el detalle está más abajo.) El canal de vuelta
    es el stdout de un proceso nativo: con otra codificación, un `reason` con acentos se corrompe y
    el JSON parsea igual. Y el lugar importa — medido en pwsh 7.6.5 con `-File`: **el host se queda
    con el encoding que tenía cuando escribió por primera vez**, así que fijarlo al lado del loop
    arregla la lectura y deja la escritura en la codificación vieja (una corrida redirigida a un
    archivo sale en la ANSI de la consola). Hay **dos** tests contra un `.exe` nativo, con la consola
    del proceso hijo en 1252 —uno por cada lado del canal—, y son dos porque uno solo dejaba pasar
    una de las dos mutaciones: leer mal y escribir mal con la *misma* codificación equivocada
    devuelve los bytes originales y el error se cancela.
  - **No se usa `Start-Process`** para poder poner un timeout: sus reglas de comillas son otras y
    volvería a abrir la clase de corrupción que este repo existe para no cometer. El techo es
    `-MaxBudgetUsd`, que el CLI corta con exit code distinto de cero.
- **`-ResumeWhen5HoursLimit` es opt-in, y sólo vale junto con `-Unattended`.** Fuera de ese modo hay
  un humano del otro lado, que es quien decide si vale la pena esperar cinco horas. Las decisiones
  que no se re-litigan:
  - **El límite de 5 horas se reconoce por el `rate_limit_event` del stream, exigiendo `rejected` y
    `five_hour` juntos.** Ni el exit code ni el evento de cierre alcanzan: ahí el `terminal_reason`
    dice `api_error` y el `api_error_status` dice `429`, que es lo mismo que dicen el semanal, el de
    Opus y una sobrecarga — y ninguno de esos se destraba esperando. Los demás límites **sí se
    avisan** por consola, con su nombre y su vencimiento; lo que no hacen es disparar la espera.
  - **Una sola espera por sesión.** La segunda vez ya no es mala suerte con el reloj: es una sesión
    que necesita más cuota de la que hay, y esperar de nuevo la deja dando vueltas toda la noche.
  - **Se despierta en `resetsAt` más 5 minutos**, y contra el reloj absoluto, no con un
    `Start-Sleep` largo. El corte del servidor no es exacto al segundo, y una máquina que suspende
    no tiene por qué despertarse antes de tiempo. Un vencimiento a más de 6 horas no se espera: se
    corta diciéndolo.
  - **La sesión reanudada lleva el MISMO contrato.** Sin volver a pasarle `--json-schema` y
    `--append-system-prompt` no dejaría resultado estructurado, y el semáforo la leería como una
    sesión colgada — la misma pared contra la que se acababa de chocar. Está medido que en un
    `--resume` los dos flags siguen aplicando.
  - **La rama va ANTES del semáforo, no adentro.** "Sin resultado es `stop`" no se toca: lo que se
    agregó es una causa de corte conocida y externa, que se atiende antes de llegar a esa decisión.
  - **`-MaxBudgetUsd` es un techo por invocación**, así que una sesión que espera y reanuda puede
    gastar el doble. Se dice en la confirmación de `-Unattended`, junto con que la máquina se queda
    esperando: las dos cosas se saben antes de la primera sesión, no corriendo.
- **Nada de esto se dedujo: está medido, y la medición vive en el repo.** `tools/` levanta una API
  falsa de Anthropic en loopback y maneja al `claude.exe` real contra ella, sin gastar cuota. Se
  rehace con `pwsh -File .\tools\Measure-Limite5Horas.ps1`, y devuelve error si alguna respuesta
  cambió — o sea que también es la alarma de cuando sale una versión nueva del CLI. Lo medido contra
  la 2.1.229 está en el [README](README.md#el-arnés-del-límite-de-5-horas) y resumido en el
  encabezado del bloque del runner. **No usa `System.Net.HttpListener`**: sus prefijos piden reserva
  de URL o privilegios de administrador, y el arnés tiene que correr en cualquier máquina. Y **el
  login normal se deja como está**, redirigiendo sólo `ANTHROPIC_BASE_URL`: la extracción de cuota
  del 429 depende de que la sesión sea de suscripción, así que con una API key falsa la medición
  podría dar un falso negativo.
- **La consola se pone en UTF-8 en los dos ejecutables, y en los dos arriba de todo.** El runner lo
  hace siempre, no sólo en `-Unattended`: por ese mismo stdout vuelve todo lo que la sesión
  escribe. Y el instalador lo hace por su cuenta porque **no alcanza con uno solo** — medido, con
  el runner en la ANSI y el instalador en UTF-8 (el camino de `-Update`, donde el runner lee la
  salida del instalador por un pipe) el texto sale roto igual: manda el proceso pegado a la
  consola. Lo que cambia entre los dos modos es qué pasa si no se puede fijar: en `-Unattended` es
  fatal, porque ahí el canal se parsea; en una corrida normal se sigue, porque lo que se degrada es
  el dibujo y los bytes son recuperables. Los dos la restauran al terminar, salgan por donde salgan. Lo que **no** se puede arreglar —venir del `-Update` de un runner anterior a
  la 2.0.1, que lee la salida del instalador en la ANSI— se **avisa**: una línea antes de la sesión
  del `CLAUDE.md`, diciendo que es sólo estético. El instalador lo sabe porque la versión previa
  está en la marca `.session-prompts-version` del destino.

- **Un prompt que no sea UTF-8 corta la corrida.** Se valida con una decodificación UTF-8
  estricta antes que nada, y el UTF-16 sin BOM aparte por sus bytes NUL. No se adivina la
  codificación ni se convierte sola: leer un prompt en otra codificación es mandarle a la
  sesión un texto distinto del que se escribió, que es lo mismo que este repo evita del lado
  de los argumentos.
- **El patrón de las marcas termina en `[ \t]*\r?$`, y el `\r?` no se saca.** `$` en modo
  multilínea matchea antes del `\n`, así que en un `.md` con fin de línea CRLF —lo que entrega Git
  para Windows en un repo sin `.gitattributes`, o sea el caso normal— sin ese `\r?` **ninguna**
  marca aplica, y no aplica en silencio. Está medido y tiene test.
- **Las carpetas que empiezan con `_` no son series**, aunque tengan prompts numerados adentro. Es lo
  que permite que `_serie-de-ejemplo` muestre el formato completo sin ensuciar el menú.
- **El `session-prompts.config.json` se valida entero al arrancar**, contra la lista de claves que el
  runner realmente mira y contra el tipo de cada una: una clave desconocida o un valor del tipo
  equivocado cortan. La lista vive en `$script:ConfigEsquema` — si agregás una clave nueva, va ahí, o
  el propio archivo de ejemplo deja de pasar la validación (hay un test que lo comprueba). Las claves
  que empiezan con `_` son comentarios y se ignoran.
- **El corte por tamaño es un error, no un truncado**, y **mide la línea de comandos completa**
  (ejecutable + flags + nombre de sesión + prompt escapado) contra el techo de Windows, no el largo
  crudo del prompt. Un número fijo se equivoca en las dos direcciones: está medido, y los dos casos
  aparecieron entre los prompts reales.
- **Los 439 prompts reales que existían cuando esto se unificó pasan por el runner y llegan byte a
  byte** (los tres que no, superan el techo del sistema y hay que partirlos). El arnés que lo
  verifica no vive en este repo: copia las series a un repo temporal y no toca los originales.

## 4. Estructura

```
Run-SessionPrompts.ps1        el producto
Install-SessionPrompts.ps1    lo instala y actualiza en otro repo
templates/                    lo que el instalador copia al destino
  README.md                   la referencia para los agentes del repo destino
  _plantillas/                moldes de serie y de prompt
  series-estado.txt           molde, no se pisa si ya existe en el destino
  session-prompts.config.json molde, no se pisa si ya existe en el destino
  prompt-instalacion-claude-md.md  el prompt de la sesion que corre la instalacion
tests/Run-Tests.ps1           suite, sin dependencias
tools/Start-FakeAnthropicApi.ps1  API falsa de Anthropic, para manejar al CLI real sin gastar cuota
tools/Measure-Limite5Horas.ps1    la medicion que la usa; se rehace cuando cambia el CLI
docs/analisis-de-versiones.md de dónde salió cada cosa, y qué se descartó
docs/gen-ejemplo-corrida.ps1  arma la captura de consola del ejemplo del README
docs/ejemplo-corrida.svg      esa captura, generada — no se edita a mano
CHANGELOG.md                  qué cambió en cada versión
```

**Los dos documentos que ve el repo destino** —`templates/README.md` y
`templates/prompt-instalacion-claude-md.md`— son parte del producto, no decoración: el primero es lo
que un agente lee para saber cómo escribir y correr una serie, y el segundo es lo que hace que el
andamiaje sea descubrible. Si cambiás una regla del runner, revisá si alguno de los dos la afirma.

## 5. Cómo se distribuye

El producto se instala y se actualiza **desde el release de GitHub** (`apanitsch/RunSessionPrompts`),
no desde una carpeta local: `Install-SessionPrompts.ps1 -FromRelease latest` para instalar, y
`Run-SessionPrompts.ps1 -Update` desde el repo donde ya está. El runner además chequea una vez por
día si hay una versión nueva y la ofrece — **nunca actualiza solo**, y si no hay conexión la corrida
sigue igual.

Eso implica que **una versión no existe hasta que el release está publicado**: el paso 5 del
procedimiento del [README](README.md#versionado-y-releases) no es opcional. Se usa el `.zip` del
código del tag, que GitHub arma solo; no hay que subir ningún archivo.

El repo del producto es **público**, así que todo eso funciona sin credenciales. El fallback a `gh`
que tienen el runner y el instalador queda por si alguna vez vuelve a ser privado, o para pasar el
límite de la API anónima.

## 6. Este repo no sabe dónde está instalado, y no tiene por qué

El producto es independiente de los repos que lo usan: no hay acá una lista de instalaciones, ni
nada que dependa de cómo esté armado un repo destino. Si hace falta saber qué versión tiene una
instalación, se mira allá — en su `.session-prompts-version` — o se corre
`Run-SessionPrompts.ps1 -Version`.

Donde todavía haya una copia vieja, sin marca de versión, el instalador **se niega a pisarla sin
`-Force`**, a propósito: puede tener algo propio. Migrar una copia así es una decisión de quien
mantiene ese repo, no de este.
