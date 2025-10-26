#!/bin/bash

set -euo pipefail

DATA_DIR=${LDAP_DATA_DIR:-/var/lib/ldap}
CONFIG_DIR=${LDAP_CONFIG_DIR:-/etc/ldap/slapd.d}
RUN_DIR=${LDAP_RUN_DIR:-/run/slapd}
CERT_DIR=${LDAP_CERTS_DIR:-/certs}
CERT_DEST_DIR=${LDAP_TLS_DEST_DIR:-/etc/ldap/tls}

LDAP_BASE_DN=${LDAP_BASE_DN:?LDAP_BASE_DN must be set}
LDAP_ADMIN_PASSWORD=${LDAP_ADMIN_PASSWORD:?LDAP_ADMIN_PASSWORD must be set}
LDAP_ADMIN_USERNAME=${LDAP_ADMIN_USERNAME:-admin}
LDAP_ORGANISATION=${LDAP_ORGANISATION:-Example Org}
LDAP_DOMAIN=${LDAP_DOMAIN:-example.org}
LDAP_TLS_CRT_FILENAME=${LDAP_TLS_CRT_FILENAME:-ldap.crt}
LDAP_TLS_KEY_FILENAME=${LDAP_TLS_KEY_FILENAME:-ldap.key}
LDAP_TLS_CA_CRT_FILENAME=${LDAP_TLS_CA_CRT_FILENAME:-ca.crt}
LDAP_TLS_VERIFY_CLIENT=${LDAP_TLS_VERIFY_CLIENT:-never}

LOCAL_TLS_CERT_FILE="$CERT_DEST_DIR/$LDAP_TLS_CRT_FILENAME"
LOCAL_TLS_KEY_FILE="$CERT_DEST_DIR/$LDAP_TLS_KEY_FILENAME"
LOCAL_TLS_CA_FILE="$CERT_DEST_DIR/$LDAP_TLS_CA_CRT_FILENAME"

ensure_permissions() {
  mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$RUN_DIR"
  chown -R openldap:openldap "$DATA_DIR" "$CONFIG_DIR" "$RUN_DIR"
}

wait_for_certs() {
  local files=("$CERT_DIR/$LDAP_TLS_CRT_FILENAME" "$CERT_DIR/$LDAP_TLS_KEY_FILENAME" "$CERT_DIR/$LDAP_TLS_CA_CRT_FILENAME")
  for f in "${files[@]}"; do
    until [ -s "$f" ]; do
      echo "Esperando certificado requerido: $f"
      sleep 2
    done
  done
}

sync_certificates() {
  mkdir -p "$CERT_DEST_DIR"
  install -o openldap -g openldap -m 600 "$CERT_DIR/$LDAP_TLS_KEY_FILENAME" "$LOCAL_TLS_KEY_FILE"
  install -o openldap -g openldap -m 640 "$CERT_DIR/$LDAP_TLS_CRT_FILENAME" "$LOCAL_TLS_CERT_FILE"
  install -o openldap -g openldap -m 644 "$CERT_DIR/$LDAP_TLS_CA_CRT_FILENAME" "$LOCAL_TLS_CA_FILE"
}

update_tls_config_file() {
  local config_file="$CONFIG_DIR/cn=config.ldif"
  if [ ! -f "$config_file" ]; then
    return
  fi
  perl -0pi -e "s#^olcTLS(?:CertificateFile|CertificateKeyFile|CACertificateFile|VerifyClient):.*\\n##mg" "$config_file"
  printf 'olcTLSCertificateFile: %s\nolcTLSCertificateKeyFile: %s\nolcTLSCACertificateFile: %s\nolcTLSVerifyClient: %s\n' \
    "$LOCAL_TLS_CERT_FILE" "$LOCAL_TLS_KEY_FILE" "$LOCAL_TLS_CA_FILE" "$LDAP_TLS_VERIFY_CLIENT" >> "$config_file"
  perl -0pi -e 's/\n{2,}(olcTLSCertificateFile)/\n\1/g' "$config_file"
  chown openldap:openldap "$config_file"
}

