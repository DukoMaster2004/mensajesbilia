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

Los favoritos, notas, resaltados, notas múltiples y el chat se sincronizan entre todas las personas que abren la página. **Son datos públicos y compartidos:** cualquier visitante puede leerlos, cambiarlos o eliminarlos. El tema y el tamaño del texto siguen siendo preferencias locales del navegador.

Para activar la sincronización:

1. Crea un proyecto en Supabase y ejecuta [`supabase/shared_page_state.sql`](./supabase/shared_page_state.sql) en el SQL Editor.
2. Configura `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` como variables de entorno del servidor (en `.env` o `.env.local` al desarrollar localmente) y del despliegue de Vercel. La clave `service_role` es secreta; nunca la pongas en el código del navegador.
3. Despliega de nuevo. Las pestañas abiertas reciben actualizaciones periódicamente.

Al conectarse correctamente por primera vez, los elementos guardados localmente que aún no existan en el estado compartido se publican automáticamente; los elementos ya compartidos tienen prioridad. Antes de migrar, los datos locales se conservan como copia en `localStorage` (`branham-study-local-backup` y `branham-chat-local-backup`). Mientras las variables no estén configuradas, la sincronización muestra un error y los cambios nuevos siguen guardándose localmente.

## Biblia

Sección "Biblia" (debajo de Mensajes): los 66 libros en Reina-Valera 1960 (`Resources/biblia_rv1960.json`), con navegación por libro/capítulo, búsqueda por palabra o referencia (`Juan 3:16`) y compartir versículos. La **IA de la Biblia** solo muestra versículos reales del archivo; el modelo únicamente elige y explica brevemente.

Variable opcional en `.env`: `GEMINI_BIBLE_API_KEY` (si falta, usa `GEMINI_API_KEY`).

También incluye Nota múltiple y edición/eliminación de mensajes en el chat.
