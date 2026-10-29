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
- No usa Supabase: todo vive en el navegador del visitante (localStorage). Arranca en limpio, sin clientes; solo trae la biblioteca de ejercicios y 3 plantillas base sin nombres de atletas. Cada visitante tiene su propia copia; «Reiniciar demo» la borra.
- Funciona igual que la app real: crear clientes (genera correo y contraseña de demo), planes, tareas, Excel, vista del atleta.

## Eliminar perfil (lo hace la clienta / cliente o el coach)

- En **Mi perfil**, al final, hay un enlace pequeño «Eliminar mi perfil» con dos confirmaciones (casilla + escribir ELIMINAR).
- El coach también puede eliminar a un cliente: Perfil del cliente → «🗑️ Eliminar cliente», con los mismos pasos. Además borra el plan personal del cliente en las plantillas.
- Requiere correr una vez `eliminar-cuenta.sql` en Supabase → SQL Editor. Crea las funciones `delete_my_account()` y `coach_delete_client(correo)` y el permiso para que cada quien borre sus archivos del bucket `evidencias`.
- Borra: tareas, cargas, medidas, foto, ciclo, alimentación, mensajes, actividad, avisos, ficha, plan, sesiones, comentarios, evidencias (filas y archivos), perfil y el usuario de acceso. El coach no puede borrarse por esta vía.
- Después la persona puede registrarse otra vez con el mismo correo y empieza en blanco.

## Cargar desde archivo (ficha del cliente)

- Botón **Cargar desde archivo** en la ficha de cada cliente. Solo acepta Excel (.xlsx/.xls, se valida el contenido, no solo la extensión) con el formato de `plantilla-entrenamiento.xlsx`.
- Lee: hojas de días (plan), «Datos del plan», «Datos del cliente» y «Nutrición». Muestra una vista previa y el coach elige qué aplicar.
- El plan se asigna al cliente y se programa en su calendario desde la fecha elegida (L–V o L–S); reemplaza las sesiones pendientes del plan anterior y conserva las completadas.
- También lee la plantilla anterior `plantilla-plan.xlsx`.

## Trabajo aeróbico

- Categoría «Aeróbico / cardio» en el editor de plan y botón «Agregar bloque aeróbico» en el editor de sesión (también cuenta cualquier bloque llamado Cardio/Aeróbico).
- En esos ejercicios se cambian series/reps/RIR/tempo/descanso por: Máquina, Tiempo (min), Inclinación (solo caminadora), Zona Karvonen (Z1–Z5) y FCE en lpm (se calcula con la edad y la FC en reposo del cliente).
- En el plan, cada fase lleva minutos y zona. El atleta lo ve con 🏃 y lo marca como «Hecho».
- Excel: Grupo = Aeróbico; en F1–F4 Series van los minutos y en F1–F4 Reps la zona; columnas Máquina e Inclinación.

## Aviso de privacidad (LFPDPPP 2025)

- Aviso integral público: `aviso-de-privacidad/index.html` → atletas.headcoachleonardopablo.com/aviso-de-privacidad/ (fuente única; la app lo carga dentro de la ventana).
- Cada cliente (nuevo o actual) ve la ventana al entrar hasta aceptar la versión vigente (`PRIVACY.version` en index.html). Aceptar exige la casilla de consentimiento expreso para datos sensibles (art. 8); finalidades secundarias opcionales. Cancelar bloquea el acceso y permite salir.
- La aceptación se guarda en `pt_evo` (kind `privacy`, versión, fecha, secundarias, navegador). El coach ve el estado en la ficha del cliente.
- Para publicar una nueva versión: edita la página del aviso, sube `PRIVACY.version` y su fecha; todos los clientes lo volverán a aceptar.

## Multi-coach: «Soy coach / Soy atleta» y catálogo de coaches

- Requiere correr una vez `multi-coach.sql` (después de los otros scripts). Antes de correrlo, la app funciona como siempre (un solo coach).
- **Crear cuenta** (en la app nueva, desde «Entrar» o `/#crear-cuenta`): elige «Soy atleta» o «Soy coach». El coach queda activo al instante con 14 días de prueba (`pt_coaches.trial_ends_at`); el cobro automático está pendiente.
- **Cada coach ve solo a sus clientes**: el acceso a las tablas `pt_*` depende del vínculo activo en `pt_links`. Plantillas por coach; biblioteca compartida (solo el coach principal borra).
- **Cliente sin coach** → ve el catálogo (`pt_coach_profiles`) y envía una solicitud; el coach la acepta o rechaza en «Solicitudes». Al darlo de alta el coach: si la cuenta es nueva queda vinculada; si ya existía, se le envía una invitación (evita que un coach tome clientes de otro).
- **Mi perfil de coach**: ficha pública del catálogo (foto, título, especialidades, ciudad, modalidad, precios, bio, sitio, Instagram, visible u oculto).
- Los clientes actuales quedan asignados a coach@headcoachleonardopablo.com. Las tablas del portal anterior no cambian y siguen siendo solo del coach principal.
