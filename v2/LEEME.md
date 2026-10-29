# ProTrainerPlus v2

Nueva versión del portal. Desde el 28/10/2026 vive en la raíz `https://atletas.headcoachleonardopablo.com/` (el `index.html` principal); `/v2/` redirige ahí y el portal anterior quedó en `/anterior/`.

- Usa el mismo Supabase y el mismo login que el portal actual (`/`).
- No modifica `index.html`, ni las tablas `plans`, `sessions`, `profiles`, `comments` o `evidencias`. Los planes actuales de cada atleta se siguen viendo en el portal de siempre; la v2 muestra un acceso directo a ellos.
- Guarda lo nuevo en tablas con prefijo `pt_`:
  - tareas del calendario
  - biblioteca de ejercicios
  - plantillas
  - disposición y carga
  - mensajes y actividad

## Instalación (una sola vez)

1. Supabase → SQL Editor → New query → pega `supabase-v2.sql` → Run.
2. Publica esta carpeta `v2/` en la rama principal del repo `portal-atletas` (GitHub Pages la sirve sola).
3. Entra a `/v2/` con la cuenta del coach. La primera vez se cargan solas la biblioteca de ejercicios y las plantillas, armadas con los planes reales.

## Archivos

- `index.html` — panel del coach y vista del atleta (según el rol de quien entra).
- `supabase-v2.sql` — tablas nuevas y permisos (RLS). Se puede correr más de una vez.

## Editor de entrenamientos (29/10/2026)

- Cada ejercicio tiene botones − / + para series, reps, RIR, tempo y descanso, y un selector kg / lb.
- Tipos: Aislado, Biserie (2), Triserie (3), Superserie (2), Megaserie (4+) y Dropset. Se guardan en cada ejercicio como `link` (va seguido del siguiente), `gtype` y `drop`; el atleta los ve agrupados (A1, A2…).
- Una sesión ya asignada se edita desde su detalle (botón Editar); puede aplicarse a las siguientes sesiones iguales. Las sesiones editadas a mano no se sobrescriben al guardar el plan.
- Al guardar un plan se actualizan sus sesiones pendientes del calendario (casilla en el editor).
- Excel: `plantilla-entrenamiento.xlsx` (Plantillas → Descargar plantilla Excel / Subir Excel). También se lee la plantilla anterior `plantilla-plan.xlsx`. Cada plan se puede exportar a Excel y volver a cargar.

## Demo privado para coaches

- Se abre solo con el enlace `https://atletas.headcoachleonardopablo.com/#demo=<clave>`. El repo guarda únicamente el hash SHA-256 de la clave (`DEMO.HASH` en `index.html`); para cambiar la clave, genera una nueva y reemplaza el hash.
- No usa Supabase: todo vive en el navegador del visitante (localStorage), con 4 clientes ficticios, planes, historial, alimentación y medidas. Cada visitante tiene su propia copia; «Reiniciar demo» la borra.
- Funciona igual que la app real: crear clientes (genera correo y contraseña de demo), planes, tareas, Excel, vista del atleta.