start_temp_slapd() {
  /usr/sbin/slapd -h "ldap:/// ldapi:///" -F "$CONFIG_DIR" -u openldap -g openldap
  for _ in $(seq 1 30); do
    if [ -S "$RUN_DIR/ldapi" ]; then
      return 0
    fi
    sleep 1
  done
  echo "slapd no inició correctamente (ldapi no disponible)" >&2
  exit 1
}

stop_temp_slapd() {
  if [ -f "$RUN_DIR/slapd.pid" ]; then
    kill "$(cat "$RUN_DIR/slapd.pid")" || true
    for _ in $(seq 1 30); do
      if [ ! -f "$RUN_DIR/slapd.pid" ]; then
        break
      fi
      sleep 1
    done
  fi
}

configure_ldap() {
  update_tls_config_file
  start_temp_slapd

  local hashed_pass
  hashed_pass=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
  local admin_dn="cn=${LDAP_ADMIN_USERNAME},${LDAP_BASE_DN}"

  cat > /tmp/db-config.ldif <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_BASE_DN
-
replace: olcRootDN
olcRootDN: $admin_dn
-
replace: olcRootPW
olcRootPW: $hashed_pass
-
replace: olcAccess
olcAccess: {0}to attrs=userPassword by self write by dn.base="$admin_dn" write by anonymous auth by * none
olcAccess: {1}to * by dn.base="$admin_dn" write by * read
EOF

  ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/db-config.ldif

  dc_value=$(echo "$LDAP_BASE_DN" | awk -F',' '{for(i=1;i<=NF;i++){if($i ~ /^dc=/){print substr($i,4); exit}}}')
  cat > /tmp/base.ldif <<EOF
dn: $LDAP_BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: $LDAP_ORGANISATION
dc: $dc_value

dn: ou=people,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: people

dn: ou=groups,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: groups

dn: $admin_dn
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: ${LDAP_ADMIN_USERNAME}
description: Directory administrator account
userPassword: $hashed_pass
EOF

  ldapadd -x -D "$admin_dn" -w "$LDAP_ADMIN_PASSWORD" -H ldap://127.0.0.1 -f /tmp/base.ldif || true

  stop_temp_slapd
  touch "$DATA_DIR/.configured"
}

ensure_root_credentials() {
  local admin_dn="cn=${LDAP_ADMIN_USERNAME},${LDAP_BASE_DN}"
  start_temp_slapd

  local hashed_pass
  hashed_pass=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")

  cat > /tmp/admin-credentials.ldif <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: $admin_dn
-
replace: olcRootPW
olcRootPW: $hashed_pass
EOF

  ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/admin-credentials.ldif

  if ldapsearch -Y EXTERNAL -H ldapi:/// -b "$admin_dn" -s base "(objectClass=*)" >/dev/null 2>&1; then
    cat > /tmp/admin-entry.ldif <<EOF
dn: $admin_dn
changetype: modify
replace: objectClass
objectClass: organizationalRole
objectClass: simpleSecurityObject
-
replace: cn
cn: ${LDAP_ADMIN_USERNAME}
-
replace: description
description: Directory administrator account
-
replace: userPassword
userPassword: $hashed_pass
EOF
    ldapmodify -x -D "$admin_dn" -w "$LDAP_ADMIN_PASSWORD" -H ldapi:/// -f /tmp/admin-entry.ldif || true
  else
    cat > /tmp/admin-entry.ldif <<EOF
dn: $admin_dn
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: ${LDAP_ADMIN_USERNAME}
description: Directory administrator account
userPassword: $hashed_pass
EOF
    ldapadd -x -D "$admin_dn" -w "$LDAP_ADMIN_PASSWORD" -H ldapi:/// -f /tmp/admin-entry.ldif || true
  fi

  stop_temp_slapd
  rm -f /tmp/admin-credentials.ldif /tmp/admin-entry.ldif
}

ensure_permissions
wait_for_certs
sync_certificates
update_tls_config_file

if [ ! -f "$DATA_DIR/.configured" ]; then
  configure_ldap
else
  ensure_root_credentials
fi

exec /usr/sbin/slapd -h "ldap:/// ldapi:/// ldaps:///" -F "$CONFIG_DIR" -u openldap -g openldap -d 0
