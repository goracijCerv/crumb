# Definición del producto (v1.1)

Nombre: **crumb**

## 1. Problema
El historial de comandos del shell es global. Los comandos de todos los proyectos se mezclan, es difícil encontrar "cómo corría esto en este proyecto" y un recién llegado a un proyecto no tiene forma de saber qué comandos se usan.

## 2. Propuesta
Una capa sobre el shell que guarda y recupera el historial según el contexto (carpeta o proyecto), con la opción de usar el global. Funciona dentro de cualquier terminal, incluida la integrada de VS Code y otros editores, porque no reemplaza al emulador de terminal.

## 3. Usuarios
Desarrolladores que trabajan con varios proyectos en paralelo. Equipos que quieren documentar cómo se corre un proyecto. Se piensa publicar como herramienta abierta.

## 4. Modos de historial
| Modo | Qué guarda | Alcance |
|---|---|---|
| Global | Todo, como hoy | Todo el sistema |
| Por carpeta | Comandos ejecutados en esa carpeta | Una carpeta |
| Por proyecto | Comandos del proyecto, compartibles | Raíz del proyecto y subcarpetas sin proyecto propio |

## 5. Reglas de comportamiento
1. **Pregunta inicial**: la primera vez que se entra a un proyecto, se pregunta qué modo usar. La respuesta se recuerda y no se vuelve a preguntar. Fuera de un proyecto se usa el global sin preguntar.
2. **Detección de proyecto**: una carpeta es raíz de proyecto si tiene un marcador (archivo propio de la herramienta, `.git`, `package.json`, `*.csproj`, etc.; lista configurable).
3. **Subcarpetas**: si una subcarpeta es raíz de otro proyecto (por ejemplo un monorepo con varias apps), tiene su propio historial. Si no, usa el del proyecto padre.
4. **Cambio con `cd`**: el historial activo cambia solo al cruzar el límite de un proyecto. Moverse entre subcarpetas del mismo proyecto no lo cambia.
5. **Búsqueda**: Ctrl+R y flechas respetan el modo activo. Ampliar la búsqueda al global queda para la segunda versión.

## 6. Compartir historial
Objetivo: que alguien nuevo sepa cómo correr el proyecto.
- El historial se puede guardar dentro del proyecto para versionarlo.
- El historial crudo tiene ruido, errores de tipeo y posibles secretos. **Decisión**: el historial personal es privado por defecto y un comando **marcar** publica comandos útiles al archivo compartido del proyecto.

## 7. Datos sensibles
- Prefijo o comando para ejecutar sin guardar (como `HISTCONTROL=ignorespace` en bash).
- Lista de patrones que nunca se guardan (`password`, `token`, `--secret`, etc.).
- Valores sensibles definidos por el usuario: el comando se ejecuta con el valor real, pero se guarda con un marcador (por ejemplo `$API_KEY` o `***`).
- Revisión antes de publicar comandos al archivo compartido.

## 8. Plataformas y shells
- Windows, Linux y macOS.
- Shells: PowerShell y bash en el MVP; cmd después.
- cmd no tiene historial persistente nativo ni hooks fáciles. **Decisión**: queda fuera del MVP y se evalúa después.

## 9. Alcance del MVP
Dentro:
- Modos global, carpeta y proyecto (guardados fuera del repo).
- Pregunta la primera vez en cada proyecto, con la elección recordada. Fuera de un proyecto, global sin preguntar.
- Detección de proyecto y cambio de historial con `cd`.
- Flechas y Ctrl+R usan el historial activo.
- Forma de no guardar un comando (secretos).
- PowerShell y bash.

Segunda versión:
- Comando `marcar` y archivo compartido en el proyecto.
- Búsqueda avanzada y ampliada al global.
- Valores sensibles con marcador.
- Importar el historial global.
- Soporte de cmd.
- Terminal propia con interfaz gráfica.
- Sincronización en la nube y estadísticas.

## 10. Decisiones técnicas
- Lenguaje: **Go**. Un binario único por plataforma, más scripts de integración por shell.
- Distribución: compilación cruzada y publicación con GoReleaser.

## 11. Decisiones de comportamiento
- **Importar historial global**: segunda versión. Será opcional: en la pregunta inicial se ofrecerá empezar vacío o importar los últimos N comandos del global.
- **Varias terminales en el mismo proyecto**: cada comando se escribe al archivo al ejecutarse, sin esperar a cerrar la terminal, así las sesiones se ven entre sí.
- **Distinta shell en el mismo proyecto**: PowerShell y bash tienen historiales separados en el MVP, porque guardan formatos distintos. Unificarlos llega con el formato propio de la segunda versión.
- **Mover o renombrar un proyecto**: el historial está ligado a la ruta. `crumb move <vieja> <nueva>` lo reasigna.
- **Idioma**: mensajes del programa y documentación pública en inglés; README también en español. Los documentos de diseño siguen en español.
- **Privacidad**: sin telemetría. crumb no se conecta a internet.
- **Licencia**: MIT.
- **Instalación**: scoop, winget y brew, publicados con GoReleaser. `crumb setup` añade la línea al perfil del shell; `crumb setup --remove` la quita y `crumb purge` borra los datos.

## 12. Pendiente
- Ninguno.