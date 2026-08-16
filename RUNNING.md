# Running TV30 + NCL4 (online prime, offline rebuild)

Direct steps. Run everything from the **TV30 root** (`docker-compose.yml`), never from `infra/`.

## 0. Prerequisites

- Docker Engine + Compose v2 (`docker compose`).
- `.env` exists at root (already present). It sets `COMPOSE_PROFILES=mqtt,linux`.
- `ccws/.env` must have `HTTPS_CERT` and `HTTPS_KEY` (base64). If empty, generate a self-signed pair — see `README.md` § "Gerando HTTPS_CERT".

The integration is not on Docker Hub. **You must build locally** — do not rely on `docker compose up` alone (it would pull stale Hub images).

---

## 1. First setup — WITH internet (prime everything once)

```bash
cd /path/to/TV30

# a) Pull the prebuilt images that are NOT built locally (krakend, swagger,
#    middlewares, redis, redis-commander) and all base images.
docker compose pull

# b) Build every locally-built image (aop, bcast, ccws, mosquitto, redis-seed).
#    This downloads npm/go/apt deps ONCE and caches them in image layers.
docker compose build

# c) Build the NCL4 engine (Go). Downloads Go modules once.
cd NCL4
docker compose -f docker-compose.yml -f docker-compose.tv30.yml build engine
cd ..
```

After this, all deps live in Docker's image/layer cache. Later rebuilds of
**source-only changes** work offline.

---

## 2. Run — normal (online or offline, after priming)

```bash
# a) TV30 stack (mosquitto, bcast, aop, ccws, infra)
cd /path/to/TV30
docker compose up -d --build

# b) NCL4 engine on TV30's shared broker + network
cd NCL4
docker compose -f docker-compose.yml -f docker-compose.tv30.yml up --build engine
```

Then open **http://localhost:8080**, pick/create a profile, open the app
catalogue, select **NCL Demo**, go fullscreen. The NCL demo renders in AoP's
own player iframe.

> The NCL4 `player` container (port 7855) is only for NCL4's standalone view —
> it is NOT needed for the TV30 demo. Add it only if you want it:
> `... up --build engine player`. Camera/hand-pose: add `--profile multimodal multimodal`.

To stop:
```bash
cd NCL4 && docker compose -f docker-compose.yml -f docker-compose.tv30.yml down
cd .. && docker compose down
```

---

## 3. Modify a service and rebuild — WITHOUT internet

Editing **source only** (not `package.json` / `go.mod` / the C plugin deps)
rebuilds offline, because dependency install happens in cached layers before the
source is copied in.

```bash
# bcast  (edit bcast/src/**)
docker compose up -d --build bcast

# aop    (edit aop/src/** or aop/public/nclplayer/**)
docker compose up -d --build aop

# ccws   (edit ccws/src/**)
docker compose up -d --build ccws

# NCL4 engine (edit NCL4/controller/**)
cd NCL4
docker compose -f docker-compose.yml -f docker-compose.tv30.yml up -d --build engine
```

**What still needs internet (re-prime with `docker compose build` while online):**

- Changing `package.json` / `package-lock.json` in aop, bcast, ccws → `npm ci` re-runs.
- Changing `go.mod` / `go.sum` in NCL4 controller or player-service → `go mod download` re-runs.
- Changing the mosquitto C plugin's apt deps or mosquitto version → apt/wget re-run.
- Pulling a base image you never primed (e.g. first `docker compose build`).

Bind-mounted content needs **no rebuild at all** — just restart or edit live:

- `bcast/public/**` (templates + media, incl. `public/media/ncl-demo/**`) is bind-mounted `:ro`.
- `TV30/user-files/**` (aop, ccws).

---

## 4. redis-seed — the offline gotcha (fixed)

`redis-seed` used to run `pip install redis` **at container start**, so it hit
PyPI on every `up` and failed offline. It is now baked at build time
(`infra/dockerfiles/redis-seed.Dockerfile`, referenced from
`infra/docker-compose.yml`). After one online `docker compose build`, it runs
offline. It is a **local-only image** — no `image:` name, so nothing is
published to or maintained on Docker Hub; `docker compose build`/`up` build it
from the Dockerfile and `docker compose pull` skips it.

> This is a change in the `infra/` submodule — commit it there so it isn't lost.

---

## 5. Quick reference

| What | URL / port |
|------|-----------|
| AoP receiver UI (see the demo here) | http://localhost:8080 |
| bcast | http://localhost:8081 |
| Mosquitto WS (browser → broker) | ws://localhost:9001/mqtt |
| Redis Commander | http://localhost:18081 |
| Swagger | http://localhost:8085 |

Engine working correctly (logs): `docker logs -f ncl4-engine` should show it
waiting on `aop/urn:tv30:service:ncl-demo/currentApp`, then a GET of
`.../media/ncl-demo/main.ncl` after you select the app.
