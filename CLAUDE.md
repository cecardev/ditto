# ditto

CLI en Go que, ejecutada en un servidor Linux o en macOS, prepara un entorno de desarrollo personal (Neovim + LazyVim, OpenCode, rg, fd…) dentro de `<workspace>/.ditto/` y abre una subshell con él, sin modificar el host. mise instala los binarios, LazyVim + Mason gestionan Neovim y ditto orquesta.

## Fuentes de verdad

| Documento | Para qué | Autoridad |
|---|---|---|
| [arch.md](arch.md) | Arquitectura y decisiones vigentes | **Manda** sobre todo lo demás |
| [roadmap.md](roadmap.md) | Fases, hitos (`H<fase>.<n>`), criterios y orden | Qué se hace y cuándo |
| [docs/code_standards.md](docs/code_standards.md) | Cómo se escribe el código | Obligatorio al programar |
| [project.md](project.md) | Propuesta original | Histórico; no se edita |
| GitHub Issues | Stories: el trabajo concreto | Una story = una rama; un PR por story o por lote |

Lo marcado como *(spike H…)*, "provisional" o "pendiente" en arch.md **no está decidido**: no implementarlo como si lo estuviera. Para cerrar una decisión se usa `/record-decision`.

## Cómo se trabaja

Todo el trabajo pasa por el harness de `.claude/` (detalle en [.claude/README.md](.claude/README.md)):

| Quiero… | Usar |
|---|---|
| Ver el estado y qué sigue | `/story-status` |
| Crear el backlog desde el roadmap | `/generate-stories [fase\|hito]` |
| Crear un issue suelto | `/create-story` |
| Desarrollar una story | `/develop-story <N>` |
| Desarrollar varias en paralelo/serie | `/develop-batch <#N …\|fase n\|hito Hx.y>` |
| Registrar una decisión de arquitectura | `/record-decision` |
| Revisar código antes de un PR | `/check-standards` |

Agentes (los lanzan los skills): `story-developer`, `standards-reviewer`, `platform-tester`.

Si el usuario pide implementar algo que no tiene issue, proponer primero crear la story (`/create-story`) en vez de programar directamente, salvo que pida explícitamente lo contrario.

## Reglas del proyecto

- **GitHub solo con la CLI `gh`.** El MCP de GitHub está denegado.
- **No usar ruflo** (ni sus herramientas MCP `memory_*`, `swarm_*`, `agent_spawn`, `hooks_route`). La orquestación de agentes es la de este harness (`develop-batch` + agentes de `.claude/agents/`).
- **Una story = una rama `story/<N>-<slug>`.** `/develop-story` abre un PR por story con `Closes #N`; `/develop-batch` integra todas las stories del lote en una rama `batch/<slug>` y abre **un solo PR** con un `Closes #N` por story. El issue se cierra al mergear, no a mano.
- **`manual-only`**: issues que solo puede hacer una persona (servidores reales, credenciales, hardware, root, GUI). Ningún agente los desarrolla; `/develop-batch` los excluye.
- **Toda story declara dependencias** (`Depende de: #N` o `Depende de: ninguna`).
- **Spikes** (`type:spike`): código descartable en `spikes/h0.<n>-<slug>/` + `RESULTS.md`. Nunca en `internal/` ni `cmd/`.
- Pedir confirmación antes de `git push`, abrir PRs, mergear o editar decisiones en arch.md (salvo que un plan de `develop-batch` confirmado ya lo autorice).
- Idioma: código y comentarios en inglés; mensajes al usuario, docs, issues, PRs y commits en español (Conventional Commits con `(#N)`).

## Protocolo de investigación (graphify)

Para entender o buscar en el código, usar primero el grafo de [graphify](https://github.com/Graphify-Labs/graphify) (`graphify-out/`, no versionado), y solo después Grep/Glob/Read para leer los archivos concretos:

1. **Grafo actualizado:** si `graphify-out/graph.json` no existe → `graphify update .` (o `/graphify . --no-viz` la primera vez). Si existe pero el código cambió (otra rama, pull, worktree nuevo) → `graphify update .`.
2. **Preguntas acotadas:**
   - `graphify query "<pregunta>"` — dónde está o cómo funciona algo.
   - `graphify explain "<Símbolo>"` — qué es un tipo o función, quién lo usa y de qué depende.
   - `graphify path "<A>" "<B>"` — cómo se conectan dos piezas (impacto de un cambio).
   - Código de salida `3` = nombre ambiguo (elegir uno de los candidatos listados); `4` = sin coincidencias (reformular o ir a Grep).
3. **Visión general:** `graphify-out/GRAPH_REPORT.md` (conceptos clave, hubs, conexiones), solo para análisis amplios.
4. **Después** leer con Read solo los archivos que el grafo señaló.
5. **Fallback:** si `graphify` no está instalado o el grafo está vacío (aún no hay código), usar Grep/Glob y decirlo en el resultado.

graphify procesa el código localmente; no ejecutar extracción de documentos con un backend LLM externo sin que el usuario lo pida. La sección `## graphify` del final la gestiona `graphify install --project` (junto con los hooks `PreToolUse` de `.claude/settings.json`); no editarla a mano.

## Verificación

Antes de dar por terminado código Go (a partir de H1.1, cuando exista `go.mod`):

```sh
test -z "$(gofmt -l .)" && go vet ./... && go test -race ./...
for t in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
  CGO_ENABLED=0 GOOS=${t%/*} GOARCH=${t#*/} go build ./... || break
done
```

Compatibilidad Linux (glibc antiguas, musl, arm64): agente `platform-tester` (Docker).

## Principios que no se negocian (arch.md)

Nada se escribe fuera de `.ditto/` · sin Docker para ejecutar el entorno (host-first) · `CGO_ENABLED=0` · ningún `XDG_*`/`MISE_*` global en la subshell · todo artefacto descargado se verifica con sha256 · nunca secretos en el binario, los dotfiles ni los lockfiles.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
