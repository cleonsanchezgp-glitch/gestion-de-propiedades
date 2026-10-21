# Ensayo de actualizacion en VirtualBox sin portal

Esta entrega es para la VM Windows 10 Home x64 aislada, sin datos de cliente,
con instalacion original completa, propietario `prueba` y origen reservado
`https://portal.example.test`. No se cambia el origen ni se conecta un tunel.

La instalacion inicial se utiliza una sola vez para crear el origen. Las
actualizaciones posteriores usan `Actualizar.ps1`, no `Instalar.ps1`.

1. Conservar una instantanea previa y comprobar el SHA256 externo de esta
   entrega antes de extraerla en una carpeta nueva local de la VM.
2. Ejecutar `Preparar-Ensayo-Local.ps1 -ConfirmIsolatedVM` como administrador.
   Comprueba huellas originales, servicios y dependencias reales; exige base
   de negocio vacia, crea datos sinteticos (incluidos 600/250/350 e historicos
   null), adjunto binario, marca ligada a raiz/sujeto y catalogo exclusivo del
   ensayo. Construye un paquete de aplicacion sin dependencias y ejecuta solo
   preflight. No sustituye ejecutables ni detiene servicios en este paso.
3. Revisar el resultado `LocalRehearsalPreflightVerified` y conservar una
   instantanea de esta baseline con datos. No repetir la preparacion encima
   de un directorio de trabajo existente o de un mantenimiento iniciado.
4. Ejecutar `Ejecutar-Ensayo-Local.ps1 -Action Apply`. Solicita credenciales
   del propietario de forma local. Usa el control real de servicios Windows,
   copia ambas bases y archivos inventariados, comprueba restauracion aislada,
   selecciona candidata y comprueba identidad, sesiones, CRUD sintetico y
   conservacion. No introduce simulaciones de servicios ni de Keycloak.
5. Repetir Apply sobre el mismo ZIP debe devolver
   `LocalRehearsalAlreadyApplied`, sin otra migracion/copia. Comprobar servicios,
   acceso y datos antes/despues del reinicio. El ensayo de fallos y recuperacion
   requiere baseline separada y evidencia por variante; no esta completado por
   una actualizacion correcta.

Un resultado `VerificationPending` requiere revisar la causa y usar Finalize
con las mismas herramientas/modo. Recover recupera una operacion incompleta;
no revierte una operacion ya Committed descartando escrituras posteriores.
Si aparece RecoveryRequired, conservar metadatos y bases y revisar antes de
actuar. No borrar la instalacion ni cambiar el manifiesto para eludir rechazos.

## Limites y produccion

`-LocalRehearsal` requiere marca explicita ligada a la instalacion, origen
reservado, propietario de ensayo y ausencia de servicio/token de tunel.
El contexto y recibo conservan el modo: no se reanuda ni se reconoce una entrega
aplicada en un modo distinto. La marca es una restriccion administrativa, no
una prueba automatica de ausencia de datos reales; el operador confirma la VM.

El modo local comprueba API y autenticacion reales en loopback. La cookie Secure
se reproduce manualmente solo para el diagnostico local; no acredita transporte
HTTPS ni comportamiento del navegador. Los resultados son
`LocalRehearsalSucceeded`, `LocalRehearsalAlreadyApplied` o
`LocalRehearsalPreflightVerified`, con `portalChecked=false`,
`productionAccepted=false` y `updateSucceeded=false`. Nunca equivalen a
`UpdateSucceeded` ni a aceptacion de la entrega al cliente.

Produccion sigue exigiendo el portal HTTPS real y sus contratos. No se omiten
validaciones de paquetes, copias, esquema, cuentas, bloqueo ni conservacion.
La conservacion de Keycloak sigue siendo estricta: si sus datos cambian al
arrancar/autenticar, el ensayo puede rechazar el commit y recuperar. No se
excluyen tablas o datos de identidad para forzar un resultado satisfactorio.
Las migraciones que transforman datos siguen necesitando politica revisada.

El runtime Microsoft se comprueba por hashes de las DLL reales de System32
mediante el espacio reservado `system-runtime/` (solo vcruntime140.dll,
vcruntime140_1.dll y msvcp140.dll). No se copia ni reinstala durante el update.
Los otros archivos de dependencias se cotejan en la raiz instalada.

