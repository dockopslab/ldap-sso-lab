## ldap-sso-lab

This repository defines a self-contained lab for testing LDAP authentication flows with [Pocket ID](https://github.com/pocket-id/pocket-id) and future SSO providers. It provisions:

- **OpenLDAP** pre-configured with TLS and optional sample data.
- **phpLDAPadmin** to inspect and manage entries over HTTPS.
- **Pocket ID** (OIDC provider) pre-wired to the LDAP directory.
- **PKI helper** that issues an internal CA and per-service server certificates, renewing them automatically.

Everything runs via Docker Compose, so you can iterate on schema, TLS, and IdP behavior locally or in an isolated environment.

---

### Repository Structure

| Path | Purpose |
| --- | --- |
| `compose/ldap-sso-pocketid.yml` | Main Docker Compose definition for the stack. |
| `env/` | Environment files (`*.env`) that drive container configuration; templates are committed, secrets are not. |
| `dockerfile/` | Custom Dockerfiles for PKI, OpenLDAP, and the Pocket ID wrapper image. |
| `scripts/` | Helper scripts used inside containers (PKI automation, entrypoints). |
| `template/ldap-ldif/` | Example LDIF files to seed groups and users. |
| `docs/` | Additional how-tos (Pocket ID integration notes, Synology guides, etc.). |
| `docs/resources/` | Supporting screenshots referenced in the docs. |

---

### Prerequisites

- Docker Engine 24+ and Docker Compose v2.
- Make sure your user can access the Docker socket (or run commands with `sudo`).
- Optional: `openssl` locally if you want to inspect the generated certificates.

---

### Configure Environment Variables

1. Clone the repository and move into it:

   ```sh
   git clone https://github.com/dockopslab/ldap-sso-lab.git
   cd ldap-sso-lab
   ```

2. Copy the provided template and tailor it to your deployment:

   ```sh
   cp env/ldap-pocketid-template.env env/ldap-pocketid.env
   ```

3. Open `env/ldap-pocketid.env` and review each section:

   - **OpenLDAP**: Define `LDAP_DOMAIN`, admin credentials, ports, and TLS behavior. Set `LDAP_TLS_*` paths to `/certs/...` (they are mounted from the PKI container). Adjust base DN values to match your organization.
   - **phpLDAPadmin**: Update `LDAP_HOST`, port, and bind credentials if you changed them above. Keep `LDAP_SSL=true` when using LDAPS.
   - **Pocket ID**: Set `APP_URL`, `TRUST_PROXY`, and `MAXMIND_LICENSE_KEY` if geo-IP features are required.
   - **PKI**: Customize `PKI_CA_SUBJECT` and the per-service SAN values. You can provide multiple DNS/IP entries by comma-separating them (e.g., `PKI_LDAP_SAN_DNS=ldap.example.local,ldap`). Keep the literal `,ldap` suffix so the certificate also covers the Docker hostname used by Pocket ID when dialing `ldaps://ldap:636`.
   - **TailScale (optional)**: Fill out the auth key and route settings if you plan to expose the stack over Tailscale.

4. Keep `env/ldap-pocketid.env` out of version control. The `.gitignore` already excludes `env/*.env` files except templates.

---

### Certificate Management

The `pki` service (built from `dockerfile/pki.Dockerfile`) runs `scripts/pki-init.sh`, which:

- Issues a long-lived internal CA (`ca.crt`/`ca.key`).
- Creates per-service server certificates with SANs derived from `PKI_*` variables.
- Tracks a hash of the CN/SAN configuration and automatically regenerates certificates when those values change or when renewal thresholds are reached.
- Publishes compatibility symlinks (`ldap.crt`, `ldap.key`, `ldap-ca.crt`) consumed by OpenLDAP and Pocket ID.

The custom Pocket ID image (see `dockerfile/pocket-id.Dockerfile`) copies the CA bundle from `/certs/ca.crt` into the system trust store on startup, so its Go LDAP client trusts the internal PKI without manual steps.

---

### Build and Run

From the repository root:

```sh
# Build custom images (PKI, OpenLDAP, Pocket ID wrapper)
docker compose -f compose/ldap-sso-pocketid.yml build

# Start the full stack
docker compose -f compose/ldap-sso-pocketid.yml up -d

# Tail logs for troubleshooting
docker compose -f compose/ldap-sso-pocketid.yml logs -f pki openldap pocket-id
```

Volumes defined in the compose file (`pki_certs`, `ldap_data`, `ldap_config`, `pocketid_data`) persist certificates, directory data, and Pocket ID state across restarts.

To update certificates after editing `PKI_*` variables, restart the PKI container and then restart the consumers:

```sh
docker compose -f compose/ldap-sso-pocketid.yml up -d --force-recreate pki
docker compose -f compose/ldap-sso-pocketid.yml restart openldap pocket-id
```

---

### Network Edge (NGINX / Ingress)

Pocket ID requires HTTPS with a valid domain in order to register passkeys and serve the OIDC endpoints. Deploy an external reverse proxy (e.g., NGINX Proxy Manager, Traefik, Caddy) that:

- Terminates TLS for your public FQDN (e.g., `auth.example.com`) using certificates issued by a trusted CA (Let’s Encrypt, internal PKI, etc.).
- Proxies traffic to the Pocket ID container (`pocket-id-ldap-sso:1411`), adding `X-Forwarded-*` headers so `TRUST_PROXY=true` works correctly.
- Exposes phpLDAPadmin and any other management UI only over secure channels. When possible, keep administrative endpoints private (for example, publish them exclusively through the Tailscale container or another zero-trust tunnel instead of the public edge).

Ensure DNS records point to the proxy and that the domain configured in `APP_URL` matches the URL users hit, otherwise passkey registration/login will fail.

---

### Seeding Directory Data

Use the LDIF samples under `template/ldap-ldif/` as a starting point. You can apply them from the host once OpenLDAP is running, for example:

```sh
docker compose -f compose/ldap-sso-pocketid.yml exec openldap \
  ldapadd -x -D "cn=admin,dc=example,dc=local" -W \
  -f /templates/ldap-ldif/inetOrgPerson.ldif
```

Adjust the bind DN and template path to align with your environment and mounts.

You can also upload those LDIF templates through phpLDAPadmin (`phpldapadmin-ldap-sso`) by using the *Import* feature inside the web UI, which is often more convenient for quick tweaks while iterating on the directory schema.

---

### Additional Guides

| Guide | Description |
| --- | --- |
| [`docs/pocketid.md`](docs/pocketid.md) | Detailed Pocket ID configuration: reverse proxy, LDAP connector, claim mapping, and OIDC app setup. |
| [`docs/synology.md`](docs/synology.md) | Steps to bind Synology DSM to the lab LDAP and enable SSO via Pocket ID. |

Feel free to extend these documents with environment-specific steps or screenshots as you harden the stack for production use.

---

### Official References

- [OpenLDAP Project](https://www.openldap.org/)
- [phpLDAPadmin](https://github.com/leenooks/phpLDAPadmin)
- [Pocket ID](https://github.com/pocket-id/pocket-id)
- [Tailscale](https://tailscale.com/)
- [NGINX Proxy Manager](https://nginxproxymanager.com/)
