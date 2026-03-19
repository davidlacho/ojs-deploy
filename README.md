# OJS/OMP/OPS IaC (DigitalOcean + Docker + Traefik)

This repository contains an “infrastructure as code” setup to run **OJS** (and similarly OMP/OPS) on a **DigitalOcean droplet in Canada** using **Docker Compose** and **Traefik**.

## What this gives you

- A repeatable Docker Compose stack (Traefik + app + MariaDB)
- Canadian server targeting: use DigitalOcean region `tor1` (Toronto)
- Deployment automation via **GitHub Actions** (push to `main` -> deploy to your droplet)
- Persistent storage for:
  - the database (`db-data`)
  - OJS uploads and application state (`ojs-app`)

## Notes / limitations (important)

- OJS installation is typically done via the web installer at least once (to create `config.inc.php` and initialize database schema).
- The first deployment will start the stack, but you will still need to complete the installer in your browser.

## Prerequisites

- A DigitalOcean account
- A DigitalOcean droplet using region `tor1`
- SSH access enabled for the user you will connect as (e.g. `root` or `ubuntu`)
- Firewall/security rules allowing inbound `22` (SSH) and `80` (HTTP)
- Docker installed on the droplet (the GitHub Action will install it automatically if missing)

## Repository secrets (GitHub Actions)

Create these GitHub Secrets (Settings -> Secrets and variables -> Actions):

- `DO_HOST` (droplet IP or hostname)
- `DO_USER` (ssh user)
- `DO_SSH_KEY` (private key that can SSH into the droplet)
- `MARIADB_ROOT_PASSWORD`
- `MARIADB_DATABASE` (example: `ojs`)
- `MARIADB_USER` (example: `ojs`)
- `MARIADB_PASSWORD`

Optionally for HTTPS later:

- `ACME_EMAIL`
- `OJS_HOSTNAME` (custom domain)

## Deploy

1. Update `docker-compose.yml` and/or the image args if you want a specific OJS version.
2. Push to `main`.
3. GitHub Actions will deploy and start the stack.

## One-time OJS installation (after the stack starts)

1. Browse to: `http://<droplet-ip>`
2. Complete the installer form using the DB settings you used in the compose stack:
   - Host: `mariadb` (Docker service name, as seen from the OJS container)
   - Database/User/Password: `MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD`
   - File uploads directory (recommended): `/var/ojs-files` (this stack mounts a persistent volume there, outside the web root)
   - If the installer asks separately for “public files”, use `/var/ojs-files/public`
3. After completion, create your admin user and your first journal.

If the installer fails because the base URL is wrong, update `base_url` later in `config.inc.php` (inside the persistent `ojs-app` volume).

## HTTPS later (custom domain)

When you’re ready with your custom domain:

1. Create a DNS record for `OJS_HOSTNAME` pointing to your droplet IP
2. Open inbound `80` to the internet (for Let’s Encrypt HTTP challenge)
3. Ensure your remote `/opt/ojs/.env` includes:
   - `ACME_EMAIL`
   - `OJS_HOSTNAME`
4. Open inbound `443` (HTTPS) to the droplet
5. Redeploy with the TLS override file:

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
```

## How to choose the OJS version

The app image is built from the official PKP tarball URL using the build arg:

- `OJS_TARBALL_URL`

By default it points at the latest 3.5.x-style tarball pattern you set in the compose file.

