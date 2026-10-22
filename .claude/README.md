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
/check-standards: self-review en cualquier momento
```

## Skills

| Skill | Uso | Qué hace |
|---|---|---|
| `story-status` | `/story-status [fase\|hito\|estado\|area:x]` | Progreso por fase e hito (issues + PRs + roadmap.md), bloqueos, inconsistencias entre roadmap y GitHub, y qué conviene hacer después. Solo lectura. |
| `generate-stories` | `/generate-stories [fase\|hito]` | Lee arch.md, roadmap.md y project.md, revisa el estado real del repo y los issues, y propone las siguientes stories respetando el orden del roadmap y las decisiones pendientes. Crea solo las aprobadas (vía `create-story`). |
| `create-story` | `/create-story [hito o descripción]` | Plantilla y convenciones de los issues: título `[H1.2] área: …`, labels `type/area/priority/size`, milestone por fase, `Depende de: #N`, body de [story](skills/create-story/templates/story.md) o [spike](skills/create-story/templates/spike.md). Crea labels y milestones faltantes. |
| `develop-story` | `/develop-story <N>` | Lee el issue con `gh`, valida dependencias, carga [docs/code_standards.md](../docs/code_standards.md) y arch.md, crea la rama, implementa con tests, verifica (gofmt, vet, `go test -race`, cross-build de 4 targets, `standards-reviewer`, `platform-tester`), actualiza docs y abre el PR. Los spikes van a `spikes/` y terminan en `record-decision`. |
| `record-decision` | `/record-decision [#spike \| texto]` | Lleva una decisión a arch.md (§2, sección afectada, sin marcas de spike, §18, *Registro de decisiones*) y roadmap.md sin dejar contradicciones; comenta y desbloquea los issues afectados. Pide confirmación antes de editar. |
| `check-standards` | `/check-standards [diff\|all\|area:x\|ruta]` | Checks automáticos + `standards-reviewer` sobre el alcance (por defecto, el diff contra main). Ofrece corregir los ERROR. |

## Agentes

| Agente | Modelo | Qué hace | Usado por |
|---|---|---|---|
| `standards-reviewer` | sonnet | Revisa con contexto limpio contra los standards, los principios de arch.md y los criterios de aceptación. Hallazgos verificados con archivo:línea. No edita. | `develop-story`, `check-standards` |
| `platform-tester` | haiku | Ejecuta un escenario (spike, binario, comandos) en contenedores de `platforms.images` como usuario sin privilegios, con solo los prerrequisitos declarados. Tabla de resultados por distro/libc/arch. No toca el repo. | `develop-story` |

## Archivos

```
.claude/
├── README.md
├── project.config.json        # repo, docs, labels, milestones, plataformas Docker, verificación
├── settings.json              # permisos de lectura de gh/go; deny del MCP de GitHub
├── agents/
│   ├── standards-reviewer.md
│   └── platform-tester.md
└── skills/
    ├── story-status/SKILL.md
    ├── generate-stories/SKILL.md
    ├── create-story/{SKILL.md,templates/story.md,templates/spike.md}
    ├── develop-story/SKILL.md
    ├── record-decision/SKILL.md
    └── check-standards/SKILL.md
docs/code_standards.md         # fuente de verdad de develop-story y standards-reviewer
```

## Convenciones clave

- **Una story = un PR.** Tamaño máximo `L`; si no cabe, se divide.
- **Spikes** (`type:spike`): código descartable en `spikes/h0.<n>-<slug>/` + `RESULTS.md`; la decisión entra a arch.md con `record-decision`.
- **El issue se cierra con el merge** (`Closes #N`). Estados: `status:in-progress` → `status:in-review`.
- **Board:** `project.board` es `null`. Para usar un GitHub Project, crearlo y poner su número en el config.
- **Matriz de plataformas:** `platforms` en el config; ajustarla con el inventario real de servidores.

## Requisitos

- `gh` autenticado (`gh auth status`) con scope `repo` (y `project` si se usa board).
- Docker para `platform-tester`. En Apple Silicon, las imágenes `amd64` corren emuladas (más lento).
- Go a partir de H1.1. Opcionales: `golangci-lint`, `shellcheck`.
