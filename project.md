# Proyecto: Portable Development Environment

**Estado:** Diseño conceptual / exploración de arquitectura  
**Lenguaje propuesto:** Go  
**Plataformas objetivo:** Linux y macOS  
**Filosofía:** Plug & Play, portable, no invasivo y ejecutado directamente sobre el host.

> **Nota:** este documento es la propuesta original y se conserva como referencia histórica. Las decisiones vigentes están en [arch.md](arch.md) y [roadmap.md](roadmap.md). En particular: el nombre definitivo es `ditto` (no `mydev`); **mise** reemplaza a pkgx como mecanismo de obtención de binarios; Neovim se distribuye con **LazyVim** (LSPs vía Mason); y el binario incluye un **menú de setup** para elegir componentes en el primer uso.

## 1. Objetivo principal

Construir una herramienta que permita desplegar un entorno de desarrollo personal completo y reproducible en cualquier servidor Linux o equipo macOS, ejecutando **un único binario**, sin configuraciones manuales ni modificaciones globales al sistema operativo.

La experiencia deseada es:

1. Conectarse a cualquier servidor mediante SSH.
2. Copiar o descargar el binario de la herramienta.
3. Ejecutarlo.
4. Esperar a que prepare automáticamente el entorno.
5. Comenzar a utilizar Neovim, OpenCode y otras herramientas con las configuraciones personales del usuario.

**Principio fundamental:** El usuario quiere llevar su entorno de desarrollo a cualquier máquina, no adaptar cada máquina a su entorno.

## 2. Problema que intenta resolver

Actualmente se utiliza VS Code con Remote-SSH para trabajar en servidores remotos.

VS Code ofrece una experiencia cómoda para instalar extensiones y mantener herramientas de desarrollo, pero se busca migrar hacia un flujo basado en terminal con Neovim.

Entre las principales ventajas identificadas de Neovim están:

- Mayor velocidad y menor consumo de recursos.
- Navegación completamente mediante teclado.
- Fuzzy Finder para búsqueda por nombre y contenido de archivos.
- Personalización mediante plugins.
- Integración natural con herramientas CLI.

El problema aparece al trabajar en múltiples servidores con distintos sistemas operativos, arquitecturas, dependencias y herramientas preinstaladas.

Configurar Neovim, sus plugins, LSPs y herramientas auxiliares individualmente en cada servidor representa una carga de mantenimiento importante.

### 2.1. Por qué Docker no es la solución ideal

Inicialmente se consideró distribuir el entorno dentro de un contenedor Docker, montando los repositorios como volúmenes.

Sin embargo, el trabajo realizado requiere interactuar directamente con el hardware y las herramientas de los servidores.

Por ejemplo:

- Herramientas de administración NVMe.
- Utilidades de diagnóstico de hardware.
- Comandos del sistema operativo.
- Dispositivos y recursos físicos del servidor.
- Software especializado previamente instalado en el host.

Utilizar Docker complicaría el acceso directo a estas capacidades.

**Decisión conceptual:** No utilizar contenedores para aislar el entorno de desarrollo.

En su lugar, ejecutar las herramientas directamente como procesos nativos del host, conservando sus permisos y capacidades habituales.

## 3. Experiencia de usuario deseada

El objetivo es conseguir una experiencia similar a un entorno virtual de Python, pero aplicada a todo el tooling de desarrollo.

Ejemplo:

```bash
ssh usuario@servidor

./mydev
```

Después de ejecutar `mydev`, se abre una shell preparada:

```bash
nvim proyecto/
opencode
rg "search_term"
fd "*.py"
nvme list
```

En esta sesión:

- `nvim` corresponde a la versión personalizada del entorno.
- `opencode` utiliza las configuraciones y MCPs personales.
- `rg` y `fd` corresponden a los binarios gestionados por el entorno.
- `nvme` continúa siendo el comando original del host.
- El resto de las herramientas del sistema siguen disponibles.

