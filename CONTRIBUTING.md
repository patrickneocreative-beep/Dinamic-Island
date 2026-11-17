# Contribuir a ISLA

Las propuestas y correcciones son bienvenidas. Abre un issue con el problema que quieres resolver o una pull request que explique el comportamiento antes y después. Las contribuciones se reciben bajo la licencia MIT del repositorio.

## Entorno

Se necesita un Mac, SDK de macOS 26 o posterior y Swift de Xcode o sus Command Line Tools. La interfaz actual está en español. No se requiere Xcode para abrir la app ya compilada.

```sh
bash build.sh
```

Conserva el objetivo de despliegue macOS 14 y las comprobaciones de disponibilidad para APIs posteriores. El código se compila en modo Swift 5 con un compilador moderno.

## Invariantes de interacción

- El borde superior exacto pertenece al área de activación; el límite horizontal derecho sigue siendo exclusivo para separar pantallas contiguas.
- Una isla externa cerrada permanece fuera de pantalla, sin interceptar clics. Copias, lecturas y procesos terminados no deben revelarla.
- La animación de tamaño la controla la ventana nativa, con anclaje superior. No añadas otra animación de geometría que la separe del borde.
- Los datos se comparten; apertura, pestaña y pin pertenecen a cada pantalla.
- No bloquees el hilo principal con procesos, red o lectura del iPhone.
- Los nombres y rutas del usuario se pasan como argumentos de procesos, nunca se interpolan en comandos de shell.

Ejecuta las [pruebas pertinentes](docs/TESTING.md). Una corrección visual no necesita una batería nueva de pruebas que replique su implementación, pero sí una comprobación de la interacción afectada.

## Entregar el cambio

Usa un cambio acotado, una descripción del problema, la solución y la validación. Indica cualquier parte que no se pudo probar. Las capturas deben usar datos de demostración. No incluyas `.app`, cachés, certificados, datos de usuario o registros privados.

Antes de enviar:

```sh
python3 scripts/check-repository.py
bash build.sh
```
