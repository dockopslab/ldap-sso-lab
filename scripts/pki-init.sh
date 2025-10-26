#!/bin/sh
set -euo pipefail

CERT_DIR="${CERT_DIR:-/certs}"
umask 077

CA_KEY="${CERT_DIR}/ca.key"
CA_CRT="${CERT_DIR}/ca.crt"
CA_SERIAL="${CERT_DIR}/ca.srl"

CA_SUBJECT="${PKI_CA_SUBJECT:-/C=ES/ST=Org/L=Org/O=Empresa/OU=IT/CN=Empresa-Root-CA}"
CA_DAYS="${PKI_CA_DAYS:-3650}"
RENEW_THRESHOLD_DAYS="${PKI_RENEW_THRESHOLD_DAYS:-30}"
FORCE_RENEW="${PKI_FORCE_RENEW:-false}"

RENEW_THRESHOLD_SECONDS=$((RENEW_THRESHOLD_DAYS * 86400))

ensure_dir() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
  fi
}

needs_renewal() {
  cert_path="$1"

  if [ "$FORCE_RENEW" = "true" ]; then
    return 0
  fi

  if [ ! -f "$cert_path" ]; then
    return 0
  fi

  if ! openssl x509 -checkend "$RENEW_THRESHOLD_SECONDS" -noout -in "$cert_path"; then
    return 0
  fi

  return 1
}

generate_server_cert() {
  name="$1"
  common_name="$2"
  san_dns="$3"
  san_ip="$4"

  key="${CERT_DIR}/${name}.key"
  csr="${CERT_DIR}/${name}.csr"
  crt="${CERT_DIR}/${name}.crt"
  ext="${CERT_DIR}/${name}.ext"
  meta="${CERT_DIR}/${name}.meta"
  desired_signature="$(printf '%s|%s|%s' "$common_name" "$san_dns" "$san_ip")"

  if [ -f "$key" ] && [ -f "$crt" ] && [ -f "$meta" ]; then
    current_signature="$(cat "$meta" 2>/dev/null || true)"
    if [ "$current_signature" = "$desired_signature" ] && ! needs_renewal "$crt"; then
      echo "✔ Certificado vigente para ${name}, omitiendo"
      return
    fi
  fi

  echo "→ Generando certificado para ${name}"

  rm -f "$key" "$crt" "$meta"

  openssl genrsa -out "$key" 4096
  openssl req -new -key "$key" -out "$csr" -subj "/CN=${common_name}"

  {
    printf "subjectAltName="
    sep=""
    if [ -n "$san_dns" ]; then
      IFS=',' 
      for dns in $san_dns; do
        printf "%sDNS:%s" "$sep" "$dns"
        sep=","
      done
      unset IFS
    fi
    if [ -n "$san_ip" ]; then
      IFS=',' 
      for ip in $san_ip; do
        printf "%sIP:%s" "$sep" "$ip"
        sep=","
      done
      unset IFS
    fi
    printf "\n"
  } > "$ext"

  openssl x509 -req -in "$csr" \
    -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$crt" -days 825 -sha256 -extfile "$ext"

  rm -f "$csr" "$ext"
  printf '%s\n' "$desired_signature" > "$meta"
  echo "✔ Certificado para ${name} generado"
}

create_compat_symlinks() {
  ln -sf openldap.crt "${CERT_DIR}/ldap.crt"
  ln -sf openldap.key "${CERT_DIR}/ldap.key"
  ln -sf ca.crt "${CERT_DIR}/ldap-ca.crt"
}

main() {
  ensure_dir "$CERT_DIR"

  if needs_renewal "$CA_CRT"; then
    echo "→ Generando/Renovando CA interna"
    rm -f "$CA_KEY" "$CA_CRT" "$CA_SERIAL"
    openssl genrsa -out "$CA_KEY" 4096
    openssl req -x509 -new -nodes -key "$CA_KEY" \
      -sha256 -days "$CA_DAYS" -out "$CA_CRT" \
      -subj "$CA_SUBJECT"
    echo "✔ CA interna emitida"
  else
    echo "✔ CA vigente en ${CERT_DIR}"
  fi

  generate_server_cert \
    "openldap" \
    "${PKI_LDAP_COMMON_NAME:-ldap.empresa.local}" \
    "${PKI_LDAP_SAN_DNS:-ldap.empresa.local}" \
    "${PKI_LDAP_SAN_IP:-}"

  generate_server_cert \
    "phpldapadmin" \
    "${PKI_PHPLDAPADMIN_COMMON_NAME:-phpldapadmin.empresa.local}" \
    "${PKI_PHPLDAPADMIN_SAN_DNS:-phpldapadmin.empresa.local}" \
    "${PKI_PHPLDAPADMIN_SAN_IP:-}"

  create_compat_symlinks

  echo "✔ Tarea de PKI completada"
}

main "$@"
