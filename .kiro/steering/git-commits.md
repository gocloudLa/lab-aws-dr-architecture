---
inclusion: always
---

# Formato de mensajes de commit

REGLA PRINCIPAL: el mensaje de commit debe ser EXACTAMENTE UNA sola línea de texto.
La salida completa es esa única línea, sin nada antes ni después.

Restricciones estrictas (no negociables):

- Devolvé UNA sola línea. Está PROHIBIDO el cuerpo, la descripción extendida o cualquier
  segunda línea.
- NO incluyas caracteres de salto de línea (`\n`) en ninguna parte del mensaje.
- NO agregues líneas en blanco, bullets, listas, párrafos ni notas después del título.
- NO uses bloques de código, comillas, ni encabezados alrededor del mensaje.
- El largo total: idealmente menos de 50 caracteres, máximo 72. Si no entra, acortá el
  resumen; nunca lo pases a una segunda línea.
- Formato Conventional Commits en minúsculas: `tipo(scope opcional): resumen breve`.
  - Valores de `tipo`: feat, fix, chore, docs, refactor, test, ci, build, perf.
- Resumen en modo imperativo y directo (ej: "add", "fix", "update", "remove").
- NO incluyas nombres de archivos, listas de cambios, ni explicaciones del porqué.
- NO uses punto final.

Ejemplos válidos (cada uno es el mensaje COMPLETO, una sola línea):
- `fix: corrige timeout en failover de arc`
- `feat(terragrunt): agrega capa workload para arc`
- `chore: deshabilita container insights en ecs`
- `docs: actualiza guia de switchover`

Ejemplo de lo que NO se debe generar (multilínea, prohibido):

```
feat: agrega switchover con arc

- promueve aurora
- escala ecs
```
