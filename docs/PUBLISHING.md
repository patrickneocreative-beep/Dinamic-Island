# Publicar ISLA

La carpeta del repositorio contiene código, recursos propios y documentación. La app compilada pertenece a una **Release**; no hace falta subir `build/` ni `dist/` al historial de Git.

## Con GitHub Desktop

1. Inicia sesión en GitHub Desktop con la cuenta que será propietaria del proyecto. Configura tu nombre y el correo de commits; puedes usar el correo privado `noreply` que muestra GitHub en los ajustes de tu cuenta.
2. Usa **File → Add Local Repository** y selecciona esta carpeta. Si vienes de un ZIP sin `.git`, elige crear un repositorio en esa misma carpeta, sin generar otro README o licencia.
3. Revisa los cambios y crea el primer commit en `main`, por ejemplo: `Prepare ISLA 0.13.0 beta`.
4. Pulsa **Publish repository**, usa el nombre `ISLA` y la descripción propuesta abajo. Elige si será público o privado antes de publicarlo.
5. Abre la pestaña **Actions** en GitHub para revisar la primera compilación. Las pruebas gráficas no se ejecutan allí.

Referencias: [añadir una carpeta local](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-a-repository-from-your-local-computer-to-github-desktop) y [publicarla en GitHub](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-an-existing-project-to-github-using-github-desktop).

## Desde la web con un ZIP de fuentes limpio

Descomprime el ZIP de fuentes preparado para GitHub. Crea un repositorio vacío llamado `ISLA`, sin pedir a GitHub que genere README, licencia o `.gitignore`.

En **Add file → Upload files**, sube el **contenido** de la carpeta descomprimida, de modo que `README.md`, `Sources/` y `build.sh` queden en la raíz. En Finder, `⌘⇧.` muestra los archivos ocultos: incluye `.github/`, `.gitignore`, `.gitattributes` y `.editorconfig`. No subas el ZIP como un único archivo. Confirma el primer commit en `main`.

## Perfil del repositorio

- Nombre sugerido: **ISLA**.
- Descripción: **Una isla nativa para macOS: música, batería, calendario, portapapeles, archivos y Atajos, con soporte para varias pantallas.**
- Topics sugeridos: `macos`, `swift`, `swiftui`, `appkit`, `notch`, `dynamic-island`, `clipboard`, `shortcuts`, `productivity`.
- Licencia: **MIT**; ya está incluida.
- En Settings → Security puedes activar los reportes privados de vulnerabilidades para ofrecer el canal descrito en `SECURITY.md`.

## Primera release

1. Comprueba que Actions terminó y revisa sus resultados.
2. Genera los archivos con `bash scripts/package.sh`, o utiliza los artefactos de esa compilación. Conserva juntos el ZIP y su `SHA256SUMS.txt`.
3. En Releases → Draft a new release, crea la etiqueta **`v0.13.0`** sobre el commit revisado de `main` y titula la publicación **ISLA 0.13.0 — Primera beta**.
4. Copia el texto de `docs/releases/v0.13.0.md` y adjunta `ISLA-0.13.0-macOS-universal.zip` y `SHA256SUMS.txt`.
5. Marca **Set as a pre-release**. Revisa y publica cuando decidas hacerlo.

El workflow `macOS build` genera artefactos. `Publish beta` publica una prerelease después de compilar y probar, al añadir su workflow o cambiar Info.plist en main; también puede ejecutarse desde Actions → Publish beta → Run workflow. Si esa versión ya existe, conserva sus archivos. Los ZIP locales tienen firma ad hoc, sin certificado Developer ID ni notarización. Si en el futuro se añade distribución notarizada, los certificados y secretos deben configurarse fuera del repositorio.
