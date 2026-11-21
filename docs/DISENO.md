# Diseño técnico del MVP (v1.0)

Producto: [PRODUCTO.md](PRODUCTO.md). Plan de trabajo: [TAREAS.md](TAREAS.md).

## 1. Idea central
El shell ya guarda y recupera su historial. `crumb` solo decide **qué archivo de historial usa el shell** según la carpeta, y el shell lo carga. No captura comandos ni reemplaza flechas ni Ctrl+R.

```
prompt ──(¿cambió la carpeta?)──► crumb resolve ──► modo + ruta del archivo
   ▲                                                        │
   └──── el script cambia el archivo y recarga el historial ◄┘
```

## 2. Piezas y responsabilidades
| Pieza | Hace | No hace |
|---|---|---|
| **Binario `crumb` (Go)** | Detectar el proyecto, normalizar rutas, nombrar archivos, leer y guardar elecciones y configuración, comandos de mantenimiento (`move`, `setup`, `purge`). | Leer el teclado ni tocar la sesión del shell. |
| **Script de integración** (`pwsh.ps1`, `bash.sh`, embebidos con `go:embed`) | Detectar el cambio de carpeta, llamar a `crumb resolve`, **hacer la pregunta inicial** (D1), cambiar y recargar el historial, omitir comandos sensibles, definir la función `crumb` de la sesión. | Lógica de proyecto o de archivos: todo eso lo decide el binario. |

Se instala con una línea en el perfil, que también puede añadir `crumb setup`:
- PowerShell: `Invoke-Expression (& crumb init pwsh | Out-String)`
- bash: `eval "$(crumb init bash)"`

**Función `crumb` de la sesión.** El binario no puede cambiar el estado del shell que lo llamó. Por eso el script define una función `crumb` que envuelve al binario: `crumb off`, `crumb on` y `crumb mode` se resuelven en la función (desactivar o recargar el historial) y el resto se pasa al binario.

## 3. Almacenamiento
Todo vive fuera de los proyectos. Ningún repo se ensucia en el MVP.

| Qué | Windows | Linux / macOS |
|---|---|---|
| Configuración (`config.toml`) | `%APPDATA%\crumb\` | `$XDG_CONFIG_HOME/crumb/` o `~/.config/crumb/` |
| Elecciones (`choices.json`) | `%APPDATA%\crumb\` | igual que la configuración |
| Historiales | `%LOCALAPPDATA%\crumb\histories\` | `$XDG_DATA_HOME/crumb/histories/` o `~/.local/share/crumb/histories/` |

`CRUMB_HOME=<dir>` manda todo a `<dir>/config` y `<dir>/histories` (pruebas y usuarios avanzados).

### Nombre del archivo de historial (D4)
`<carpeta>-<hash8>.<shell>.txt`, por ejemplo `api-3f9a1c0b.pwsh.txt`.
- `<carpeta>`: último segmento de la ruta, con los caracteres no seguros cambiados por `_`.
- `<hash8>`: primeros 8 caracteres hex de SHA-256 de la ruta normalizada.
- `<shell>`: `pwsh` (Windows PowerShell y PowerShell 7 comparten formato) o `bash`.

### Normalización de rutas
Absoluta, limpia (`filepath.Clean`) y con enlaces simbólicos resueltos. En Windows además: minúsculas y `\` como separador, porque `C:\Repo` y `c:\repo` son la misma carpeta. Es la clave de todo: elecciones y nombres de archivo usan la ruta normalizada.

### Formato del historial
El nativo de cada shell. El shell sigue leyendo y escribiendo su propio formato, así que no hay que capturar comandos. Por eso PowerShell y bash tienen historiales separados en el mismo proyecto (E3). En modo global se usa el archivo original del shell y no se toca.

Costo de esta decisión: no hay fecha, carpeta ni código de salida por comando. `marcar` y la búsqueda avanzada (segunda versión) necesitarán un formato propio o un índice aparte.

### `choices.json`
```json
{
  "version": 1,
  "choices": {
    "c:\\users\\yo\\repos\\app": "project",
    "c:\\users\\yo\\repos\\tools": "folder"
  }
}
```
- Se escribe de forma atómica (archivo temporal y renombrado) y con bloqueo, porque dos terminales pueden escribir a la vez.
- `version` permite migrar el formato más adelante.

### `config.toml` (D3)
Opcional. Sin archivo se usan estos valores:
```toml
# Archivos o carpetas que marcan la raíz de un proyecto
markers = [".git", ".crumb", "package.json", "go.mod", "Cargo.toml", "pyproject.toml", "*.csproj", "*.sln"]

