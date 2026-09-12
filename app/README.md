# Imagen Keycloak para la demo

La imagen fija Keycloak `26.7.2` y habilita PostgreSQL, salud y métricas. En AWS, `DB_HOST` recibe el endpoint del clúster Aurora de la misma región. El driver usa `sslmode=verify-full`, valida el hostname administrado por Aurora y confía únicamente en las autoridades incluidas en el bundle global oficial de RDS incorporado durante el build.

Keycloak administra su propio esquema con Liquibase. El servicio utiliza un único rol PostgreSQL dedicado y no ejecuta SQL propio. La imagen limita las conexiones a 30 segundos y la caché DNS del JVM a 5 segundos para volver a consultar el destino después del cambio.

Variables obligatorias en AWS: `DB_HOST`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`, `KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD` y `KC_HOSTNAME`. `DB_HOST` siempre es el endpoint del clúster Aurora local, nunca el Global Writer Endpoint. Las dos task definitions regionales fijan `KC_DB_URL_PROPERTIES=?targetServerType=any`; el entrypoint incorpora esas propiedades a la URL JDBC completa junto con TLS, porque Keycloak ignora `KC_DB_URL_PROPERTIES` cuando también recibe `KC_DB_URL`. La propiedad evita que el driver descarte una réplica sólo por no ser el writer; cualquier escritura reenviable depende de Global Write Forwarding de Aurora, no de esta propiedad JDBC. `DB_PORT` y `DB_NAME` usan `5432` y `keycloak` por defecto. `RDS_CA_BUNDLE` permite cambiar la ruta local del bundle, cuyo default es `/opt/keycloak/conf/rds-global-bundle.pem`. El modo `LOCAL_MODE=true` desactiva TLS sólo si el host es `postgres`, `localhost` o `127.0.0.1`.

Los endpoints son `:8080` para la aplicación y `:9000/health/live` y `:9000/health/ready` para administración. El ALB no debe publicar el puerto 9000.
