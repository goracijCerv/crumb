# Plan de tareas del MVP en Go (v1.0)

Diseño: [DISENO.md](DISENO.md). Cada tarea se cierra con su **definición de terminado** (DISENO §8): pruebas unitarias en verde en Windows, Linux y macOS; escenario e2e en verde con el binario si la tarea lo afecta; documentación actualizada.

## Decisiones tomadas
| # | Decisión | Elegido |
|---|---|---|
| D1 | Quién hace la pregunta inicial | El script del shell. El binario responde `ask` y el script guarda con `crumb mode`. |
| D2 | Monorepos | Gana el marcador más cercano. `.crumb` con `scope = "root"` une todo el árbol en un proyecto. |
| D3 | Configuración | `config.toml` opcional: `markers` e `ignore`. |
| D4 | Nombre del archivo | `<carpeta>-<hash8>.<shell>.txt` |
| D5 | Si crumb falla | Se mantiene el historial actual, un aviso por sesión, el prompt nunca se bloquea. |
| D6 | Desactivar | `CRUMB_DISABLE=1` y `crumb off` / `crumb on`. |
| E1 | Mover un proyecto | `crumb move <vieja> <nueva>`. |
| E2 | Idioma | Mensajes y docs públicas en inglés; README también en español; diseño en español. |
| E3 | Distinta shell, mismo proyecto | Historiales separados en el MVP. |
| E4 | Tamaño máximo | El límite de cada shell (`MaximumHistoryCount`, `HISTSIZE`). |
| E5 | Desinstalar | `crumb setup --remove` y `crumb purge`, con confirmación. |
| E6 | Telemetría | Ninguna. |
| E7 | Definición de terminado | Ver arriba. |

Ajustes que salieron al juntar las decisiones (ya en DISENO):
- **Función `crumb` en la sesión**: `off`, `on` y `mode` cambian la sesión del shell, y un binario no puede hacerlo. El script define una función que envuelve al binario.
- **Elecciones por clave exacta**: no se heredan de carpetas padre, para que cada proyecto anidado pregunte por separado (D2).
- **El directorio personal nunca es proyecto**: un repo de dotfiles en `~` convertiría todo en un proyecto.
- **CLI con `flag` de la librería estándar** en lugar de `cobra`: pocos subcomandos, una dependencia menos.

## Fase 0. Base
| Tarea | Contenido | Se acepta cuando |
|---|---|---|
| **T0.1 Esqueleto** | Módulo `github.com/goracijCerv/crumb`, estructura de DISENO §7, `crumb version`, `go vet`, `gofmt`. | `go build ./...` y `go test ./...` pasan en local. |
| **T0.2 CI** | GitHub Actions: `go vet`, `gofmt -l`, `go test -race` en `windows-latest`, `ubuntu-latest` y `macos-latest`. | CI en verde en las 3. |

## Fase 1. Núcleo (sin shell)
| Tarea | Contenido | Pruebas |
|---|---|---|
| **T1 Rutas** | `paths`: config, elecciones e historiales por SO; `CRUMB_HOME`. | Unitarias por SO en CI. |
| **T2 Proyecto** | `project`: normalización, raíz (más cercano, `.crumb scope=root`, HOME y raíz del disco excluidos), nombre de archivo. | Tabla: sin proyecto, proyecto, subcarpeta, anidado, `scope=root`, `~` con `.git`, `C:\X` vs `c:\x`, espacios y comillas, enlace simbólico. |
| **T3 Configuración** | `config`: `config.toml` y `.crumb`, valores por defecto, errores claros si el TOML es inválido. | Archivo ausente, válido, inválido, campos desconocidos. |
| **T4 Elecciones** | `choices`: `choices.json` versionado, escritura atómica con bloqueo. | 20 escrituras concurrentes dejan un JSON válido; archivo corrupto da error claro sin borrar nada. |
| **T5 `crumb resolve`** | Algoritmo de DISENO §4 y su formato de salida. | Tabla con los casos de T2 y T4. Tiempo < 50 ms en Windows (riesgo 2). |

## Fase 2. Integración con shells
| Tarea | Contenido | Pruebas |
|---|---|---|
| **T6 `crumb init`** | Scripts `pwsh.ps1` y `bash.sh` embebidos, a partir del prototipo: cambio de carpeta, pregunta, recarga, función `crumb`, D5 y D6. | e2e del prototipo apuntando al binario: tui-test (powershell, pwsh, bash) y VS Code (8 variantes). Caso nuevo: binario ausente → aviso único y prompt usable. |
| **T7 Sensibles** | Espacio inicial y `ignore` en `AddToHistoryHandler` y `HISTIGNORE`. | e2e con `ignore = ["*password*"]`. |
| **T8 `mode`, `status`, `off`, `on`** | Comandos de DISENO §6 que tocan la sesión. | e2e: cambiar a global y ver el global con flecha arriba; `off` y `on`. |
| **T9 Varias terminales** | Un comando de una terminal aparece en otra del mismo proyecto. | e2e con dos sesiones de tui-test. Documentar lo que haga PSReadLine. |

## Fase 3. Mantenimiento, multiplataforma y publicación
| Tarea | Contenido | Pruebas |
|---|---|---|
| **T10 `move` y `purge`** | E1 y E5. | Unitarias con carpetas temporales. |
| **T11 `setup`** | Añadir y quitar la línea del perfil, con confirmación y respaldo. | Unitarias sobre perfiles temporales. Nunca toca el perfil real en pruebas. |
| **T12 e2e en Linux y macOS** | tui-test con bash y pwsh en CI. | CI en verde. |
| **T13 Publicación** | GoReleaser: binarios, scoop, winget, brew. README en inglés y español. Release `v0.1.0`. | Instalación limpia en Windows con scoop y en Linux. |

## Orden
T0.1 → T0.2 → T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13.
T1 a T4 son independientes entre sí; el orden es solo por comodidad.

## Fuera del MVP
`marcar` y archivo compartido, búsqueda ampliada al global, valores sensibles con marcador, importar el global, historial único entre shells, cmd y terminal propia. Ver PRODUCTO §9.