Al salir de la shell, el entorno original permanece intacto.

La instalación debe ser persistente para evitar descargar todo en cada ejecución, pero su activación debe limitarse a la sesión correspondiente.

## 4. Requisitos funcionales

### 4.1. Binario único como punto de entrada

Desarrollar una CLI en Go que funcione como orquestador.

Nombre provisional: `mydev`.

El usuario no debería necesitar ejecutar scripts adicionales, instalar paquetes manualmente ni mantener archivos YAML para iniciar el entorno.

El binario debe encargarse de:

- Detectar el sistema operativo.
- Detectar la arquitectura de CPU.
- Descargar las herramientas compatibles.
- Seleccionar las versiones definidas.
- Preparar directorios y configuraciones.
- Configurar variables de entorno.
- Iniciar una shell con las herramientas disponibles.
- Reutilizar descargas existentes.

El objetivo es distribuir un ejecutable de Go compilado para cada combinación de sistema y arquitectura soportada, no necesariamente un mismo archivo ejecutable para todas las plataformas.

### 4.2. Instalación no invasiva

No instalar herramientas globalmente mediante `apt`, `brew` u otros gestores del sistema.

Tampoco modificar permanentemente:

- `/usr/bin`
- `/usr/local/bin`
- `/etc`
- La configuración global de shell.
- Los archivos personales de configuración existentes.

Los recursos gestionados deben almacenarse en un directorio controlado por la aplicación.

Estructura conceptual:

```text
workspace/
├── .mydev/
│   ├── bin/
│   │   ├── nvim
│   │   ├── opencode
│   │   ├── rg
│   │   └── fd
│   ├── config/
│   │   ├── nvim/
│   │   └── opencode/
│   ├── data/
│   └── cache/
│
├── proyecto-a/
└── proyecto-b/
```

Esta estructura es orientativa y todavía no está definida.

Debe evaluarse si conviene almacenar las herramientas dentro de cada workspace o usar una caché compartida en el directorio personal del usuario para evitar descargas duplicadas.

### 4.3. Activación temporal del entorno

El binario debe abrir una shell hija con variables de entorno preparadas.

Ejemplo conceptual:

```bash
export PATH="$MYDEV_ROOT/bin:$PATH"
export XDG_CONFIG_HOME="$MYDEV_ROOT/config"
export XDG_DATA_HOME="$MYDEV_ROOT/data"
export XDG_CACHE_HOME="$MYDEV_ROOT/cache"
```

De esta manera, los binarios personalizados tienen prioridad sin reemplazar los comandos originales del host.

Es importante considerar que las variables XDG también pueden afectar a herramientas externas. Debe evaluarse la conveniencia de utilizar variables específicas por aplicación para minimizar efectos secundarios.

### 4.4. Compatibilidad multiplataforma

Soporte inicial deseado:

| Sistema | Arquitectura |
|---|---|
| Linux | x86_64 |
| Linux | ARM64 |
| macOS | Apple Silicon ARM64 |
| macOS | Intel x86_64 |

Debe existir una estrategia de resolución de versiones y binarios por plataforma.

También deben verificarse requisitos como glibc, musl y versiones mínimas del sistema operativo para evitar descargar ejecutables incompatibles.

### 4.5. Gestión de herramientas

Herramientas iniciales consideradas:

| Herramienta | Propósito |
|---|---|
| Neovim | Editor principal |
| OpenCode | Agente de programación con IA |
| ripgrep | Búsqueda de contenido |
| fd | Búsqueda de archivos |
| fzf | Fuzzy Finder |
| lazygit | Interfaz Git en terminal |
| Herramientas LSP | Integración con Neovim |

La lista debe ser ampliable y configurable internamente, sin que el usuario necesite editar manifiestos para el uso cotidiano.

## 5. Integración con OpenCode

OpenCode es una parte importante del entorno.

