# Imagen Keycloak para la demo

La imagen fija Keycloak `26.7.2` y habilita PostgreSQL, salud y métricas. En AWS, `DB_HOST` recibe directamente el Global Writer Endpoint de Aurora. El driver usa `sslmode=verify-full`, valida el hostname administrado por Aurora y confía únicamente en las autoridades incluidas en el bundle global oficial de RDS incorporado durante el build.

Keycloak administra su propio esquema con Liquibase. El servicio utiliza un único rol PostgreSQL dedicado y no ejecuta SQL propio. La imagen limita las conexiones a 30 segundos y la caché DNS del JVM a 5 segundos para volver a consultar el destino después del cambio.

Variables obligatorias en AWS: `DB_HOST`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`, `KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD` y `KC_HOSTNAME`. `DB_PORT` y `DB_NAME` usan `5432` y `keycloak` por defecto. `RDS_CA_BUNDLE` permite cambiar la ruta local del bundle, cuyo default es `/opt/keycloak/conf/rds-global-bundle.pem`. El modo `LOCAL_MODE=true` desactiva TLS sólo si el host es `postgres`, `localhost` o `127.0.0.1`.

Los endpoints son `:8080` para la aplicación y `:9000/health/live` y `:9000/health/ready` para administración. El ALB no debe publicar el puerto 9000.
