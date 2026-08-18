<!--
PLANTILLA del README de una serie. Copiala a `<serie>/README.md`.
- Reemplaza TODO lo que esta entre «comillas angulares».
- El README es el contexto COMPARTIDO: lo que vale para TODAS las sesiones de la serie.
- Los hallazgos (Fn) y decisiones (Dn) van aca para que ninguna sesion los re-investigue ni re-litigue.
- Este archivo NO empieza con numero, asi que el runner no lo ejecuta.
- Borra este comentario antes de commitear.
-->

# Serie de sesiones — «Título de la serie»

«Un párrafo: qué deja andando esta serie que hoy no anda, y cuál es el resultado observable cuando
cierra. Nombrá las piezas por como se llaman en el repo.»

## Punto de partida

- «Qué existe ya en el repo y qué no. Sé concreto: qué proyectos, qué entidades, qué migraciones, qué
  corre y qué todavía no.»
- «Qué documento del repo describe lo que la serie construye, con la sección.»

## Lo que gobierna desde afuera

Esta serie **no decide** estas cosas: las obedece.

- **Decisiones firmes en juego** (las del `CLAUDE.md` de la raíz): ««cuáles»». Si aparece evidencia
  nueva que contradice una, **frená y reportá**.
- **Decisiones ya escritas** que aplican: ««archivo»», «…».
- **Vocabulario:** «qué nombres toca esta serie y cuáles son los correctos».

## Hallazgos ya verificados — no los re-investigues

«Comprobados durante la planificación. Ninguna sesión necesita volver a comprobarlos. Cada uno con su
cita: `archivo:línea` si es del repo, versión del paquete si es de una dependencia, enlace y fecha si
es de una especificación externa.»

### F1 — «Hallazgo» ✅ verificado

«Qué se comprobó, contra qué, y por qué importa para esta serie.»

### F2 — «Hallazgo» ✅ verificado

«…»

## Decisiones fijadas — no re-litigar

«Validadas con el owner. Cada una con su porqué y con lo que se descartó.»

> **Ojo con dónde vive cada una.** Un `Dn` es un acuerdo de **alcance local** que muere con la serie.
> Una decisión que **cuesta revertir** no se queda acá: se escribe donde el repo guarde sus decisiones,
> y el `Dn` la referencia.

- **D«n» — «Decisión».** «Por qué. Qué se descartó y por qué.»

## Reglas duras de la serie

Valen para **todas** las sesiones.

1. **No dejes trabajo manual pendiente.** Nada de "correr esto a mano" ni "configurar X después". Si
   hay que hacerlo, automatizalo; si todavía no se puede, dejalo como tarea explícita con todo lo
   necesario para ejecutarla.
2. **Ni un secreto al repo**, ni siquiera de desarrollo.
3. **Al cerrar cada sesión:** build y tests verdes **con los números pegados**, documentación al día y
   `ESTADO.md` actualizado.
4. «Regla propia de la serie.»

## Sesiones

| # | Sesión | Entrega | Modelo |
| --- | --- | --- | --- |
| 01 | [«Título»](01-«descripcion».md) | «Qué deja lista» | «opus / sonnet» |
| 02 | [«Título»](02-«descripcion».md) | «…» | «…» |

«Aclará las dependencias: cuáles son paralelizables y cuál necesita a cuál.»

## Tooling y convenciones

- **Build y tests:** ««comandos», y qué necesitan para correr».
- **Repositorio:** ««owner/repo»». «Decí acá si la serie corre directo sobre la rama principal, por
  rama y PR, o aislada en su propio worktree (`-Worktree` del runner).»
- «Idioma de la documentación, los comentarios y los commits.»