No basta con descargar su ejecutable: también es necesario distribuir sus configuraciones.

Esto incluye:

- Proveedores y modelos configurados.
- MCP servers.
- Instrucciones y prompts personalizados.
- Comandos y otras personalizaciones.
- Configuraciones que dependan del sistema operativo.

Las configuraciones deben distribuirse junto con la herramienta o incorporarse al ejecutable Go mediante `go:embed`.

### Gestión de secretos

No incorporar API keys, credenciales o tokens privados al ejecutable ni al repositorio.

Utilizar variables de entorno, almacenes de credenciales o mecanismos seguros equivalentes.

El entorno debe poder identificar credenciales faltantes y notificarlo sin bloquear herramientas que no las necesitan.

### MCP servers

Considerar que algunos MCPs tienen dependencias adicionales:

- Node.js.
- Python.
- Binarios externos.
- Servicios remotos.
- Permisos o recursos del host.

La herramienta debe contemplar la preparación de estas dependencias sin contaminar globalmente el sistema.

## 6. Herramientas open source consideradas

### Chezmoi

Repositorio: https://github.com/twpayne/chezmoi

Permite gestionar configuraciones y dotfiles, incluyendo plantillas y lógica condicional dependiendo del sistema operativo.

**Ventajas:**
- Configuraciones multiplataforma.
- Templates.
- Scripts.
- Gestión declarativa de dotfiles.

**Limitación para este proyecto:** No cubre por sí solo toda la experiencia de adquisición, preparación y ejecución de herramientas que se desea.

Podría aprovecharse únicamente como motor de configuración.

### GNU Stow

Permite gestionar configuraciones mediante enlaces simbólicos.

No resuelve la detección del sistema operativo ni la descarga de ejecutables.

No se considera suficiente como componente principal.

### Devbox

Repositorio: https://github.com/jetify-com/devbox

Ofrece entornos de desarrollo reproducibles utilizando Nix como backend.

Permite preparar shells con dependencias específicas por proyecto.

Es una alternativa interesante, pero introduce una infraestructura y un modelo de configuración que podrían resultar excesivos para la experiencia plug and play buscada.

### pkgx

Repositorio: https://github.com/pkgxdev/pkgx

Herramienta especialmente interesante porque permite obtener y ejecutar paquetes sin depender de instalaciones tradicionales del sistema.

**Propuesta:** Evaluar pkgx como mecanismo interno para resolver y obtener herramientas compatibles con cada plataforma.

De esta manera:

- Go implementaría la interfaz y la orquestación.
- pkgx gestionaría la resolución de paquetes y dependencias que soporte.
- Un mecanismo alternativo descargaría releases oficiales cuando pkgx no cubra una herramienta.

Esta integración sigue siendo una hipótesis de arquitectura. Hay que validar si pkgx ofrece las APIs, comandos, cobertura de paquetes y comportamiento de aislamiento necesarios.

## 7. Arquitectura conceptual propuesta

```text
                   USUARIO
                      |
                  ./mydev
                      |
             ORQUESTADOR GO
                      |
          +-----------+-----------+
          |           |           |
      Platform     Package      Config
      Detector     Manager      Manager
          |           |           |
     Linux/macOS     pkgx      Embedded
     amd64/arm64   / releases    configs
          |           |           |
          +-----------+-----------+
                      |
              Workspace Manager
                      |
            Environment Builder
                      |
               Launch Subshell
                      |
          +-----------+-----------+
          |           |           |
        Neovim     OpenCode     Host CLI
          |           |           |
       Plugins       MCPs      NVMe/etc.
```

### Responsabilidades propuestas

**Go Orchestrator**
- Punto de entrada único.
- Detección de plataforma.
- Instalación y actualización.
- Preparación del entorno.
- Manejo de errores.
- Lanzamiento de la shell.

