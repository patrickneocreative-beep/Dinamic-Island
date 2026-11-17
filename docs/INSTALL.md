# Instalar y usar ISLA

## Primera instalación

Descarga el ZIP universal desde la sección Releases del repositorio, descomprímelo y mueve `ISLA.app` a Aplicaciones. Abre la app y busca el icono de cápsula en la barra de menús. Desde ese menú puedes abrir secciones o salir.

Esta beta usa firma ad hoc y no está notarizada. Si confías en la descarga y macOS bloquea la app, intenta abrirla y después revisa Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente. El texto puede variar según macOS. Conserva activadas las protecciones del sistema.

No se añade automáticamente al inicio de sesión. Para iniciarla al encender el Mac, puedes añadirla desde los ítems de inicio de sesión de macOS.

## Abrir y cerrar

- Mac con notch: acerca el puntero al borde inferior, a sus lados o al centro superior de la pantalla.
- Monitor externo: acerca el puntero al centro del borde superior. Cuando está cerrada no hay ventana visible ni superficie que intercepte clics de la barra de menús.
- Recorre el panel para usar sus pestañas. Al retirar el cursor se contrae; el pin lo mantiene abierto.
- La flecha y Esc cierran el panel. Un movimiento deliberado o salir y volver permite abrirlo de nuevo.

## Conectar módulos

**Música:** abre Apple Music o Spotify y conecta el reproductor desde ISLA. macOS puede pedir permiso de Automatización. Si lo denegaste, revisa Privacidad y seguridad → Automatización. La consulta de letras utiliza LRCLIB; no todas las canciones tienen letras sincronizadas.

**Calendario:** pulsa Conectar Calendario y autoriza el acceso a eventos. Sin ese permiso sigue disponible el mes. Los calendarios se configuran en macOS, no dentro de ISLA.

**Portapapeles:** pulsa Activar historial. Se capturan nuevas copias, hasta 24 recientes y 12 fijados. Pausar detiene la captura. La papelera elimina los recientes; usa la × de un elemento fijado para eliminarlo también del almacenamiento local. Se omiten textos de más de 30 KB e imágenes de más de 4 MB.

**Archivos:** arrastra un archivo a la isla o pulsa Añadir. Pulsa el nombre para Vista previa. El menú … permite abrir, localizar, renombrar, comprimir o quitar de la bandeja. Renombrar cambia el original; quitar de la bandeja lo conserva. Un ZIP necesita un destino nuevo y, si comprimes una carpeta, fuera de ella.

**Atajos:** la pestaña carga los atajos de la app de Apple. La estrella coloca favoritos primero. Pulsa un nombre para ejecutar. Si entraste desde un archivo de la bandeja, ese archivo se enviará como entrada; la × permite quitarlo. Atiende en Atajos cualquier pregunta o permiso que requiera el flujo.

**iPhone:** conecta primero por USB y autoriza la confianza desde iOS/Finder. Para intentar Wi‑Fi, activa Mostrar este iPhone al estar en Wi‑Fi en Finder y aplica el cambio. Ambos equipos deben compartir red y el iPhone debe estar disponible para macOS. La ruta inalámbrica continúa experimental; ISLA no cambia el emparejamiento ni esa opción. Puede necesitar permiso de red local.

## Actualizar

Cierra la versión anterior desde el menú de ISLA antes de sustituir la app. Conserva una sola instancia abierta. Con el mismo identificador de app, se mantienen notas, referencias a archivos, preferencias y portapapeles fijado.

## Desinstalar

Sal de ISLA y elimina la app. Las notas y preferencias usan el dominio `local.isla.prototype` de macOS; los fijados del portapapeles están en `~/Library/Application Support/ISLA/clipboard-pins.json`. Puedes eliminar el historial desde la propia app antes de desinstalar. Los archivos originales añadidos a la bandeja no se eliminan.

## Si algo falla

Comprueba que la app esté abierta y que no haya dos instancias. Prueba el menú de la barra de menús como acceso alternativo. En un reporte indica la versión, macOS y si ocurre en la pantalla con notch, externa o ambas. No adjuntes tus preferencias o el historial del portapapeles: pueden contener información privada.
