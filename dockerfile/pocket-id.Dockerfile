FROM ghcr.io/pocket-id/pocket-id:latest

USER root

RUN apk add --no-cache ca-certificates

COPY scripts/pocket-id-entrypoint.sh /usr/local/bin/pocket-id-entrypoint.sh
RUN chmod 755 /usr/local/bin/pocket-id-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/pocket-id-entrypoint.sh"]
CMD ["/app/pocket-id"]