**Package Manager Adapter**
- Comunicación con pkgx u otros mecanismos.
- Selección de paquetes.
- Resolución de versiones.
- Caché y reutilización.
- Fallback para herramientas no soportadas.

**Configuration Manager**
- Extracción de configuraciones embebidas.
- Adaptación multiplataforma.
- Preparación de Neovim y OpenCode.
- Configuración de MCPs.

**Environment Manager**
- Preparación de variables.
- Aislamiento lógico de las herramientas.
- Compatibilidad con los comandos del host.
- Creación de shells temporales.

## 8. Principios de diseño

1. **Plug & Play:** El usuario ejecuta un comando y obtiene su entorno preparado.
2. **No invasivo:** Sin modificar instalaciones o configuraciones globales.
3. **Native execution:** Las herramientas se ejecutan directamente en el host, no dentro de Docker.
4. **Multiplataforma:** Linux y macOS con distintas arquitecturas.
5. **Reproducible:** Versiones controladas y configuraciones consistentes.
6. **Offline after setup:** Reutilizar las herramientas descargadas cuando no exista conexión.
7. **Extensible:** Posibilidad de agregar binarios, configuraciones y MCPs.
8. **Host-first:** Preservar el acceso al hardware, comandos y permisos originales del servidor.
9. **Minimal interaction:** Evitar asistentes, prompts o configuraciones manuales innecesarias.
10. **Single entry point:** Toda la complejidad queda oculta detrás del ejecutable Go.

## 9. Aspectos pendientes de diseño

Todavía no se han tomado decisiones definitivas sobre:

- **Workspace scope:** Dónde instalar físicamente las herramientas y cómo compartirlas entre repositorios.
- **Shell lifecycle:** Cómo activar y desactivar el entorno sin efectos secundarios.
- **pkgx:** Verificar su compatibilidad y si puede operar como backend transparente.
- **Bootstrap:** Cómo distribuir el ejecutable correcto para cada arquitectura.
- **OpenCode:** Validar variables de configuración, rutas y dependencias reales de los MCPs.
- **Neovim:** Estrategia para instalar plugins, LSPs, parsers de Treesitter y otras dependencias.
- **Actualizaciones:** Cómo actualizar versiones sin romper un entorno funcional.
- **Rollback:** Posibilidad de recuperar versiones anteriores.
- **Entornos sin internet:** Qué grado de funcionalidad debe ofrecerse.
- **Distribuciones Linux:** Compatibilidad entre entornos con distintas bibliotecas del sistema.
- **Seguridad:** Verificación de checksums, firmas de descargas y manejo de credenciales.
- **Sesiones existentes:** Cómo integrar herramientas como tmux o Zellij, si se consideran necesarias.

## 10. MVP propuesto

La primera versión debería enfocarse exclusivamente en demostrar la experiencia central:

**Copiar un ejecutable Go, correrlo y obtener una shell con Neovim y OpenCode configurados, sin modificar el host.**

Alcance sugerido:

1. Detectar OS y arquitectura.
2. Preparar el directorio de trabajo.
3. Obtener Neovim, OpenCode, ripgrep, fd y fzf.
4. Aplicar configuraciones personales embebidas.
5. Activar las variables de entorno requeridas.
6. Abrir una shell interactiva.
7. Garantizar que los comandos originales del host siguen disponibles.
8. Permitir cerrar la sesión y regresar al entorno anterior sin cambios persistentes fuera del directorio gestionado.

No incorporar inicialmente una interfaz gráfica, daemon, contenedores, sincronización distribuida ni un gestor complejo de proyectos.

## 11. Visión final

La herramienta no pretende ser un reemplazo generalista de Docker, Nix, Devbox o Chezmoi.

Su finalidad es proporcionar un **Portable Personal Development Environment**.

Debe funcionar como un entorno personal empaquetado, capaz de desplegarse en servidores heterogéneos con mínima intervención.

La intención final puede resumirse así:

> Quiero conectarme a cualquier servidor por SSH