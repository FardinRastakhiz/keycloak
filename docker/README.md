# Running this Keycloak build in Docker

`docker/Dockerfile` compiles the server from the sources in this repository
(so custom modules such as `scim`, `ssf` and `authzen` are included) and packages
it like the official image. `docker/docker-compose.yml` runs it against Postgres
and imports the `identity-service` realm from `realm-export.json` on first start.

## Quick start

```bash
cd docker
cp .env.example .env        # optional, defaults work for local development
docker compose up --build   # first build takes a while (Maven + admin console)
```

Then open:

- Admin console: http://localhost:8080/admin/ (user `admin`, password `admin` unless changed in `.env`)
- Realm: http://localhost:8080/realms/identity-service
- Health: http://localhost:9000/health/ready

## Notes

- The SCIM API (`/realms/identity-service/scim/v2`) is a preview feature, enabled via the
  `KC_FEATURES` build argument (default `scim-api`). Changing it requires `docker compose build`.
- The image is pre-built for Postgres (`kc.sh build --db=postgres`) and started with
  `start --optimized --import-realm`. Runtime options (database URL and credentials,
  hostname, ports) come from `.env`.
- `--import-realm` only creates the realm if it does not already exist. To re-import
  after editing `realm-export.json`, drop the database volume:
  `docker compose down -v && docker compose up`.
- `KC_HTTP_ENABLED=true` and `KC_HOSTNAME_STRICT=false` are development settings.
  For a public deployment put a TLS-terminating reverse proxy in front and set
  `KC_HOSTNAME` to the public URL.
- The realm contains development client secrets (`identity-service-admin`,
  `identity-service-client`). Rotate them before using the realm anywhere public.
- To rebuild the image after source changes: `docker compose build` (the Maven
  repository is kept in a BuildKit cache mount, so rebuilds are much faster).
