## Objetivo

<Qué resultado observable entrega esta story, en 1-3 líneas.>

## Contexto

- Hito: H<fase>.<n> — [roadmap.md](../blob/main/roadmap.md)
- Arquitectura: [arch.md §<n> <título>](../blob/main/arch.md)
- <Por qué ahora / qué desbloquea.>

## Alcance

- <Incluido>

**Fuera de alcance:**

- <Excluido explícitamente, y en qué story/hito va>

## Criterios de aceptación

- [ ] <Criterio verificable: comando, test o comportamiento observable>
- [ ] <…>
- [ ] `gofmt`, `go vet` y `go test -race ./...` en verde; compila para los 4 targets con `CGO_ENABLED=0`

## Plan técnico

- Paquete(s): `internal/<pkg>`
- Archivos esperados: `<ruta>`
- <Interfaces, tipos o decisiones de implementación relevantes>

## Tests

- <Unitarios de tabla sobre …>
- <Fixtures en `testdata/` / binarios falsos en un `PATH` temporal>
- Sin red ni escrituras fuera de `t.TempDir()`.

## Verificación manual

- [ ] Linux: <pasos> *(o "no aplica")*
- [ ] macOS: <pasos> *(o "no aplica")*

## Documentación

- <Secciones de arch.md / roadmap.md a actualizar, o "ninguna">

## Dependencias

<!-- Una línea por dependencia directa: "Depende de: #N". Sin dependencias: "Depende de: ninguna". -->
Depende de: <#N | ninguna>
