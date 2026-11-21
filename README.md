# crumb

Historial de comandos por proyecto para tu terminal de siempre.

El historial del shell es global: los comandos de todos tus proyectos se mezclan. crumb hace que las flechas y Ctrl+R muestren el historial del proyecto en el que estás. La primera vez que entras a un proyecto te pregunta qué quieres usar:

1. **Global**: el historial de siempre.
2. **Por carpeta**: solo los comandos de esa carpeta.
3. **Por proyecto**: los comandos del proyecto, compartidos con sus subcarpetas.

Fuera de un proyecto se usa el global sin preguntar. Funciona dentro de cualquier terminal, incluida la de VS Code, porque no reemplaza al shell: solo cambia qué archivo de historial usa.

> **Estado: prototipo.** Hoy son scripts para PowerShell y bash que validan la idea. La versión real será un binario en Go para Windows, Linux y macOS. Ver [docs/PRODUCTO.md](docs/PRODUCTO.md) y [docs/DISENO.md](docs/DISENO.md).

## Probar el prototipo

PowerShell (Windows PowerShell 5.1 o PowerShell 7):
```powershell
. .\prototype\crumb-proto.ps1
```

bash:
```bash
source prototype/crumb-proto.sh
```

Después entra a una carpeta con `.git`, `package.json`, `go.mod` u otro marcador de proyecto. Un comando que empieza con espacio no se guarda.

Solo afecta a la sesión actual. Para dejar de usarlo, cierra la terminal.

## Pruebas

- `prototype/e2e/run-e2e.ps1 -Shell powershell|pwsh|bash`: abre un shell real con [tui-test](https://github.com/microsoft/tui-test) y lo usa con el teclado.
- `prototype/e2e/vscode` (`npm install` y `npm test`): lo mismo dentro de la terminal integrada de una copia aislada de VS Code.
- [docs/PRUEBAS-MANUALES.md](docs/PRUEBAS-MANUALES.md): lista para probar a mano.

Las pruebas usan carpetas e historiales temporales y no tocan tu historial real.

## Licencia

[MIT](LICENSE)