El catalogo original del cliente permanece sin revisar. El catalogo generado
solo acredita el ensayo sintetico inspeccionado por su operador y no sustituye
revision independiente, admision del origen de produccion ni pruebas de portal.
No exportar configuracion, dumps, logs privados o credenciales; compartir solo
resultados sanitizados.

Tras un ensayo recuperado sin cambios de aplicacion, `Comprobar-Copia-Ensayo-Local.ps1`
permite repetir exclusivamente la captura y restauracion aislada de ambas bases.
Requiere la VM marcada, administrador y credenciales del propietario sintetico.
Conserva el registro anterior, crea otra operacion y detiene temporalmente los
escritores. Siempre intenta recuperar el estado original al terminar. Nunca entra
en Applying ni instala la candidata. Si devuelve RecoveryRequired, conservar el
estado protegido y diagnosticar antes de repetir. El informe muestra etapas y
comparaciones booleanas, sin datos, hashes de contenido ni respuestas privadas.

Las nuevas copias usan formato 2: el fingerprint de columnas conserva el orden
de las columnas vigentes mediante su ordinal logico. No compara los huecos de
numeracion fisica dejados por columnas eliminadas, que un dump logico omite.
Se siguen comprobando nombres, tipos, nulabilidad, identidad, generacion,
collation, restricciones, propietarios y el resto del fingerprint existente.
Las copias de formato 1 conservan su algoritmo original, incluso al recuperarlas;
no se reetiquetan ni se marcan verificadas retroactivamente.

La captura publica pasos separados para fingerprint previo, dump, fingerprint
posterior y globals. Los comandos de mantenimiento tienen un limite por proceso
de 300 segundos y conexion de 10 segundos; stdout y stderr se drenan por separado
y stdin se cierra incluso sin SQL. Un proceso que excede el limite se termina y
no valida la copia. Esto permite la recuperacion mientras Windows responde;
no garantiza recuperacion durante un bloqueo de todo el sistema invitado.

La comprobacion exclusiva de copia admite la VM de VirtualBox y su copia Windows
en Hyper-V (fabricante Microsoft Corporation, modelo Virtual Machine). Ambas
siguen requiriendo el marcador local de ensayo, propietario sintetico, origen
reservado y operacion anterior recuperada. El cambio de hipervisor no constituye
por si mismo una validacion del backup ni del actualizador.
# Perfil experimental de conservación de Keycloak

Solo `LocalRehearsal`, con su marcador de instalación aislada y los JAR de Keycloak 26.7.4 cotejados por SHA-256, admite el perfil `keycloak-26.7.4-local-runtime-v1`. Se captura una proyección privada después de verificar la copia completa y antes de modificar la aplicación; queda ligada al ID de operación. Las copias y la restauración conservan su comparación integral, incluidas todas las sesiones y las filas de funcionamiento interno.

La comprobación posterior permite cambiar las filas de descubrimiento de `public.jgroups_ping` y las sesiones normales (`offline_flag='0'`). Conserva exactamente las sesiones offline (`'1'`), rechaza categorías desconocidas y exige que no cambie la estructura completa de Keycloak. En `public.server_config` solo admite el avance numérico del contador único `JGROUPS_ADDRESS_SEQUENCE`, sin retroceso de su versión; `crt_jgroups` y todas las demás claves siguen comparándose íntegramente. Usuarios, credenciales, realms, clientes y permisos permanecen bajo comparación estricta. La ausencia o identidad incorrecta de la proyección bloquea el ensayo.

Este perfil es experimental y no habilita aceptación de producción. Producción y versiones de Keycloak sin ese perfil mantienen la comparación estricta previa. Su incorporación al diseño confirmado requiere revisión y evidencia con Keycloak real; no cambia la limitación documentada para migraciones que transforman datos de negocio.

Fuentes contrastadas para 26.7.4: [contador y descubrimiento JGroups](https://github.com/keycloak/keycloak/blob/26.7.4/model/infinispan/src/main/java/org/keycloak/spi/infinispan/impl/embedded/JGroupsConfigurator.java), [certificado del clúster](https://github.com/keycloak/keycloak/blob/26.7.4/model/infinispan/src/main/java/org/keycloak/jgroups/certificates/DatabaseJGroupsCertificateProvider.java). No se excluye la tabla completa de configuración.

