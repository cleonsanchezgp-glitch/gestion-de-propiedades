# Publicar el frontend de PROMALZA

Ejecutar estos comandos desde el repositorio del proyecto, en un ordenador con Node.js y npm instalados:

```powershell
cd "C:\Users\Usuario\Documents\empresa\repositorios\gestion de propiedades\frontend"
npm ci
npm run build
npx wrangler@4 login
```

El último comando abrirá el navegador. Inicia sesión en la cuenta de Cloudflare donde creaste `promalza` y autoriza el acceso.

Después ejecuta, desde la misma carpeta:

```powershell
npx wrangler@4 deploy
```

Si el repositorio está en otra ubicación, cambia únicamente la ruta del primer comando. Si PowerShell bloquea `npm.ps1` o `npx.ps1`, utiliza `npm.cmd` y `npx.cmd`, respectivamente.

## Antes de publicar

Este procedimiento utiliza el código fuente del repositorio, con `package.json`, `package-lock.json`, `src`, `public`, `cloudflare` y `wrangler.jsonc`. La carpeta `frontend` de la candidata contiene archivos compilados; no es la carpeta del repositorio desde la que ejecutar `npm ci`.

Para actualizar el Worker existente, conservar su configuración: nombre `promalza`, dominio, variable `API_ORIGIN` y secretos `CF_ACCESS_CLIENT_ID` y `CF_ACCESS_CLIENT_SECRET`. El archivo del proyecto usa `keep_vars: true`. Si es la primera publicación, el responsable debe configurar esos valores y el túnel del backend antes de comprobar el portal.

El comando `deploy` publica el Worker y los archivos de `dist` generados por `npm run build`. Coordinar la publicación con la versión compatible del backend. No hace falta crear una carpeta de publicación intermedia.

## Comprobar el resultado

1. Abrir el dominio habitual del portal y comprobar que carga la nueva versión.
2. Consultar `/release.json`: esta entrega identifica `promalza-web-20261021-r1` y el contrato `propiedades-v3`.
3. Iniciar sesión, consultar los datos y guardar un cambio de prueba acordado. Recargar y comprobar que persiste.
4. Cerrar sesión y comprobar que se vuelve a solicitar acceso.

Si aparece `API no configurada`, revisar la variable y los secretos del Worker. Si indica que el servidor local no está disponible, revisar backend, túnel y autorización de Access con el responsable.

La publicación del frontend no instala ni actualiza el backend. La candidata sigue pendiente de validación con la instalación real del cliente.

Referencia: https://developers.cloudflare.com/workers/wrangler/commands/workers/