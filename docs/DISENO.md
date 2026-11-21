# Diseño técnico del MVP (borrador v0.1)

## 1. Idea central
El shell ya guarda y recupera su historial. `crumb` solo decide **qué archivo de historial usa el shell** según la carpeta, y le pide al shell que lo cargue. No captura comandos ni reemplaza flechas ni Ctrl+R.

```
Prompt del shell ──(cambió la carpeta?)──► crumb resolve ──► ruta del archivo de historial
        ▲                                                            │
        └──── el shell cambia su archivo y recarga el historial ◄────┘
```

## 2. Piezas
1. **Binario `crumb` (Go)**: decide el modo, detecta proyecto, hace la pregunta inicial y guarda la elección.
2. **Script de integración por shell** (`pwsh.ps1`, `bash.sh`), embebido en el binario con `go:embed`. Se instala con una línea en el perfil del shell:
   - PowerShell: `crumb init pwsh | Out-String | Invoke-Expression`
   - bash: `eval "$(crumb init bash)"`

## 3. Almacenamiento
Todo vive fuera de los proyectos. No se ensucia ningún repo en el MVP.

| Qué | Dónde (Windows / Linux-macOS) |
|---|---|
| Configuración | `%APPDATA%\crumb\config.toml` / `~/.config/crumb/config.toml` |
| Elecciones por carpeta | `%APPDATA%\crumb\choices.json` / `~/.config/crumb/choices.json` |
| Historiales | `%LOCALAPPDATA%\crumb\histories\` / `~/.local/share/crumb/histories/` |

- Un archivo por clave: `<hash de la ruta>.<shell>.txt`. La clave es la ruta de la carpeta (modo carpeta) o de la raíz del proyecto (modo proyecto).
- **Formato**: el nativo de cada shell (texto, una entrada por línea). El shell sigue escribiendo y leyendo su propio formato, así que no hay que capturar comandos. Se separan por shell porque PowerShell y bash guardan comandos de varias líneas de forma distinta.
- **Modo global**: se deja el archivo original del shell sin tocar.
- **Costo de esta decisión**: sin fecha, carpeta ni código de salida por comando. Para `marcar` y la búsqueda avanzada (segunda versión) habrá que migrar a un formato propio o añadir un índice aparte.

`choices.json`:
```json
{ "C:\\Users\\yo\\repos\\app": "project", "C:\\Users\\yo\\Downloads": "global" }
```

## 4. Resolución del historial
`crumb resolve --shell pwsh --cwd <ruta>` imprime en stdout la ruta del archivo a usar.

1. Buscar raíz de proyecto: subir desde `cwd` hasta encontrar un marcador. Gana el más cercano, así una subcarpeta con su propio proyecto tiene historial propio. Se detiene en el directorio personal o en la raíz del disco.
2. Clave candidata: la raíz de proyecto si existe, si no `cwd`.
3. Buscar una elección guardada para esa clave, subiendo por los padres.
4. Si no hay ninguna y no hay proyecto: usar el global sin preguntar ni guardar. Si hay proyecto: **preguntar** global, carpeta o proyecto, y guardar la respuesta.
5. Devolver la ruta según el modo.

Marcadores por defecto, configurables: `.git`, `.crumb`, `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `*.csproj`, `*.sln`.

La pregunta se escribe en stderr y se lee del terminal (`CONIN$` en Windows, `/dev/tty` en Unix), así stdout queda libre para la ruta. Si no hay terminal interactivo (scripts, tareas automáticas), no pregunta y usa el global.

## 5. Integración con cada shell
Regla: llamar a `crumb` **solo cuando cambia la carpeta**, no en cada comando, para no pagar el arranque del proceso cada vez.

### bash
- Se engancha en `PROMPT_COMMAND`.
- Al cambiar `$PWD` (y al abrir): `history -a` para guardar lo pendiente, `HISTFILE=<ruta>`, `history -c`, `history -r`.
- Cada prompt: `history -a` para escribir al instante, de modo que varias terminales se vean entre sí (`history -n` para leer lo de otras sesiones).
- Comandos que no se guardan: `HISTCONTROL=ignorespace` y `HISTIGNORE` con los patrones de la configuración.

