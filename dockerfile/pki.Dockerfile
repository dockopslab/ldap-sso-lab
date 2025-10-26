FROM alpine:3.20

RUN apk add --no-cache openssl

COPY scripts/pki-init.sh /usr/local/bin/pki-init.sh
RUN chmod 755 /usr/local/bin/pki-init.sh

ENV CERT_DIR=/certs

ENTRYPOINT ["/bin/sh","-c","/usr/local/bin/pki-init.sh && while sleep \"${PKI_RENEW_INTERVAL_SECONDS:-86400}\"; do /usr/local/bin/pki-init.sh; done"]