# Comandos que nunca se guardan (glob sobre la línea completa).
# Además, un comando que empieza con espacio nunca se guarda.
ignore = []
```
El binario entrega la configuración al script en `crumb init` (así no se lee en cada prompt). Cambiarla requiere abrir una terminal nueva.

### Archivo `.crumb` en un proyecto (D2)
Opcional. Su presencia marca una raíz de proyecto. Con `scope = "root"`, todo el árbol de debajo es un solo proyecto aunque contenga otros marcadores (monorepo con un solo historial).
```toml
scope = "root"
```

## 4. Resolución del historial
`crumb resolve --shell pwsh|bash --cwd <ruta>` imprime una sola línea, separada por tabulador:

| Salida | Significado |
|---|---|
| `global` | Usar el archivo global del shell. |
| `folder<TAB><archivo>` | Historial propio de esta carpeta. |
| `project<TAB><archivo>` | Historial del proyecto. |
| `ask<TAB><raíz>` | Proyecto sin elección guardada: el script pregunta. |

Código de salida distinto de 0 = error (ver D5).

Algoritmo:
1. Normalizar `cwd`.
2. **Raíz de proyecto**: subir desde `cwd` hasta el primer directorio con un marcador. Gana el más cercano. Si más arriba hay un `.crumb` con `scope = "root"`, gana ese. El directorio personal y la raíz del disco nunca son proyecto (evita que un repo de dotfiles en `~` convierta todo en un proyecto).
3. **Clave**: la raíz si hay proyecto; si no, `cwd`.
4. **Elección guardada** para la clave exacta (no se heredan elecciones de carpetas padre: un proyecto anidado pregunta por separado).
5. Sin elección: fuera de proyecto → `global`. En proyecto → `ask`.
6. Con elección: `project` usa la raíz; `folder` usa `cwd`; `global` no usa archivo.

Tras la pregunta, el script guarda la respuesta con `crumb mode <modo> --path <raíz>` y vuelve a resolver. Esto pasa una sola vez por proyecto.

Si no hay terminal interactiva (scripts, tareas automáticas), el script no pregunta y usa el global.

## 5. Integración con cada shell
Regla: llamar a `crumb` **solo cuando cambia la carpeta**, no en cada comando, para no pagar el arranque del proceso.

### bash
- Se engancha en `PROMPT_COMMAND`, sin romper otros ganchos (por ejemplo la integración de VS Code).
- Al cambiar `$PWD` y al abrir: `history -a` (guarda lo pendiente en el archivo anterior), `HISTFILE=<archivo>`, `history -c`, `history -r`.
- En cada prompt: `history -a` para que otras terminales vean el comando.
- Sensibles: `HISTCONTROL=ignorespace` y `HISTIGNORE` con los patrones de `ignore`.

### PowerShell (5.1 y 7)
- Se envuelve la función `prompt`, conservando la anterior.
- Al cambiar `$PWD`: `HistorySaveStyle SaveNothing`, `HistorySavePath <archivo>`, `ClearHistory()`, cargar con `AddToHistory()` uniendo los comandos multilínea (líneas que terminan en `` ` ``), y restaurar el estilo de guardado. En el primer prompt solo se cambia la ruta, porque PSReadLine aún no cargó nada (hallazgos del prototipo, §10).
- Sensibles: `AddToHistoryHandler` devuelve `SkipAdding` si el comando empieza con espacio o coincide con `ignore`.

