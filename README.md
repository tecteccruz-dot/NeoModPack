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
- `Instalar.bat` y `Actualizar.bat`: accesos para los jugadores.

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

El jugador crea o abre la carpeta que usará como instancia, coloca allí
`Instalar.bat` y lo ejecuta. No requiere Git, Python ni CurseForge. Primero elige
entre Minecraft Launcher oficial y SKLauncher. Si elige SKLauncher, el instalador
lo descarga desde su repositorio oficial cuando sea necesario y registra la
instancia. Luego obtiene la última GitHub Release, verifica su SHA-256 y coloca el
modpack directamente en la misma carpeta del `.bat`, sin crear una carpeta
intermedia `game`. Una ventana gráfica muestra el estado, porcentaje y megabytes
descargados.

`Actualizar.bat` debe permanecer en esa misma carpeta. Este compara la versión instalada,
comprueba que no falten mods o recursos y verifica la integridad de los archivos
principales. Solo descarga nuevamente el pack cuando encuentra una actualización
o necesita reparar la instalación. También pregunta si desea aplicar la selección
recomendada de packs; si acepta, reemplaza únicamente la propiedad `resourcePacks`
de `options.txt` y conserva todas las demás preferencias del jugador.
