# ProTrainerPlus v2

Nueva versión del portal, publicada en paralelo en `https://atletas.headcoachleonardopablo.com/v2/`.

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
