FROM quay.io/keycloak/keycloak:26.7.2 AS keycloak-build
ENV KC_DB=postgres KC_HEALTH_ENABLED=true KC_METRICS_ENABLED=true KC_CACHE=local
ADD --chown=keycloak:keycloak --chmod=0444 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /opt/keycloak/conf/rds-global-bundle.pem
RUN grep -q "BEGIN CERTIFICATE" /opt/keycloak/conf/rds-global-bundle.pem
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.7.2
ENV KC_DB=postgres \
    KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true \
    KC_HTTP_ENABLED=true \
    KC_CACHE=local \
    KC_PROXY_HEADERS=xforwarded \
    KC_HOSTNAME_STRICT=true \
    KC_DB_POOL_MAX_LIFETIME=30s \
    KC_DB_POOL_MIN_SIZE=0 \
    JAVA_OPTS_APPEND="-Dsun.net.inetaddr.ttl=5"
COPY --from=keycloak-build /opt/keycloak/ /opt/keycloak/
COPY --chown=keycloak:keycloak entrypoint.sh /opt/keycloak/bin/demo-entrypoint.sh
USER 1000
EXPOSE 8080 9000
ENTRYPOINT ["/opt/keycloak/bin/demo-entrypoint.sh"]
CMD ["start", "--optimized", "--server-async-bootstrap=false"]
