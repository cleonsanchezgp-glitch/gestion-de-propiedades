# Evidencia del instalador nativo

Validado el 10 de octubre de 2026 con PowerShell 5.1, Windows x64 build
10.0.26200.0. El equipo de destino Windows 10 Home no está conectado a esta sesión.

- API Rust compilada en release para `x86_64-pc-windows-msvc`, con CRT estático.
- Paquete con archivos originales de proveedores y manifest de hashes SHA256.
- Comprobaciones de integridad: acepta payload intacto y rechaza payload modificado.
- PostgreSQL inicializado con SCRAM, roles separados y dos bases persistentes.
- Keycloak en modo producción, privado en loopback, con usuario y cliente propios.
- Migraciones ejecutadas por la API nativa.
- Login, cookie HttpOnly/Secure, identificación del propietario, logout y rechazo
  de la sesión cerrada comprobados con la API nativa y el Keycloak del paquete.
- Copias `pg_dump` de ambas bases generadas y sus índices leídos con `pg_restore`.
- ACL de configuración administrativa comprobada: sin acceso de LocalService.
- WinSW aceptó las tres configuraciones de servicio mediante su comando `status`.
- Parámetro `--token-file` verificado en el cloudflared incluido.
- Procesos de ensayo cerrados, sin registrar servicios ni instalar runtime en
  este ordenador. Las bases del ensayo se conservaron al reiniciar los procesos.

Evidencia del ensayo:
`tests/artifacts/windows-native-smoke-20261010-183241/smoke-result.json`.

Pendiente en destino: registro y ejecución bajo LocalService en Windows 10 Home,
reinicio sin sesión Windows, conectividad real de Cloudflare y prueba del portal
publicado. También debe probarse una restauración completa de copia en una
instalación separada: leer el índice del archivo no sustituye esa restauración.
