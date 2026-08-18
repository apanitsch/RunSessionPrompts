# De dónde sale este script: las ocho versiones que se unificaron

Relevado el 2026-08-18 sobre `C:\Users\andre\source\repos`. Ocho copias de `Run-SessionPrompts.ps1`,
todas bajo `docs/session-prompts/` o `Docs/session-prompts/`, todas distintas entre sí.

| Repositorio | Ruta | Líneas | Última modificación |
| --- | --- | ---: | --- |
| ChatNet | `docs/session-prompts/` | 589 | 2026-08-14 |
| Agentada | `docs/session-prompts/` | 558 | 2026-08-14 |
| Buspack | `Web.Bpk/Docs/session-prompts/` | 499 | 2026-07-30 |
| Chat | `Docs/session-prompts/` | 489 | 2026-08-18 |
| AtlasVDT | `docs/session-prompts/` | 453 | 2026-08-18 |
| Chat-usuarios-meta | `Docs/session-prompts/` | 434 | 2026-08-07 |
| ncore-wingo | `Docs/session-prompts/` | 320 | 2026-07-27 |
| SRT.Kairos | `docs/session-prompts/` | 250 | 2026-07-22 |

## La línea evolutiva

Se ve claro que es un script que se fue copiando hacia adelante:

1. **SRT.Kairos** (22 de julio) es el ancestro. Menú de series, `-StartFrom`, `-FullAuto`, Remote
   Control con nombre de sesión, `Ctrl+C` que corta todo, escapado de comillas, modelo fijo
   (`claude-opus-4-8`) escrito en el código.
2. **ncore-wingo** (27 de julio) agrega el menú de modelo y el de effort.
3. **Chat-usuarios-meta** y **Chat** (agosto) agregan el modelo sugerido por prompt, la exclusión de
   las carpetas `_` y la nota de encoding.
4. **AtlasVDT** y **Chat** (18 de agosto, el mismo día) llegan por caminos distintos a la misma
   corrección: el escapado manual de comillas **no** se aplica siempre.
5. **Agentada** y **ChatNet** (14 de agosto) agregan `series-estado.txt` y el plan impreso antes de
   arrancar.
6. **Buspack** (30 de julio) va por una rama propia: aislamiento por git worktree. No tiene nada de
   lo de los puntos 4 y 5, y es la única que tiene worktrees.

Ninguna es superconjunto de las demás. La unificada sí.

## Qué aportó cada una

### ChatNet — la base

Es la más completa y es el esqueleto de la unificada: menús, `series-estado.txt`, modelo sugerido,
plan impreso, corte por tamaño de prompt, y la mejor versión de la detección de escapado
(`Test-NecesitaEscapadoNativo`, que además **imprime el motivo** de lo que decidió). Trae la tabla de
mediciones más completa —linea de comandos cruda del proceso hijo vía `Win32_Process.CommandLine`,
parseada con `CommandLineToArgvW`— y la corrección explícita de una afirmación anterior que era
falsa.

### Buspack — el aislamiento por worktree

Lo único que aporta y lo más grande que aporta nadie: cada serie corre en su propio git worktree, con
rama nueva desde una rama base, para no mover el piso bajo el sitio de IIS local. Vino entero:
helpers de normalización de rutas, `Get-MainWorktree` (robusto aunque el script se corra desde adentro
de un worktree), reutilización del worktree al reanudar, la guarda contra crear el worktree adentro
del checkout principal, y las instrucciones de merge y limpieza al cerrar.

En la unificada pasó a ser **opcional** (`-Worktree`) y sin rama base cableada: Buspack tenía
`Features-TMS` fija en el código, que es exactamente la clase de cosa que ahora vive en el
`session-prompts.config.json` del repo.

### Chat — las carpetas `_` y las notas de intérprete

- **Excluir las carpetas que empiezan con `_`.** Las demás versiones dependían de que la carpeta de
  plantillas no numerara sus archivos; acá `_serie-de-ejemplo` **sí** trae `01-`/`02-` para mostrar
  el formato completo, y aun así no aparece como serie. Es la regla correcta.
- La **nota de intérprete** (`pwsh`, nunca `powershell`) y la **nota de encoding** (el `.ps1` en ASCII
  puro a propósito), las dos con su porqué.
- Trata `$PSNativeCommandArgumentPassing` nulo como `Legacy`, que es lo que corresponde en 7.0–7.2,
  donde la variable todavía no existe.

### AtlasVDT — la segunda medición del escapado

Llegó a la misma conclusión que ChatNet el mismo día y por su cuenta, con una tabla de mediciones que
separa los tres casos (`.exe` nativo en modo Windows, shim `.cmd`, modo Legacy) y dice explícitamente
cuál está medido y cuál inferido de `about_Parsing`. Dos mediciones independientes que coinciden es la
razón por la que en la unificada esto es una decisión cerrada y no una duda.

### Agentada — los mensajes cuando no hay nada que correr

Aporta el manejo del caso vacío del menú, que las demás resolvían peor: distingue "no hay series
pendientes, hay N terminadas, usá `-Todas`" de "todavía no hay ninguna serie". Es un detalle chico que
en las otras versiones dejaba al usuario frente a un `Read-Host` pelado.

### Chat-usuarios-meta, ncore-wingo, SRT.Kairos — nada propio

Son ancestros: todo lo suyo está contenido en las versiones más nuevas. Se leyeron completas para
confirmarlo. Lo único exclusivo que quedó de SRT.Kairos es histórico —el modelo `claude-opus-4-8`
cableado— y no tiene sentido conservarlo.

## Lo que no venía de ninguna, y se agregó

La divergencia entre las ocho copias no fue casual: cada repo tenía que **editar el script** para
adaptarlo. La rama base de Buspack, el `.EXAMPLE` con el nombre de una serie real, el comentario que
nombra el repo. Un producto reutilizable tiene que hacer que eso no haga falta:

- **`session-prompts.config.json`** por repo, para lo que difería: rama base, prefijo de rama,
  worktree sí/no, modelo, effort, permisos.
- **`-SeriesRoot` y descubrimiento automático** de la carpeta de series, para que el runner también
  pueda vivir en un solo lugar y servir a todos los repos.
- **`Install-SessionPrompts.ps1`**, con marca de versión y hash, para que actualizar treinta copias
  no vuelva a ser copiar y pegar — y para que se note cuando una copia fue tocada a mano.
- **`-DryRun` y `-ClaudeCommand`**, que son lo que hace posible la suite de tests: correr el runner
  de verdad sin lanzar sesiones de verdad.
- **Tests**. Ninguna de las ocho tenía uno solo.

## Diferencias que se resolvieron eligiendo

| Punto | Qué hacían | Qué quedó |
| --- | --- | --- |
| Escapado de comillas | 4 versiones escapaban siempre (heredado de 5.1); 3 lo condicionaban | Condicionado, con el motivo impreso. Escapar siempre corrompe bajo `pwsh` + `claude.exe` |
| Effort | Buspack no lo pasaba (confiaba en el default del modelo) | Se pasa siempre explícito: la corrida no depende de que el default no cambie |
| Carpetas `_` | 2 versiones las excluían; 6 no | Se excluyen |
| Directorio de trabajo | Raíz del repo (7) o del worktree (Buspack) | Las dos, según `-Worktree` |
| Rama base del worktree | `Features-TMS` cableada | La rama actual del repo, o la que diga la configuración |
| Modelos | `claude-opus-4-8` (SRT.Kairos), `opus`/`sonnet` = 5 (las demás) | `claude-opus-5` y `claude-sonnet-5`, en una tabla fácil de extender |
