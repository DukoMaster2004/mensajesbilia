# Mensajes — web de estudio

Aplicación React para explorar el catálogo en español de mensajes de William Branham y hacer preguntas en un chat con respuestas fundamentadas en pasajes del catálogo.

## Requisitos

- Node.js 20 o posterior
- Una clave de Google Gemini para habilitar el chat con IA

## Desarrollo local

1. Instala las dependencias: `npm install`
2. Copia `.env.example` a `.env` y coloca tu clave de Gemini en `GEMINI_API_KEY`. El servidor carga `.env.local` y `.env`; no guardes claves en el código ni en el navegador.
3. Inicia la aplicación: `npm run dev`
4. Abre la URL que muestra el servidor (por defecto `http://localhost:5173`).

Sin la variable `GEMINI_API_KEY`, puedes navegar y leer el catálogo, pero el chat mostrará que falta configurar el servicio.

## Producción

Ejecuta `npm run build` y luego inicia el servidor con `GEMINI_API_KEY` configurada usando `npm start`. El servidor sirve la aplicación compilada y mantiene las solicitudes de Gemini en el backend.

El catálogo se sirve de forma paginada y los textos completos se cargan por mensaje para no descargar los 105 MB del archivo al abrir la web.

## Estudio compartido

En cada mensaje puedes compartir, marcar favoritos, resaltar (4 colores, incluso fragmentos elegidos manualmente) y añadir notas por párrafo o por mensaje. Las secciones **Favoritos**, **Notas** y **Resaltados** reúnen estos elementos.

Los mensajes y la Biblia son públicos. Cualquier persona puede iniciar sesión con Google para guardar sus propios favoritos, notas, notas múltiples, resaltados y conversación. Cada cuenta solo puede leer y modificar sus propios datos; los datos antiguos compartidos siguen visibles como lectura pública. El tema y el tamaño del texto se guardan localmente.

Para activar cuentas de Google y sincronización:

1. En Supabase, ejecuta [`supabase/shared_page_state.sql`](./supabase/shared_page_state.sql) en el SQL Editor. La actualización conserva las filas antiguas como datos públicos de solo lectura y agrega separación por cuenta.
2. En Google Cloud Console, configura la pantalla de consentimiento OAuth y crea un ID de cliente OAuth de tipo **Aplicación web**. Registra la URL de callback como URI de redirección autorizada. En local es `http://localhost:5173/api/auth/google/callback`; para producción usa `https://TU-DOMINIO/api/auth/google/callback`.
3. En `.env.local` (local) y en Vercel **Settings → Environment Variables** (Production/Preview) configura `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` y `AUTH_SESSION_SECRET`. Genera este último con `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`. En Vercel, `GOOGLE_REDIRECT_URI` debe ser exactamente la URL callback de producción.
4. Reinicia el servidor local o despliega de nuevo en Vercel después de guardar las variables. La sesión usa una cookie `HttpOnly` de 12 horas. No publiques los secretos ni los pongas en el código del navegador.

Los datos guardados anteriormente en Supabase permanecen visibles públicamente, pero las nuevas modificaciones quedan en el espacio de la cuenta que inició sesión. Las copias locales se separan por cuenta en `localStorage`.

## Biblia

Sección "Biblia" (debajo de Mensajes): los 66 libros en Reina-Valera 1960 (`Resources/biblia_rv1960.json`), con navegación por libro/capítulo, búsqueda por palabra o referencia (`Juan 3:16`) y compartir versículos. La **IA de la Biblia** solo muestra versículos reales del archivo; el modelo únicamente elige y explica brevemente.

Variable opcional en `.env`: `GEMINI_BIBLE_API_KEY` (si falta, usa `GEMINI_API_KEY`).

También incluye Nota múltiple y edición/eliminación de mensajes en el chat.
