# OJS Infrastructure as Code (DigitalOcean + Docker + Traefik + GitHub Actions)

This repository provides a reproducible way to run **Open Journal Systems (OJS)** on a **DigitalOcean droplet** with:

- Docker Compose orchestration
- Traefik reverse proxy
- Automated Let's Encrypt TLS
- Canonical host redirects
- GitHub Actions deployment
- Persistent OJS and database volumes

It is designed so academics can deploy and maintain OJS with minimal manual server work.

## Architecture

- `traefik` handles HTTP/HTTPS ingress and certificates
- `ojs` runs Apache/PHP with OJS
- `mariadb` stores application data
- Named volumes persist data across redeploys:
  - `db-data` (database)
  - `ojs-app` (application state including `config.inc.php`)
  - `ojs-files` (uploaded files)
  - `letsencrypt` (ACME cert state)

## What is automated

- Push to `main` triggers deploy (`.github/workflows/deploy.yml`)
- Droplet bootstrap for Docker/Compose (if missing)
- Compose deploy/update from repo to `/opt/ojs`
- HTTPS cert provisioning/renewal (Let's Encrypt via Traefik)
- Redirect policy:
  - `http://<apex>` -> `https://<apex>`
  - `http(s)://www.<apex>` -> `https://<apex>`
- Smoke tests that fail deploy if public HTTPS/redirects are broken

## Prerequisites

- DigitalOcean droplet (Ubuntu recommended)
- SSH access to the droplet user
- Domain DNS control (e.g., Namecheap)
- GitHub repository with Actions enabled

## DigitalOcean setup (required)

### 1) Create droplet

- Region can be any; `tor1` is commonly used for Canada
- Ubuntu LTS recommended

### 2) Configure firewall rules

Inbound must allow:

- `22/tcp` (SSH)
- `80/tcp` (HTTP, ACME + redirect)
- `443/tcp` (HTTPS)

If using a DigitalOcean Cloud Firewall, add these there.  
If using `ufw`, allow the same ports on host OS.

### 3) DNS records

For domain `example.org`:

- `A` record: `@` -> droplet IPv4
- `CNAME` record: `www` -> `example.org`

Do not point `www` at a different server.

## GitHub repository secrets (required)

Set these in **Settings -> Secrets and variables -> Actions**:

- `DO_HOST` - droplet IP or SSH hostname
- `DO_USER` - SSH user on droplet
- `DO_SSH_KEY` - private key matching authorized key on droplet
- `MARIADB_ROOT_PASSWORD`
- `MARIADB_DATABASE`
- `MARIADB_USER`
- `MARIADB_PASSWORD`
- `ACME_EMAIL` - valid email for Let's Encrypt notifications
- `OJS_HOSTNAME` - apex host only, e.g. `journal.example.org`

Optional GitHub **Repository Variables**:

- `OJS_JOURNAL_PATH` - journal path to configure automatically (e.g. `joicac`)
- `OJS_JOURNAL_THEME` - theme path to enforce (e.g. `bootstrap3`, `default`)

Important: `OJS_HOSTNAME` must be host-only (no `https://`, no path, no trailing slash).

## First deploy

1. Push to `main` (or run workflow manually).
2. Workflow syncs repo to `/opt/ojs` on droplet and runs:
   - `docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d --build --remove-orphans`
3. Wait for workflow smoke tests to complete.

## First-time OJS web installer

After the stack is up, open `https://<your-apex-domain>` and complete installer.

Use:

- DB host: `mariadb`
- DB name/user/password: values from secrets above
- Files directory: `/var/ojs-files`
- Public files directory (if prompted): `/var/ojs-files/public`

## Runtime config behavior (declarative)

On container startup, `ojs/entrypoint.sh` enforces:

- `base_url = "https://<OJS_HOSTNAME>"`
- `allowed_hosts = '["<OJS_HOSTNAME>","www.<OJS_HOSTNAME>"]'`
- `force_ssl = On`

It can also apply journal theme declaratively when both are set:

- `OJS_JOURNAL_PATH=<journalPath>`
- `OJS_JOURNAL_THEME=<themePath>`

Current image startup also ensures `plugins/themes/bootstrap3` is present in the persistent app volume so the `bootstrap3` theme remains available after redeploys.

It also configures Apache to honor `X-Forwarded-Proto` from Traefik so OJS correctly detects HTTPS behind reverse proxy.

## Verification commands

### From local machine

```bash
curl -I https://<apex-domain>/
curl -I http://<apex-domain>/
curl -I https://www.<apex-domain>/
curl -I http://www.<apex-domain>/
```

Expected:

- apex HTTPS: `200` (or installer flow response)
- apex HTTP: `301/308` -> `https://<apex>/...`
- `www` HTTP/HTTPS: `301/308` -> `https://<apex>/...`

### From droplet

```bash
cd /opt/ojs
sudo docker compose -f docker-compose.yml -f docker-compose.tls.yml ps
sudo docker compose -f docker-compose.yml -f docker-compose.tls.yml logs traefik --tail 200
sudo ss -ltnp | grep -E ':(80|443)\s'
```

## Updating OJS version

Update `OJS_TARBALL_URL` in deploy-generated env (workflow writes it into `/opt/ojs/.env`) and redeploy.  
Current default is:

- `https://pkp.sfu.ca/ojs/download/ojs-3.5.0-3.tar.gz`

## Data safety notes

- Redeploys do not delete `db-data`, `ojs-app`, or `ojs-files`.
- Avoid manual deletion of Docker volumes unless intentionally resetting instance.
- `letsencrypt` volume stores certificate state and should be preserved.

## Troubleshooting quick hits

- **`self-signed certificate` in checks**: cert issuance still warming up or router misbound; inspect Traefik logs.
- **`400 Server host not allowed`**: `allowed_hosts` mismatch; ensure `OJS_HOSTNAME` secret is correct and redeploy.
- **`too many redirects`**: verify forwarded-proto handling and OJS SSL/base_url settings (already enforced by entrypoint in this repo).

