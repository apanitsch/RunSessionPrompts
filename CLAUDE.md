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
  prompt. Medido cuatro veces: dos independientes en los repos de origen (ChatNet y AtlasVDT), y dos
  acá contra un `.exe` nativo hecho para la prueba, la segunda con 21 payloads hostiles. El escapado
  manual quedó **sólo** para PowerShell 7.0–7.2, donde `$PSNativeCommandArgumentPassing` no existe.
- **Un `claude` que resuelve a un shim `.cmd`/`.bat` no sirve, y el runner no arranca.** Medido: por
  ese camino un prompt multilínea llega truncado en su primera línea, en silencio. El runner primero
  busca el `.exe` equivalente; si no hay, corta. No lo «arregles» agregando escapado: son reglas de
  `cmd.exe`, no de `CommandLineToArgvW`.
- **Todo esto tiene test contra un `.exe` nativo, y los tests están verificados por mutación** (no
  fijar el modo, aceptar el shim, escapar siempre y no escapar nunca ponen en rojo los casos que
  corresponden). Si tocás `Resolve-ComandoClaude`, `ConvertTo-NativeArg` o el bloque que fija el
  modo, corré la suite: es lo único que separa este script de degradar prompts en silencio.
- **`-Worktree` es opcional y viene apagado.** Buspack lo hacía siempre; la mayoría de los repos no
  lo necesita.
- **Las carpetas que empiezan con `_` no son series**, aunque tengan prompts numerados adentro. Es lo
  que permite que `_serie-de-ejemplo` muestre el formato completo sin ensuciar el menú.
- **El corte por tamaño es un error, no un truncado**, y **mide la línea de comandos completa**
  (ejecutable + flags + nombre de sesión + prompt escapado) contra el techo de Windows, no el largo
  crudo del prompt. Un número fijo se equivoca en las dos direcciones: está medido, y los dos casos
  aparecieron entre los prompts reales.
- **Los 439 prompts reales de los ocho repos pasan por el runner y llegan byte a byte** (los tres
  que no, superan el techo del sistema y hay que partirlos). El arnés que lo verifica no vive en
  este repo: copia las series a un repo temporal y no toca los de origen.

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
docs/analisis-de-versiones.md de dónde salió cada cosa, y qué se descartó
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

## 6. Dónde está instalado

Los ocho repos de origen (Agentada, AtlasVDT, Buspack, Chat, Chat-usuarios-meta, ChatNet,
ncore-wingo, SRT.Kairos) todavía tienen **su copia vieja, sin marca de versión**. El instalador se
niega a pisarlas sin `-Force`, a propósito: cada una puede tener algo propio. Migrarlas es una
decisión de Andrés, repo por repo.