### PowerShell
- Se envuelve la función `prompt`.
- Al cambiar `$PWD`: `Set-PSReadLineOption -HistorySavePath <ruta>`, `[PSConsoleReadLine]::ClearHistory()` y cargar el archivo con `[PSConsoleReadLine]::AddToHistory(...)` por línea.
- Comandos que no se guardan: `Set-PSReadLineOption -AddToHistoryHandler` que devuelve `SkipAdding` si el comando empieza con espacio o coincide con un patrón.
- Escritura inmediata: `-HistorySaveStyle SaveIncrementally` (valor por defecto).

## 6. Comandos de la CLI (MVP)
| Comando | Qué hace |
|---|---|
| `crumb init <shell>` | Imprime el script de integración. |
| `crumb resolve` | Uso interno del script. Devuelve la ruta del historial. |
| `crumb mode [global\|folder\|project]` | Ve o cambia la elección de la carpeta actual. |
| `crumb status` | Muestra modo, raíz de proyecto y archivo en uso. |

## 7. Estructura del proyecto Go
```
crumb/
├── cmd/crumb/main.go
├── internal/
│   ├── cli/        # comandos (cobra)
│   ├── config/     # config.toml y rutas por sistema operativo
│   ├── project/    # detección de raíz de proyecto
│   ├── choice/     # choices.json
│   ├── resolve/    # lógica de la sección 4
│   ├── prompt/     # pregunta interactiva
│   └── shell/      # scripts embebidos (pwsh.ps1, bash.sh)
├── .goreleaser.yaml
└── LICENSE (MIT)
```
Dependencias previstas: `cobra` (CLI) y una librería TOML. La pregunta usa lectura simple de entrada, sin interfaz completa.

## 8. Riesgos a validar primero
1. **PowerShell recarga el historial en caliente**: `ClearHistory` y `AddToHistory` dependen de la versión de PSReadLine (Windows PowerShell 5.1 trae una antigua). Probar en pwsh 7 y en 5.1.
2. **Latencia**: arranque de `crumb` en Windows, donde el antivirus puede sumar tiempo. Medir.
3. **Pregunta dentro del prompt**: confirmar que se lee bien el teclado desde la función `prompt` y en la terminal integrada de VS Code.
4. **Marcadores demasiado agresivos**: un `package.json` en cada subpaquete de un monorepo daría muchos historiales. Revisar con proyectos reales.

## 9. Orden de trabajo propuesto
1. **Prototipo solo en script** (sin Go): cambiar de historial al hacer `cd` en PowerShell y en bash. Valida los riesgos 1 y 3.
2. `resolve` en Go con detección de proyecto y pruebas unitarias.
3. Pregunta inicial y `choices.json`.
4. `init` con los scripts embebidos y comandos `mode` y `status`.
5. Ocultar comandos sensibles.
6. Empaquetado con GoReleaser.

## 10. Resultados del prototipo (`prototype/`)
Probado en Windows PowerShell 5.1 con PSReadLine 2.0.0 y en bash de Git for Windows. Sin probar: PowerShell 7, Linux, macOS, la pregunta inicial con teclado real y la terminal de VS Code.

