# Neo Modpack

Herramientas de instalación y actualización del modpack privado **Neo**.

La instancia de CurseForge ubicada en este directorio funciona como la copia de
trabajo del administrador. Los mods, configuraciones, paquetes de recursos y
shaders no se guardan directamente en Git: la herramienta de publicación los
empaquetará y adjuntará a una GitHub Release.

## Distribución prevista

Cada versión publicará:

- `Neo-<version>.zip`: contenido completo del modpack.
- `manifest.json`: versión, tamaño, URL de descarga y SHA-256.
- `Iniciar-Neo.exe`: instalador y actualizador para los jugadores.

Los mundos, registros, credenciales y preferencias personales están excluidos
del repositorio y de los paquetes publicados. `options.txt` es la excepción:
se conserva como configuración predeterminada para aplicar la selección de
`resourcePacks` del administrador.

## Crear una versión

Ejecuta `Publicar.cmd`, escribe una versión como `1.0.0` y espera a que termine.
Los archivos resultantes aparecerán en `dist/`. El ZIP contiene el pack y sus
hashes individuales; `manifest.json` contiene el SHA-256 del ZIP y la dirección
de descarga de la Release correspondiente.

Después crea en GitHub una Release cuyo tag coincida con `v<version>` y adjunta
el ZIP y `manifest.json`. Por ejemplo, la versión `1.0.0` usa el tag `v1.0.0`.

## Instalación para jugadores

El jugador solo necesita descargar y abrir `Instalar.bat`. No requiere Git,
Python, CurseForge ni Java. El instalador usa Windows PowerShell, instala
SKLauncher desde su repositorio oficial si hace falta, obtiene la última GitHub
Release, verifica su SHA-256 y crea la instancia `Neo Modpack`.

Antes de jugar puede abrir `Actualizar.bat`. Este compara la versión instalada,
comprueba que no falten mods o recursos y verifica la integridad de los archivos
principales. Solo descarga nuevamente el pack cuando encuentra una actualización
o necesita reparar la instalación.