### Fallos y desactivación (D5, D6)
- Si `crumb` no está en el PATH o `resolve` falla: se mantiene el historial actual, se muestra **un** aviso por sesión y el prompt sigue. Nunca se bloquea ni se lanza una excepción en el prompt.
- `CRUMB_DISABLE=1` antes de cargar: el script no se instala.
- `crumb off`: vuelve al global y deja de resolver en esta sesión. `crumb on` lo reactiva.

## 6. Comandos
Mensajes en inglés (E2).

| Comando | Dónde se ejecuta | Qué hace |
|---|---|---|
| `crumb init <shell>` | binario | Imprime el script de integración con la configuración incluida. |
| `crumb resolve` | binario (interno) | Sección 4. |
| `crumb mode [global\|folder\|project] [--path <dir>]` | función + binario | Sin argumento muestra el modo; con argumento lo guarda y la función recarga el historial. |
| `crumb status` | binario | Modo, raíz de proyecto, archivo en uso y rutas de datos. |
| `crumb off` / `crumb on` | función | Desactiva o reactiva crumb en la sesión. |
| `crumb move <vieja> <nueva>` | binario | Reasigna elecciones e historiales tras mover un proyecto (E1). |
| `crumb setup <shell> [--remove]` | binario | Añade o quita la línea del perfil. Pide confirmación y hace respaldo del perfil. |
| `crumb purge` | binario | Borra elecciones e historiales de crumb. Pide confirmación. No toca los historiales globales del shell. |
| `crumb version` | binario | Versión. |

## 7. Estructura del proyecto Go
```
cmd/crumb/main.go
internal/
  cli/       subcomandos (paquete flag de la librería estándar)
  paths/     rutas por sistema operativo y CRUMB_HOME
  project/   detección de raíz, normalización, nombre de archivo
  config/    config.toml y .crumb
  choices/   choices.json con escritura atómica y bloqueo
  resolve/   sección 4
  shell/     scripts embebidos (pwsh.ps1, bash.sh) y generación de init
prototype/   prototipo y pruebas e2e (se reutilizan con el binario)
```
- Go 1.27 (versión estable actual).
- Dependencias: solo `github.com/BurntSushi/toml`. La CLI usa `flag` de la librería estándar: son pocos subcomandos y no hace falta `cobra`.

## 8. Estrategia de pruebas
- **Unitarias** (`go test`): tablas de casos con `t.TempDir()`. Corren en Windows, Linux y macOS en CI.
- **e2e**: las de `prototype/e2e` (tui-test y VS Code) apuntando al binario en lugar del prototipo. Mismo escenario, mismas aserciones.
- **Rendimiento**: `crumb resolve` debe tardar menos de 50 ms en Windows (medido en CI y en local).
- **Definición de terminado de cada tarea** (E7): pruebas unitarias en verde en las 3 plataformas, escenario e2e en verde con el binario cuando la tarea lo afecta, y documentación actualizada.

## 9. Riesgos
| # | Riesgo | Estado |
|---|---|---|
| 1 | PowerShell recarga el historial en caliente | Validado en 5.1 y 7 (§10). |
| 2 | Latencia de arranque de `crumb` en Windows (antivirus) | Pendiente: se mide en T4. |
| 3 | Pregunta dentro del prompt y en VS Code | Validado en las 3 shells y en VS Code (§10). |
| 4 | Marcadores demasiado agresivos en monorepos | Resuelto con D2 (`.crumb scope = "root"`). |
| 5 | Rutas con espacios, comillas o mayúsculas distintas | Cubierto por la normalización y pruebas en T2. |
| 6 | bash: cuelgue intermitente en las e2e con tui-test | 2 de 6 al inicio, sin causa. Vigilar en CI. |

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

### Prueba piloto con tui-test (reemplazada por `prototype/e2e/run-e2e.ps1`)
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
