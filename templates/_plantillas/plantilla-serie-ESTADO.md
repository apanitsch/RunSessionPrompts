<!--
PLANTILLA del ESTADO.md de una serie. Copiala a `<serie>/ESTADO.md`.
- Es la BITACORA VIVA: la sesion que cierra la actualiza y commitea.
- Reemplaza TODO lo que esta entre «comillas angulares».
- Este archivo NO empieza con numero, asi que el runner no lo ejecuta.
- Borra este comentario antes de commitear.
-->

# ESTADO — Serie «nombre-serie»

Estado vivo de la serie. Cada sesión lo actualiza al cerrar: qué entró, **contra qué se verificó**, y
el commit.

## Progreso

| # | Sesión | Estado | Commit | Verificado contra |
| --- | --- | --- | --- | --- |
| 01 | «Título» | ⬜ pendiente | — | — |
| 02 | «Título» | ⬜ pendiente | — | — |

Leyenda: ⬜ pendiente · 🟡 en curso · ✅ hecho · 🔒 bloqueada.

## Contexto de arranque (planificación, «fecha»)

«El hallazgo o la decisión que define la serie, en dos o tres frases. Los `Fn` y `Dn` completos están
en el [`README.md`](README.md) — ninguna sesión necesita re-investigarlos ni re-litigarlos.»

## Bitácora

«Una entrada por sesión al cerrarla. Qué entró, cómo se verificó, qué se decidió que el prompt había
dejado abierto, y lo que se encontró en el camino y no estaba previsto.»

### Sesión 01 — «Título» («fecha»)

- **Qué entró:** «archivos, proyectos, entidades o migraciones nuevos o cambiados.»
- **Verificación:** «build y tests con los NÚMEROS: cuántos pasaron, cuántos fallaron, cuántos se
  saltearon y por qué. "Verde" no es un número.»
- **Documentación:** «qué se actualizó, o "sin cambios" con el motivo.»
- **Decisiones:** «qué se escribió y dónde, o "ninguna decisión que cueste revertir".»

## Decisiones que la sesión tuvo que tomar

«Lo que el prompt dejó abierto y la sesión resolvió sola, con el porqué. Si alguna cuesta revertir,
acá va sólo el puntero: el cuerpo vive donde el repo guarde sus decisiones.»

## Riesgos abiertos

| # | Riesgo | Dónde se cierra |
| --- | --- | --- |
| R1 | «Riesgo abierto, con dueño» | «sesión NN / otra serie / fuera de alcance» |

> Un **riesgo abierto** va acá. Una **trampa ya pagada** no: va al archivo de trampas del repo, que es
> lo único transversal. Un **hecho verificado** tampoco: va como `Fn` al [`README.md`](README.md) de
> la serie.
