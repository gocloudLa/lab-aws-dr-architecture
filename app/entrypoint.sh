#!/bin/sh
set -eu

: "${DB_HOST:?DB_HOST is required}"
: "${DB_PORT:=5432}"
: "${DB_NAME:=keycloak}"
: "${KC_DB_USERNAME:?KC_DB_USERNAME is required}"
: "${KC_DB_PASSWORD:?KC_DB_PASSWORD is required}"

additional_db_url_properties=${KC_DB_URL_PROPERTIES:-}
case "$additional_db_url_properties" in
  "") ;;
  \?*) additional_db_url_properties=${additional_db_url_properties#\?} ;;
  *) echo "KC_DB_URL_PROPERTIES must start with ?" >&2; exit 64;;
esac

if [ -n "$additional_db_url_properties" ]; then
  additional_db_url_properties="&${additional_db_url_properties}"
fi

if [ "${LOCAL_MODE:-false}" = "true" ]; then
  case "$DB_HOST" in localhost|127.0.0.1|postgres) ;; *) echo "LOCAL_MODE permits only localhost, 127.0.0.1 or postgres" >&2; exit 64;; esac
  export KC_DB_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=disable&tcpKeepAlive=true${additional_db_url_properties}"
else
  RDS_CA_BUNDLE=${RDS_CA_BUNDLE:-/opt/keycloak/conf/rds-global-bundle.pem}
  [ -r "$RDS_CA_BUNDLE" ] || { echo "RDS CA bundle is not readable: $RDS_CA_BUNDLE" >&2; exit 66; }
  export KC_DB_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=verify-full&sslrootcert=${RDS_CA_BUNDLE}&tcpKeepAlive=true${additional_db_url_properties}"
fi

exec /opt/keycloak/bin/kc.sh "$@"