- **Riesgo 1 (recarga en caliente en PowerShell): funciona en 5.1.** Hallazgos que cambian el diseño:
  - `AddToHistory` también escribe en el archivo cuando el guardado es incremental. Hay que poner `HistorySaveStyle SaveNothing` mientras se carga y restaurarlo después, o se duplican las líneas.
  - En el primer `prompt` PSReadLine todavía no inició `ReadLine`. Ahí solo se cambia `HistorySavePath` y PSReadLine carga ese archivo solo. `ClearHistory` y `AddToHistory` se usan desde el segundo `prompt`.
  - Los comandos multilínea se guardan con `` ` `` al final de cada línea. Al cargar hay que volver a unirlos.
  - `AddToHistoryHandler` con espacio inicial funciona para omitir comandos.
- **bash: funciona.** Los historiales quedan separados por proyecto, carpeta y global. Las subcarpetas de un proyecto comparten su historial, `HISTCONTROL=ignorespace` omite los comandos con espacio inicial y no hay líneas duplicadas.
- **Detalle de comportamiento**: el `cd` que cambia de carpeta se guarda en el historial anterior, porque el cambio ocurre en el prompt siguiente. Es el mismo comportamiento de `zsh-per-directory-history`.
- **Pendiente**: riesgos 2 (latencia, necesita el binario Go), 3 (pregunta con teclado real) y 4 (marcadores en monorepos).

### Pruebas con tui-test (`prototype/e2e/pilot.ps1`)
[microsoft/tui-test](https://github.com/microsoft/tui-test) 0.1.1 abre un PowerShell real y envía teclas. La prueba piloto pasó 3 de 3 veces en Windows PowerShell 5.1. Cubre: la pregunta con teclado real (2 opciones sin proyecto, 3 con proyecto), que no repregunte en una subcarpeta, que la flecha arriba traiga el historial correcto, que otra carpeta tenga historial propio y que al volver se recupere.

Hallazgos:
- **Producto**: el prototipo preguntaba también en carpetas que no son proyecto. **Decisión**: fuera de un proyecto se usa el global sin preguntar.
- **Pruebas**: `submit` de tui-test espera marcadores del prompt y se cuelga mientras la pregunta bloquea; se usa `type` + `Enter`. En PowerShell 5.1 las comillas dobles dentro de argumentos a programas externos se pierden.
- Las variables de entorno se heredan de la consola que lanza la prueba: hay que limpiar `CRUMB_ANSWER`.

### Pruebas e2e automáticas
Todas usan carpetas temporales y un historial global temporal, así que no tocan el historial real.

| Prueba | Cómo | Resultado |
|---|---|---|
| `prototype/e2e/run-e2e.ps1 -Shell powershell` | tui-test, Windows PowerShell 5.1 (PSReadLine 2.0.0) | Pasa |
| `prototype/e2e/run-e2e.ps1 -Shell pwsh` | tui-test, PowerShell 7.7.0 portable (PSReadLine 2.4.5) | Pasa |
| `prototype/e2e/run-e2e.ps1 -Shell bash` | tui-test, Git Bash | Pasa 4 de 6. Las 2 primeras se colgaron sin causa identificada; desde entonces pasa 4 seguidas |
| `prototype/e2e/vscode` (`npm test`) | `@vscode/test-electron`: copia aislada de VS Code 1.147.0 y terminal integrada real. 8 variantes: integración inyectada por VS Code (`auto`, en pwsh 7 y bash), cargada a mano después de crumb y antes de crumb (en las 3 shells) | Pasan las 8 |

Escenario común: fuera de proyecto no pregunta; en proyecto pregunta con 3 opciones; subcarpeta sin repreguntar; otro proyecto en modo carpeta con historial propio; volver y recuperar; comando con espacio inicial no se guarda; revisión de los archivos. En VS Code además se comprueba que VS Code sigue detectando comandos (`onDidEndTerminalShellExecution`).

Control negativo: con el cambio de historial desactivado a propósito, la prueba de VS Code falla ("No apareció: pregunta con opción 3").

Cómo funciona la prueba de VS Code: envía texto y secuencias de teclas a la PTY (`sendText`, flecha arriba = `ESC [ A`, Ctrl+C = `\x03`) y lee la pantalla con "seleccionar todo" + "copiar" de la terminal.

En `auto` crumb se carga desde un perfil aislado: un HOME temporal con `.bashrc` en bash, y el `profile.ps1` de la copia portable de PowerShell 7 (solo actúa si `CRUMB_E2E_PROTO` está definida). En Windows PowerShell 5.1 no se prueba `auto` porque su perfil global está en System32.

No cubierto: Linux, macOS y `auto` en Windows PowerShell 5.1.
