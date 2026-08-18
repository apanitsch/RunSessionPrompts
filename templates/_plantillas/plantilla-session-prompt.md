<!-- modelo-sugerido: sonnet -->
<!-- effort-sugerido: high -->

<!--
PLANTILLA de prompt de sesion. Copiala a `<serie>/NN-descripcion.md`.
- Reemplaza TODO lo que esta entre «comillas angulares».
- Borra las secciones que no apliquen, PERO no borres una para no tener que contestarla.
- El prompt tiene que ser AUTOCONTENIDO: se ejecuta con contexto fresco, sin la conversacion previa.
  Un prompt que solo funciona "si estabas en la conversacion anterior" es un prompt roto.
- LAS DOS MARCAS DE ARRIBA las lee `Run-SessionPrompts.ps1`:
    * `modelo-sugerido`: `sonnet` u `opus`.
    * `effort-sugerido`: `low`, `medium`, `high`, `xhigh` o `max`.
  El modelo y el effort de la corrida son el TOPE. Si la sesion pide MENOS o lo mismo, arranca sola;
  si pide MAS, el script PARA Y PREGUNTA antes de la primera sesion. Si borras una marca, esa
  dimension corre con el tope. Un valor que no exista CORTA con un error, no se ignora.
  Regla practica: la sesion que ESCRIBE con el criterio ya resuelto aca va con `sonnet` y poco
  effort; la que JUZGA va con `opus`, y con `xhigh` o `max` si ademas el problema es dificil.
- Borra este comentario (no las marcas de modelo y effort) antes de commitear.
-->

# Sesión «NN» — «Título corto de la sesión»

**Serie:** [`«nombre-serie»`](README.md) · **Estado:** [`ESTADO.md`](ESTADO.md)
· **Reglas del repo:** [`CLAUDE.md`](«ruta relativa al CLAUDE.md de la raíz»)

## Objetivo

«Una o dos frases: qué entrega esta sesión y por qué existe. Si es de documentación o de decisión y
casi no toca código, decilo acá y explicá qué desbloquea para las que siguen.»

## Antes de empezar

Leé, en este orden:

- **El [`README.md`](README.md) de la serie completo** — los hallazgos verificados (`F1`–`Fn`) y las
  decisiones fijadas (`D1`–`Dn`). Esta sesión los **usa**, no los re-descubre ni los re-litiga.
- [`ESTADO.md`](ESTADO.md) — el tablero, los riesgos `Rn` y qué dejó la sesión anterior.
- **El `CLAUDE.md` de la raíz** — «qué secciones importan para esta sesión».
- «`docs/«archivo».md`» — «qué gobierna de esta sesión».

## Alcance

«Numerá el trabajo concreto, un ítem por entregable. Sé específico: nombres de tipos, de archivos, de
migraciones, de endpoints, de campos.»

### 1. «Entregable»

«Detalle.»

### 2. «Entregable»

«…»

## Qué queda decidido, y dónde se escribe

| Qué | Dónde va |
| --- | --- |
| «La decisión que cuesta revertir» | «Archivo propio en `docs/decisiones/`, o donde el repo las guarde, con contexto, decisión, alternativas descartadas y por qué.» |
| «El acuerdo de alcance que muere con la serie» | Como `Dn` en el [`README.md`](README.md) de la serie. |

- **Decisiones ya firmes en juego:** ««cuáles» / ninguna». Están decididas: si aparece **evidencia
  nueva** que contradice una, **frená y reportá**, no la cambies por tu cuenta.

## Fuera de alcance

- «Lo que NO se toca en esta sesión, y de quién es. Si te tienta hacerlo "ya que estás": no.»
- **Re-litigar las decisiones fijadas** de la serie.

## Cómo se verifica (cierre)

- **El comando de build y el de tests, con los números pegados** — no la conclusión:

  ```bash
  «comando de build»
  ```

  ```bash
  «comando de tests»
  ```

  «Lo que esos comandos necesitan para correr: base de datos, variables de entorno, servicios.»
- «El chequeo específico de tu rebanada, si tenés uno más angosto para iterar.»
- **Relectura honesta:** ¿un agente que lea sólo lo que produjo esta sesión entiende el porqué, sin
  haber tenido esta conversación? ¿Quedó algo que haya que "hacer a mano después"? Si quedó, **no está
  terminado**: automatizalo o dejalo escrito como tarea explícita con todo lo necesario para ejecutarla.

## Doc al día (paso obligatorio)

- [`ESTADO.md`](ESTADO.md) — fila «NN» → ✅, qué entró, **contra qué se verificó con los números**, el
  commit, y el estado de los riesgos `Rn` que tocaste.
- «El archivo de trampas del repo (`docs/gotchas.md` o equivalente)» — ¿tu sesión **pagó una trampa**
  que otra podría volver a pagar? Anotala: síntoma → causa → qué hacer → dónde se vio. Un riesgo
  abierto NO va acá: va como `Rn` en `ESTADO.md`.
- **`CLAUDE.md`** — si agregaste un proyecto, un comando o una forma de correr algo, **en el mismo
  commit**. Si no hizo falta cambiar nada, **decilo explícitamente** en `ESTADO.md`.
- Commiteá. **El mensaje de commit es el registro del porqué**: escribilo pensando en quien lea el log
  sin haber estado en esta conversación.
