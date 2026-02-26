# Static Site Template — Notes

## Architecture

```
Push to main → GitHub Actions → rsync to /opt/sites/{repo-name}/
                               + write /opt/traefik/dynamic/{repo-name}.yml
                               → Traefik auto-discovers route, provisions TLS cert
                               → Live at https://{repo-name}.qa.superposition.systems
```

Three layers on the server:

1. **nginx container** (`static-sites`) — one shared instance at `/opt/apps/static-sites/`, maps subdomain to directory via regex on the Host header
2. **Traefik file provider** — watches `/opt/traefik/dynamic/` for per-site YAML route configs, each pointing to the `static-sites@docker` service
3. **Traefik Docker provider** — existing setup, the file provider runs alongside it

No per-project Docker builds. No `.env` files. Deploy = rsync + one YAML file.

## Server-Side Setup (already done on QA)

The `server-setup/` directory contains the one-time infrastructure setup that was run on 2026-02-25:

- Added `--providers.file.directory=/opt/traefik/dynamic` and `--providers.file.watch=true` to Traefik's command flags in `/opt/traefik/docker-compose.yml`
- Added `/opt/traefik/dynamic:/opt/traefik/dynamic:ro` volume mount to Traefik
- Created `/opt/apps/static-sites/` with nginx container and config
- Created `/opt/sites/` directory for site files

**cloud-init.yaml is now in sync.** The Hetzner repo's `cloud-init.yaml` includes all static site infrastructure: Traefik file provider flags/volume, the static-sites container (docker-compose + nginx.conf), and the `/opt/sites/` and `/opt/traefik/dynamic/` directories. A reprovision from Terraform will restore this automatically.

## Deploying a New Site

1. Create a repo from this template in the `Superposition-Systems` org
2. Set GitHub secrets/variables (run `./scripts/setup-qa.sh` or manually):
   - **Variable** `QA_SERVER_IP`: `46.62.241.222`
   - **Secret** `QA_SSH_PRIVATE_KEY`: contents of `~/.ssh/id_ed25519`
3. Replace `index.html` with your site files (Figma HTML export, etc.)
4. Push to `main` — deploys automatically
5. Site is live at `https://{repo-name}.qa.superposition.systems`

## Removing a Site

No teardown workflow exists yet. Remove manually:

```bash
ssh root@46.62.241.222
rm -rf /opt/sites/{site-name}
rm /opt/traefik/dynamic/{site-name}.yml
```

Traefik picks up the route removal automatically (file watch).

## Known Issues & Gotchas

### Org-level secrets don't propagate

GitHub org secrets/variables were set with `--visibility all` on the Superposition-Systems org, but repos didn't pick them up. Had to set `QA_SERVER_IP` and `QA_SSH_PRIVATE_KEY` at the repo level for lotus-landscaping. Each new repo will need the same. The `setup-qa.sh` script handles this.

### Alpine BusyBox wget + IPv6

The nginx health check must use `127.0.0.1` not `localhost`. Alpine's BusyBox wget resolves `localhost` to `::1` (IPv6) but nginx only listens on `0.0.0.0` (IPv4). Health check fails → Traefik drops the container → 404. Already fixed in the template.

### Traefik cross-provider service references

The file provider route configs reference `static-sites@docker` — the `@docker` suffix tells Traefik to resolve the service from the Docker provider. This is how file-defined routers point to Docker-defined services.

### TLS certificates

A wildcard cert (`*.qa.superposition.systems`) covers all static sites via DNS-01 challenge with Hetzner DNS. Per-site route configs use `tls: {}` — no `certResolver` needed. DNS was migrated from Squarespace to Hetzner DNS on 2026-02-26.

### HEREDOC indentation in the workflow

The deploy workflow uses nested HEREDOCs (outer `ROUTE_SCRIPT` for SSH, inner `ROUTE_EOF` for the YAML file). The YAML literal block (`run: |`) strips base indentation, so the inner HEREDOC content starts at column 0 in the generated file. Verified with Python YAML parser — don't reindent without re-testing.

## Authentication

All static sites are behind `qa-gate` (cookie-based forward-auth). Users are redirected to `auth.qa.superposition.systems/login` and the session cookie covers all `*.qa.superposition.systems` subdomains. To make a site public, remove `qa-gate@docker` from the middlewares list in the route config.

## Future Improvements

- **Teardown workflow** — GitHub Action to remove a site (delete files + route config)
- **Slack automation** — `@claude` in Slack creates repo from template, uploads Figma zip, triggers deploy. Needs `gh` CLI in Claude Code's environment via `.claude/setup.sh`
- **Custom domains** — support `CNAME`ing a client's domain to the static site
