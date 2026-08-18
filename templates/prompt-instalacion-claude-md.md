<!--
Este es el prompt que Install-SessionPrompts.ps1 le pasa a Claude Code al terminar de instalar,
para que el andamiaje de series quede DESCUBRIBLE en el CLAUDE.md del repo destino.

El instalador reemplaza los marcadores antes de mandarlo:
  {{RUTA_SERIES}}   ruta absoluta de la carpeta de series instalada
  {{RUTA_README}}   ruta absoluta del README.md que quedo ahi
  {{RUTA_RUNNER}}   ruta absoluta del Run-SessionPrompts.ps1 instalado
  {{RUTA_REPO}}     raiz del repo destino
  {{VERSION}}       version instalada

Se puede editar: es parte del producto, y el instalador lo lee de disco cada vez.
Este comentario NO se manda (el instalador lo saca).
-->

Acabo de instalar en este repositorio el andamiaje de **series de sesiones** de Claude Code
(`Run-SessionPrompts.ps1`, versión {{VERSION}}). Tu tarea es dejarlo **descubrible** para cualquier
agente que trabaje en este repo, y **corregir** lo que el `CLAUDE.md` ya diga al respecto si quedó
desactualizado.

Es una tarea de documentación: no toques el runner ni las series.

## 1. Leé, en este orden

1. **{{RUTA_README}}** — el README del andamiaje, completo. Ahí está qué es, cómo se corre, y los
   criterios de modelo y effort. Es la fuente de verdad: tu trabajo es **apuntar** a ese archivo, no
   copiar su contenido.
2. **El `CLAUDE.md` de la raíz de este repo** ({{RUTA_REPO}}), completo, y cualquier otro `CLAUDE.md`
   del repo que hable de sesiones, prompts o de este script.
3. Mirá qué hay en **{{RUTA_SERIES}}**: si ya existen series, el repo venía usando esto de antes.

## 2. Dejá una sección en el `CLAUDE.md` de la raíz

Corta —entre cinco y quince líneas—, en el lugar donde el archivo habla de cómo se trabaja en el
repo (comandos, procedimientos, herramientas), no al final por descarte. Tiene que decir:

- **qué es**: series de prompts numerados que se corren en sesiones de contexto limpio, una por vez;
- **para qué sirve**: partir un trabajo grande en sesiones que se pueden lanzar y dejar corriendo
  sin quedarse en la máquina;
- **dónde vive**: `{{RUTA_SERIES}}`, en ruta relativa al repo;
- **cómo se corre**: `pwsh -File <ruta>\Run-SessionPrompts.ps1` — **`pwsh`, nunca `powershell`**;
- **que el README de esa carpeta es la referencia**, y que ahí están los criterios para elegir
  modelo y effort de cada sesión;
- **que el runner no se edita**: es un producto versionado que se instala; lo que este repo necesite
  cambiar va al `session-prompts.config.json`.

Escribila **en el idioma y con el registro del `CLAUDE.md` que ya existe**. Si el archivo numera sus
secciones, seguí la numeración. Si no existe ningún `CLAUDE.md` en la raíz, creá uno con sólo esa
sección, breve.

## 3. Corregí lo que haya quedado viejo

Este repo puede tener afirmaciones de una versión anterior del script, o de una copia que vivía sólo
acá. **Buscalas y corregilas** — en el `CLAUDE.md`, y en cualquier `README.md` o documento del repo
que describa este andamiaje. Estas son las que cambiaron; verificá cada una contra
{{RUTA_README}} y contra el encabezado del propio runner:

- **`powershell -File ...`** → es `pwsh -File ...`. El runner exige PowerShell 7 y falla con error si
  se corre con la 5.1. Si algún documento, script o tarea del repo lo invoca con `powershell`,
  corregilo.
- **"el script escapa las comillas siempre"** → ya no. Fija el modo de pasaje de argumentos en
  `Standard` y deja que PowerShell escape; escapar a mano encima **corrompe** el prompt.
- **"los prompts se cortan en 30000 caracteres"** → el corte mide la **línea de comandos completa**
  contra el techo de Windows, no el largo crudo del prompt.
- **"el modelo es fijo" / un id de modelo viejo** (por ejemplo `claude-opus-4-8`) → el modelo es del
  menú o del parámetro, y **cada prompt puede sugerir el suyo** con `<!-- modelo-sugerido: ... -->`.
- **"el effort es de la corrida"** → ahora **cada prompt puede sugerir el suyo** con
  `<!-- effort-sugerido: ... -->`, y el de la corrida funciona como tope.
- **"cada serie corre en un worktree"** → el aislamiento por worktree es **opcional** (`-Worktree`) y
  viene apagado.
- **Cualquier instrucción de editar el script** para adaptarlo a este repo → eso ahora va al
  `session-prompts.config.json`.

Si alguna de esas afirmaciones no está en el repo, no la agregues: la lista es de cosas a
**corregir si aparecen**, no de cosas a documentar.

## 4. Cerrá

- No dupliques en el `CLAUDE.md` lo que ya dice el README del andamiaje: apuntá.
- No toques `Run-SessionPrompts.ps1`, ni `_plantillas/`, ni ninguna serie existente.
- Al terminar, **decime en dos o tres líneas qué cambiaste y qué afirmaciones viejas corregiste**, o
  que no había ninguna.
- Dejá los cambios en el working tree, sin commitear: los revisa una persona.
