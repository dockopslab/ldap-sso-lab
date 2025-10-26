FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LDAP_DATA_DIR=/var/lib/ldap \
    LDAP_CONFIG_DIR=/etc/ldap/slapd.d \
    LDAP_RUN_DIR=/run/slapd \
    LDAP_CERTS_DIR=/certs

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        slapd \
        ldap-utils \
        gosu \
        ca-certificates \
        bash && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/openldap-entrypoint.sh /usr/local/bin/openldap-entrypoint.sh

RUN chmod +x /usr/local/bin/openldap-entrypoint.sh

VOLUME ["${LDAP_DATA_DIR}", "${LDAP_CONFIG_DIR}"]

EXPOSE 389 636

ENTRYPOINT ["/usr/local/bin/openldap-entrypoint.sh"]
