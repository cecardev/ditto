# Harness de Claude Code para ditto

Skills y agentes para llevar ditto del roadmap a código, con GitHub Issues como fuente de verdad del trabajo. Basado en el framework de Dexbot, adaptado a un solo proyecto Go con fases, hitos y spikes.

**Regla:** toda interacción con GitHub se hace con la CLI **`gh`**. El MCP de GitHub está denegado en `settings.json`.

## Flujo

```
/story-status ─► /generate-stories ─► /create-story ─► /develop-story <N> ─► PR (Closes #N) ─► merge
 (dónde estamos)  (qué sigue)          (issue estándar)  │
                                                         ├─ standards-reviewer  (revisión del diff)
                                                         ├─ platform-tester     (matriz Linux en Docker)
                                                         └─ /record-decision    (spikes → arch.md)

/develop-batch <#N …|fase n|hito Hx.y>: grafo de dependencias → plan en oleadas → confirmación
  → N × story-developer (worktrees en paralelo) → standards-reviewer / platform-tester
  → integración en batch/<slug> → un solo PR para el lote (un Closes #N por story)
/check-standards: self-review en cualquier momento
```

## Skills

| Skill | Uso | Qué hace |
|---|---|---|
| `story-status` | `/story-status [fase\|hito\|estado\|area:x]` | Progreso por fase e hito (issues + PRs + roadmap.md), bloqueos, inconsistencias entre roadmap y GitHub, y qué conviene hacer después. Solo lectura. |
| `generate-stories` | `/generate-stories [fase\|hito]` | Lee arch.md, roadmap.md y project.md, revisa el estado real del repo y los issues, y propone las siguientes stories respetando el orden del roadmap y las decisiones pendientes. Crea solo las aprobadas (vía `create-story`). |
| `create-story` | `/create-story [hito o descripción]` | Plantilla y convenciones de los issues: título `[H1.2] área: …`, labels `type/area/priority/size`, milestone por fase, `Depende de: #N`, body de [story](skills/create-story/templates/story.md) o [spike](skills/create-story/templates/spike.md). Crea labels y milestones faltantes. |
| `develop-story` | `/develop-story <N>` | Lee el issue con `gh`, valida dependencias, carga [docs/code_standards.md](../docs/code_standards.md) y arch.md, crea la rama, implementa con tests, verifica (gofmt, vet, `go test -race`, cross-build de 4 targets, `standards-reviewer`, `platform-tester`), actualiza docs y abre el PR. Los spikes van a `spikes/` y terminan en `record-decision`. |
| `develop-batch` | `/develop-batch <#N …> \| fase <n> \| hito <Hx.y>` | Orquestador. Construye el grafo con las `Depende de:` del lote, avisa de dependencias externas sin terminar, de ciclos y de conflictos probables (misma área o archivos), y propone un plan en oleadas (paralelo dentro de cada oleada, serie entre oleadas). El usuario añade o saca stories y confirma. Ejecuta con agentes `story-developer` en worktrees (ramas `story/…` locales apiladas por dependencia), revisa cada story, las integra en `batch/<slug>` y abre **un solo PR** para el lote. Excluye los issues `manual-only`. |
| `record-decision` | `/record-decision [#spike \| texto]` | Lleva una decisión a arch.md (§2, sección afectada, sin marcas de spike, §18, *Registro de decisiones*) y roadmap.md sin dejar contradicciones; comenta y desbloquea los issues afectados. Pide confirmación antes de editar. |
| `check-standards` | `/check-standards [diff\|all\|area:x\|ruta]` | Checks automáticos + `standards-reviewer` sobre el alcance (por defecto, el diff contra main). Ofrece corregir los ERROR. |

## Agentes

| Agente | Modelo | Qué hace | Usado por |
|---|---|---|---|
| `story-developer` | inherit | Implementa una story sin interacción en su worktree, partiendo de la rama base del plan. Sigue `develop-story` en modo lote (sin push, PR ni edición de decisiones) y devuelve un `STORY_RESULT` estructurado: `done`, `needs-input` o `failed`. | `develop-batch` |
| `standards-reviewer` | sonnet | Revisa con contexto limpio contra los standards, los principios de arch.md y los criterios de aceptación. Hallazgos verificados con archivo:línea. No edita. | `develop-story`, `develop-batch`, `check-standards` |
| `platform-tester` | haiku | Ejecuta un escenario (spike, binario, comandos) en contenedores de `platforms.images` como usuario sin privilegios, con solo los prerrequisitos declarados. Tabla de resultados por distro/libc/arch. No toca el repo. | `develop-story`, `develop-batch` |

