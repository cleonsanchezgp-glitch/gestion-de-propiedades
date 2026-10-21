# Actualizador PROMALZA

## El EXE que acompaña a esta preparación

`Preparar-Actualizacion-Promalza.exe` permite preparar la actualización sin ejecutar comandos:

1. Copia el EXE al ordenador que ya tiene instalado el backend.
2. Haz doble clic y acepta la solicitud de administrador de Windows.
3. Comprueba la carpeta de instalación. Normalmente es `C:\ProgramData\Aelium\Propiedades`.
4. Pulsa **Obtener inventario** y guarda el JSON en el Escritorio.
5. Envía ese JSON al responsable para que prepare el actualizador compatible. No envíes contraseñas, configuraciones ni bases de datos.

Esta edición no sustituye el backend ni detiene sus servicios. Necesita acceder al portal para completar la consulta. Revisa el JSON antes de enviarlo: contiene rutas, dominios, versiones y hashes, sin las contraseñas ni los registros de inquilinos.

## Cuando recibas la edición final

El responsable entregará `Actualizar-Promalza.exe`, específico para la instalación revisada. Solo tendrás que abrirlo como administrador, comprobar la carpeta, pulsar **Actualizar backend** e introducir tu cuenta del portal. Creará y comprobará la copia de seguridad, actualizará y verificará el backend reutilizando las dependencias instaladas.

No apagues el equipo mientras trabaja. Al terminar debe indicar que el backend está actualizado y verificado. Si indica verificación pendiente o fallo, consulta al responsable; no reinstales ni borres copias. Después, comprueba que puedes entrar al portal y consultar y guardar datos.

El frontend se publica por separado. El responsable coordinará las dos versiones y verificará la actualización y recuperación en una copia aislada antes de entregar el EXE final.
