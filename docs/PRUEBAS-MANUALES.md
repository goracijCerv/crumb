# Pruebas manuales del prototipo

Sirven para lo que los scripts automáticos no cubren: teclado real, la pregunta inicial y la terminal de VS Code.
Se repiten con cada shell: PowerShell (`crumb-proto.ps1`) y bash (`source crumb-proto.sh`).

## Preparación
Usa un historial de prueba aparte para no tocar el tuyo:

- PowerShell: `$env:CRUMB_HOME = "$env:TEMP\crumb-manual"`, luego `. .\prototype\crumb-proto.ps1`
- bash: `export CRUMB_HOME=/tmp/crumb-manual`, luego `source prototype/crumb-proto.sh`

Crea tres carpetas de prueba:
```
mkdir demo\proyecto\.git, demo\proyecto\sub, demo\otra\.git, demo\suelta
```
Cierra la terminal al terminar. Nada de esto es permanente.

## Casos
| # | Pasos | Resultado esperado | OK |
|---|---|---|---|
| 1 | `cd demo\proyecto` | Pregunta con 3 opciones (global, carpeta, proyecto) | |
| 2 | Responde `3`, ejecuta `echo uno` y `echo dos` | Los comandos se ejecutan normal | |
| 3 | `cd sub` | No vuelve a preguntar. Flecha arriba muestra `echo dos` | |
| 4 | `cd ..\..\otra`, responde `2` | Flecha arriba **no** muestra `echo dos` | |
| 5 | Ejecuta `echo tres`, luego `cd ..\suelta` | No pregunta (no es proyecto). Flecha arriba muestra tu historial global de siempre | |
| 6 | `cd ..\proyecto` | No pregunta. Flecha arriba muestra `echo dos` | |
| 7 | Escribe ` echo secreto` (con espacio al inicio) y Enter | Se ejecuta, pero no aparece con flecha arriba | |
| 8 | Ctrl+R y busca `echo` | Solo salen comandos del historial activo | |
| 9 | Cierra la terminal, ábrela de nuevo, carga el prototipo y entra a `proyecto` | No pregunta. Flecha arriba conserva `echo dos` | |
| 10 | Abre dos terminales en `proyecto`. Ejecuta un comando en una | Aparece en la otra tras un `Enter` (bash: hace falta `history -n`; en PowerShell no se espera) | |
| 11 | Escribe un comando de varias líneas (PowerShell: termina una línea con `` ` ``) y recupéralo con flecha arriba | Vuelve completo | |
| 12 | Repite los casos 1 a 6 dentro de la terminal integrada de VS Code | Mismo resultado | |

## Cosas a observar
- ¿Se nota demora al hacer `cd`?
- ¿La pregunta se lee bien y acepta Enter como global?
- ¿Algo se imprime de más en el prompt?

Anota qué falla y en qué shell. El caso 10 puede no cumplirse hoy: es información para el diseño, no un fallo del prototipo.
