---
inclusion: always
---

# Formato de mensajes de commit

Cuando generes un mensaje de commit:

- Devuelve SIEMPRE una sola línea. No incluyas cuerpo ni descripción extendida.
- No agregues líneas en blanco ni bullets ni párrafos después del título.
- Mantén el mensaje lo más corto y conciso posible (idealmente menos de 50 caracteres, máximo 72).
- Usa el formato Conventional Commits en minúsculas: `tipo(scope opcional): resumen breve`.
  - Ejemplos de `tipo`: feat, fix, chore, docs, refactor, test, ci.
- Escribe el resumen en modo imperativo y directo (ej: "add", "fix", "update").
- No incluyas nombres de archivos individuales, listas de cambios, ni explicaciones.
- No uses punto final.

Ejemplos válidos:
- `fix: corrige timeout en failover de arc`
- `feat(terraform): agrega modulo keycloak-region`
- `chore: actualiza version de opentofu`
