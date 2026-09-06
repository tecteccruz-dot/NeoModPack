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
del repositorio y de los paquetes publicados.

