# `_plantillas/` — moldes de una serie

Copiá estos archivos para arrancar una serie o una sesión nueva. **No son ejecutables**: esta carpeta
empieza con `_`, así que `Run-SessionPrompts.ps1` la ignora y nunca se confunde con una serie real.

| Plantilla | Copiala a | Qué es |
|---|---|---|
| [`plantilla-serie-README.md`](plantilla-serie-README.md) | `<serie>/README.md` | Contexto compartido de la serie: hallazgos `Fn`, decisiones `Dn`, reglas duras, tabla de sesiones. |
| [`plantilla-serie-ESTADO.md`](plantilla-serie-ESTADO.md) | `<serie>/ESTADO.md` | Bitácora viva: tablero de progreso, bitácora por sesión, riesgos `Rn`. |
| [`plantilla-session-prompt.md`](plantilla-session-prompt.md) | `<serie>/NN-descripcion.md` | El prompt autocontenido de una sesión. |

## Cómo usarlas

1. Creá la carpeta de la serie al lado del runner: `<raíz de series>/<mi-serie>/` (`kebab-case`).
2. Copiá `plantilla-serie-README.md` → `<serie>/README.md` y `plantilla-serie-ESTADO.md` →
   `<serie>/ESTADO.md`. Completá el contexto compartido.
3. Por cada sesión, copiá `plantilla-session-prompt.md` → `<serie>/NN-descripcion.md`. **El número
   al principio es lo que hace que el archivo sea un prompt ejecutable**: un `.md` sin número (como
   `README.md` o `ESTADO.md`) el runner lo ignora.
4. Reemplazá **todos** los marcadores `«…»`. Borrá las secciones que no apliquen — pero no borres una
   sólo para no tener que contestarla.

## Las dos reglas que no son de estilo

- **Cada prompt es autocontenido.** Se ejecuta con contexto fresco, sin la conversación previa y sin
  memoria de las sesiones anteriores. Un prompt que sólo se entiende "si estabas en la conversación
  anterior" es un prompt roto: lo que la sesión necesita saber está en el prompt, en el `README.md` de
  la serie, en el `ESTADO.md` o en un archivo del repo que el prompt nombre explícitamente.
- **El modelo y el effort se declaran en el prompt.** Las marcas `<!-- modelo-sugerido: sonnet -->`
  y `<!-- effort-sugerido: xhigh -->` de las primeras líneas las lee el runner. Lo que elegiste para
  la corrida es el **tope**: la sesión que pide menos arranca sola, la que pide más se confirma antes
  de empezar. Regla práctica: una sesión que **escribe** con el criterio ya resuelto va con `sonnet`
  y poco effort; una que **juzga** (decidir cómo se modela algo, resolver algo abierto, escribir una
  decisión que cuesta revertir) va con `opus`, y con `xhigh` o `max` si además el problema es
  difícil. Sin marca, esa dimensión corre con el tope de la corrida.
