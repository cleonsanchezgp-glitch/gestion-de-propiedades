# Frontend en Cloudflare, servidor local independiente

Para desarrollar con API, Keycloak y PostgreSQL en Docker Desktop, usar el [entorno de desarrollo](dev/README.md).

**Para una instalación Docker nueva en Windows con actualización automática de la API:** usar la [guía de contenedores](container/README.md). Comprobar antes los requisitos de Docker Desktop del equipo de destino.

**Para el ordenador del cliente con Windows 10 Home y servicios nativos:** usar el
[instalador nativo](windows/README.md). El resto de esta guía describe la variante
Docker. En la variante nativa Keycloak queda privado y solo se publica el dominio
API mediante el túnel; no hace falta un dominio público para Keycloak.

La instalación local de desarrollo sigue funcionando. Este despliegue tiene sus
propios volúmenes, puertos, usuarios y secretos; no utiliza los datos de pruebas.

## Arquitectura

```text
Navegador -> HTTPS portal (Cloudflare Worker + frontend/dist)
                    /api -> HTTPS API protegida con Access
                                  -> Cloudflare Tunnel -> localhost:58090
                                                            API Rust
                                                               | PostgreSQL persistente
                                                               | Keycloak HTTPS
Keycloak HTTPS -> Cloudflare Tunnel -> localhost:58082
```

Se usa Workers con Static Assets para alojar la web y su proxy juntos, en lugar
de subir únicamente archivos a Pages. La API Rust y las bases de datos permanecen
en el servidor local. El navegador nunca recibe el secreto del cliente Keycloak
ni los secretos de Cloudflare Access. Las credenciales se introducen en el portal.

## 1. Preparar el servidor

Instalar Docker con Compose y `cloudflared` en el servidor. Desde la raíz:

```powershell
Copy-Item deploy/local/.env.example deploy/local/.env
```

Editar ese archivo con los dominios y secretos reales. Generar contraseñas largas
independientes, usando letras, números, guion y guion bajo para evitar escapes en
la URL de PostgreSQL. No subir `.env` a Git. No reutilizar credenciales de pruebas.

Para configurar primero Keycloak, poner valores provisionales no vacíos en
`KEYCLOAK_ALLOWED_SUBJECT` y `KEYCLOAK_LOGIN_CLIENT_SECRET`, y arrancar solo las bases
de datos y Keycloak:

```powershell
docker compose --env-file deploy/local/.env -f deploy/local/compose.yaml up -d postgres keycloak-db keycloak
```

## 2. Conectar el túnel y configurar Keycloak

Crear un túnel persistente en Cloudflare y ejecutar su conector como servicio en
el servidor, fuera de Docker. Configurar dos aplicaciones publicadas:

| Dominio de ejemplo | Servicio del túnel |
| --- | --- |
| `api.example.com` | `http://127.0.0.1:58090` |
| `auth.example.com` | `http://127.0.0.1:58082` |

Proteger **todo el dominio API** con una aplicación Cloudflare Access, política
`Service Auth` y un token de servicio. Ese token se instalará solo en el Worker.
El dominio de Keycloak debe permitir los endpoints OIDC necesarios para que la
API pueda obtener tokens y claves. Restringir `/admin` con Access a tu identidad;
el backend no necesita acceso administrativo. No aplicar una pantalla de Access
a los endpoints OIDC usados por la API sin preparar autenticación de servicio.

Entrar en la administración de Keycloak y crear:

1. Realm `propiedades`, con protección contra fuerza bruta.
2. Tu usuario y contraseña definitiva; sin acciones pendientes que requieran un
   flujo interactivo. Copiar su ID a `KEYCLOAK_ALLOWED_SUBJECT`.
3. Cliente `portal-login`: Client authentication activado, Direct access grants
   activado, Standard flow y Service accounts desactivados. Copiar su secreto a
   `KEYCLOAK_LOGIN_CLIENT_SECRET`.
4. Mapper de tipo Audience en el client scope dedicado del cliente: Included
   Custom Audience `propiedades-api`, Add to access token activado.

Estos nombres deben coincidir con `.env`. El issuer será
`https://auth.example.com/realms/propiedades`. La API accede a esa URL HTTPS por
el túnel; no se desactiva la validación TLS. El acceso a Internet del servidor es
necesario también para renovar las sesiones.

## 3. Instalar la API

Con los identificadores y secretos definitivos:

```powershell
docker compose --env-file deploy/local/.env -f deploy/local/compose.yaml up -d --build api
```

La API ejecuta las migraciones al arrancar. PostgreSQL no publica ningún puerto.
Solo API y Keycloak publican puertos de loopback para el conector del túnel.
Los servicios tienen reinicio automático; Docker y cloudflared también deben
arrancar con el ordenador. Desactivar su suspensión si va a servir el portal.

## 4. Instalar el frontend en Cloudflare

El frontend puede compilarse desde su carpeta sin ejecutar Rust ni PostgreSQL:

```powershell
cd frontend
npm ci
npm run build
```

Editar `API_ORIGIN` en `wrangler.jsonc` con el dominio API del túnel. Utilizar
Wrangler 4, autenticarse con la cuenta de Cloudflare y guardar los dos secretos
del token de servicio de Access (el comando pide su valor sin incluirlo en Git):

```powershell
npx wrangler@4 login
npx wrangler@4 secret put CF_ACCESS_CLIENT_ID
npx wrangler@4 secret put CF_ACCESS_CLIENT_SECRET
npx wrangler@4 deploy
```

Asignar el dominio definitivo del portal al Worker desde Cloudflare. Establecer
`PORTAL_ORIGIN` en el `.env` local a ese origen HTTPS exacto, sin barra final, y
recrear la API con el comando del paso 3. No usar Vite dev o preview como servidor
de producción. No agregar caché al dominio API; configurar bypass en cualquier
regla de caché que pudiera abarcarlo.

## 5. Comprobar y mantener

Comprobar en el dominio final: login, lectura, guardar un pago, recarga y logout.
La cookie debe ser HttpOnly, Secure y SameSite=Strict. Una llamada directa al
dominio API sin token Access debe ser denegada. Apagar la API debe mostrar el
error de servidor no disponible, manteniendo la web accesible.

Hacer copias periódicas con `pg_dump` de las dos bases de datos, guardarlas fuera
del servidor y comprobar su restauración. Los volúmenes conservan datos al
reiniciar; **`docker compose down -v` los borra**. Al reiniciar la API se pierden
las sesiones en memoria y será necesario volver a entrar. Este despliegue está
pensado para una única instancia de API.

No se ha desplegado nada en una cuenta Cloudflare ni trasladado datos existentes.
Para finalizar la instalación hacen falta los dominios, el túnel, el token de
servicio y la configuración de tu usuario Keycloak.

Referencias: [Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/),
[Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/get-started/),
[Keycloak en contenedores](https://www.keycloak.org/server/containers).
