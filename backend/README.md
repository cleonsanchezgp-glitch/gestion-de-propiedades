# API de Gestión de propiedades

Servicio Rust independiente del frontend. Necesita PostgreSQL y un realm Keycloak.
Al arrancar ejecuta las migraciones incluidas en `migrations/`.

Compilación sin frontend, desde esta carpeta:

```powershell
cargo build --locked --release
```

El ejecutable usa `DATABASE_URL`, `BACKEND_BIND`, `KEYCLOAK_ISSUER`,
`KEYCLOAK_AUDIENCE`, `KEYCLOAK_ALLOWED_SUBJECT`, `KEYCLOAK_LOGIN_CLIENT_ID`,
`KEYCLOAK_LOGIN_CLIENT_SECRET` y `PORTAL_ORIGIN`. No imprime los secretos.

Para instalarlo con Docker y almacenamiento persistente, consulta
[la guía de despliegue](../deploy/README.md). El Dockerfile solo copia código,
manifiestos y migraciones del backend; no necesita Node ni los archivos del portal.
