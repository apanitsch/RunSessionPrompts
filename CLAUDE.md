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

- **El escapado manual de comillas está condicionado, no siempre.** Bajo `pwsh` con un `claude.exe`
  nativo, PowerShell ya escapa y sumar escapado encima **corrompe** cada `"` del prompt. Medido dos
  veces, independientemente (ChatNet y AtlasVDT, el mismo día). El script decide una vez al arrancar
  e **imprime el motivo**. Si aparece evidencia nueva que lo contradiga, frená y reportá.
- **`-Worktree` es opcional y viene apagado.** Buspack lo hacía siempre; la mayoría de los repos no
  lo necesita.
- **Las carpetas que empiezan con `_` no son series**, aunque tengan prompts numerados adentro. Es lo
  que permite que `_serie-de-ejemplo` muestre el formato completo sin ensuciar el menú.
- **El corte por tamaño del prompt es un error, no un truncado.** Un prompt truncado en silencio es
  peor que una corrida que no arranca.

## 4. Estructura

```
Run-SessionPrompts.ps1        el producto
Install-SessionPrompts.ps1    lo instala y actualiza en otro repo
templates/                    lo que el instalador copia al destino
  _plantillas/                moldes de serie y de prompt
  series-estado.txt           molde, no se pisa si ya existe en el destino
  session-prompts.config.json molde, no se pisa si ya existe en el destino
tests/Run-Tests.ps1           suite, sin dependencias
docs/analisis-de-versiones.md de dónde salió cada cosa, y qué se descartó
CHANGELOG.md                  qué cambió en cada versión
```

## 5. Dónde está instalado

Los ocho repos de origen (Agentada, AtlasVDT, Buspack, Chat, Chat-usuarios-meta, ChatNet,
ncore-wingo, SRT.Kairos) todavía tienen **su copia vieja, sin marca de versión**. El instalador se
niega a pisarlas sin `-Force`, a propósito: cada una puede tener algo propio. Migrarlas es una
decisión de Andrés, repo por repo.
