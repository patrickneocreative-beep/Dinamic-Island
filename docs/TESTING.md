# Pruebas

## Comprobaciones automáticas de compilación

```sh
python3 scripts/check-repository.py
bash build.sh
```

La primera orden revisa estructura, enlaces locales, versiones y patrones de credenciales o rutas de usuario en los archivos que se publicarían. No sustituye una auditoría de seguridad. `build.sh` compila las dos arquitecturas, valida la firma y ejecuta `--self-test`: temporizador, geometría, archivos, metadatos, tiempos, LRC y estados de batería/conexión con datos simulados.

El workflow `macOS build` ejecuta esas comprobaciones en `macos-26` y guarda un ZIP universal con SHA-256 como artefacto. Usa permisos de lectura y no pide certificados. El workflow separado `Publish beta` usa permiso de escritura del repositorio para publicar el ZIP como prerelease después de compilar y comprobar la app. La imagen de runner se eligió de la [lista oficial de GitHub](https://github.com/actions/runner-images#available-images). El resultado de CI se conocerá cuando el repositorio se suba y se ejecute el workflow.

## Interacción nativa con datos de prueba

Requieren una sesión gráfica de macOS. Ejecuta desde la raíz del repositorio:

```sh
bash Tests/verify.sh build/hover-check --hover-only
bash Tests/verify-calendar-displays.sh build/calendar-check
bash Tests/verify-presentation.sh build/presentation-check
bash Tests/verify-utilities.sh build/utilities-check
```

- Hover: entrada, permanencia, edición de Notas, cierre, pin y reentrada. No cambia tu reproducción.
- Calendario y pantallas: fechas, eventos de prueba, estado compartido, pantalla externa oculta y reordenación simulada.
- Presentación: indicadores compactos, prioridad de batería y 100 muestras de animación.
- Utilidades: portapapeles independiente, preferencias aisladas, archivos temporales, ZIP y Atajos simulados. Vista previa puede aparecer brevemente. No ejecuta Atajos personales.

Los artefactos se guardan dentro de `build/`, excluido de Git. Los tests que usan ventanas se mantienen fuera de CI porque dependen de una sesión gráfica y del sistema de ventanas.

## Pruebas que usan datos o dispositivos reales

Son optativas. Revisa los registros antes de compartirlos.

```sh
# Solo lee nombres e identificadores de tus Atajos; no ejecuta ninguno.
bash Tests/verify-utilities.sh build/shortcuts-live --live-list

# Consulta Apple Music y letras. Requiere canción y permiso de Automatización.
bash Tests/verify.sh build/media-live

# Compara batería del Mac con pmset y lee un iPhone autorizado.
bash Tests/verify-power.sh build/power-live

# Exige que la lectura real del teléfono llegue por Wi-Fi.
bash Tests/verify-power.sh build/power-wifi --require-wifi
```

Para probar ambos monitores reales, abre una sola instancia de ISLA y ejecuta:

```sh
bash Tests/verify-live-displays.sh
```

Esta última prueba **mueve el cursor unos 20 segundos**, sin hacer clic, y lo devuelve a su posición inicial. No uses el ratón durante el recorrido. Exige una pantalla con notch y otra externa; un movimiento ajeno al recorrido invalida la comprobación. No se debe ejecutar automáticamente en una sesión de trabajo compartida.

## Evidencia de la base 0.13

Antes de preparar este repositorio se completaron localmente 57 comprobaciones de utilidades, 25 de hover/Notas, 65 de calendario/pantallas y 15 de presentación. Una pasada controlada en dos pantallas físicas pasó 18/18, sin desplazamiento superior en 1,781 muestras. Se leyó la lista real de Atajos sin ejecutarlos.

Estas cifras son evidencia local de esa base, no un distintivo de CI ni una garantía de todas las combinaciones de hardware. La validación física de iPhone por Wi‑Fi, Spotify con una sesión activa y ejecución en Intel siguen pendientes.
