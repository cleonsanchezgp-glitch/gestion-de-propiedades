# Sesiones del portal: 30 minutos

La autenticación usa los JWT firmados de Keycloak. La API valida firma,
emisor, audiencia, caducidad e identidad autorizada. Los tokens de acceso y
renovación se guardan en memoria del backend; el navegador recibe una cookie
aleatoria HttpOnly, SameSite=Strict y Secure cuando el portal usa HTTPS.

La sesión tiene un límite absoluto de 1800 segundos desde el login y la cookie
caduca al mismo tiempo. Ni las consultas ni la renovación del token extienden
ese límite. Al caducar hay que iniciar sesión de nuevo. Reiniciar el backend
invalida sus sesiones existentes.

Las instalaciones nuevas incluyen estos atributos en el cliente `portal-login`.
Para la instalación existente del cliente, configurar en la consola privada de
Keycloak, Clients → portal-login → Advanced:

- Access Token Lifespan: 30 minutos.
- Client Session Idle: 30 minutos.
- Client Session Max: 30 minutos.

Revisar que SSO Session Idle y SSO Session Max del realm no sean inferiores a
30 minutos. Conservar secretos, usuarios, mappers y el resto de la configuración.
No reimportar el realm para modificar estos valores. Este paso corresponde a la
entrega de actualización: cambiar el generador de instalaciones nuevas no
modifica automáticamente un Keycloak ya instalado.

Comprobar con un login nuevo `expires_in` y el intervalo `exp - iat` del token,
sin copiar tokens en informes o mensajes, y el Max-Age=1800 de la cookie del
portal. Las sesiones antiguas deben cerrarse durante la actualización.

Referencia: https://www.keycloak.org/docs/latest/server_admin/index.html