Los subagentes no pueden lanzar otros subagentes. Por eso, en un lote es el orquestador (`develop-batch`, en la conversación principal) quien ejecuta `standards-reviewer` y `platform-tester` sobre la rama de cada `story-developer`, y le reenvía los hallazgos.

## Archivos

```
.claude/
├── README.md
├── project.config.json        # repo, docs, labels, milestones, plataformas Docker, verificación
├── settings.json              # permisos de lectura de gh/go; deny del MCP de GitHub
├── agents/
│   ├── story-developer.md
│   ├── standards-reviewer.md
│   └── platform-tester.md
└── skills/
    ├── story-status/SKILL.md
    ├── generate-stories/SKILL.md
    ├── create-story/{SKILL.md,templates/story.md,templates/spike.md}
    ├── develop-story/SKILL.md
    ├── develop-batch/SKILL.md
    ├── record-decision/SKILL.md
    └── check-standards/SKILL.md
docs/code_standards.md         # fuente de verdad de develop-story y standards-reviewer
```

## Convenciones clave

- **Una story = una rama.** `/develop-story` abre un PR por story; `/develop-batch`, un PR por lote. Tamaño máximo de una story `L`; si no cabe, se divide.
- **Dependencias obligatorias:** toda story lleva `Depende de: #N` (solo las directas) o `Depende de: ninguna`. Sin esto, `develop-batch` no puede armar el grafo.
- **Lotes:** `batch` en el config (`maxParallel`, `strategy`, `maxFixRounds`, `branchPattern`). Las ramas `story/…` dependientes parten de la rama de su dependencia (`stack`) y no se publican; al final se integran en `batch/<slug>`, que se publica con un único PR con un `Closes #N` por story.
- **`manual-only`** (label de `labels.execution`): trabajo que solo puede hacer una persona (servidores reales, credenciales, hardware, root, GUI). Ningún agente lo toma.
- **Spikes** (`type:spike`): código descartable en `spikes/h0.<n>-<slug>/` + `RESULTS.md`; la decisión entra a arch.md con `record-decision`.
- **El issue se cierra con el merge** (`Closes #N`). Estados: `status:in-progress` → `status:in-review`.
- **Board:** `project.board` es `null`. Para usar un GitHub Project, crearlo y poner su número en el config.
- **Matriz de plataformas:** `platforms` en el config; ajustarla con el inventario real de servidores.

## Investigación del código: graphify

La fase de investigación de los skills y agentes usa [graphify](https://github.com/Graphify-Labs/graphify): un grafo del código construido localmente con tree-sitter (`graphify-out/`, no versionado). El protocolo está en [CLAUDE.md](../CLAUDE.md#protocolo-de-investigación-graphify) y la configuración en `research` de `project.config.json`.

| Dónde | Para qué |
|---|---|
| `generate-stories` | Saber qué hitos ya tienen código y confirmar dependencias de código entre propuestas |
| `create-story` | Plan técnico con archivos y símbolos reales |
| `develop-story` / `story-developer` | Encontrar qué reutilizar y medir el impacto antes de cambiar; grafo regenerado por rama/worktree |
| `develop-batch` | Detectar conflictos entre stories paralelas y dependencias de código no declaradas |
| `standards-reviewer` / `check-standards` | Consumidores de cada símbolo modificado (impacto del diff) |
| `record-decision` | Código que asume la alternativa descartada |

Sin graphify instalado (o mientras no haya código), todo cae a Grep/Glob y se indica en el resultado.

## Requisitos

- `gh` autenticado (`gh auth status`) con scope `repo` (y `project` si se usa board).
- Docker para `platform-tester`. En Apple Silicon, las imágenes `amd64` corren emuladas (más lento).
- Go a partir de H1.1. Opcionales: `golangci-lint`, `shellcheck`.
- graphify: `uv tool install graphifyy` (o `pipx install graphifyy`) y, en el repo, `graphify install --project` (añade su skill en `.claude/skills/graphify/` y el hook que sugiere el grafo antes de búsquedas). Opcional: `graphify hook install` para regenerar el grafo en cada commit y checkout.
