# Running TV30 + NCL4 (online prime, offline rebuild)

Direct steps. Run everything from the **TV30 root** (`docker-compose.yml`), never from `infra/`.

## 0. Prerequisites

- Docker Engine + Compose v2 (`docker compose`).
- `.env` exists at root (already present). It sets `COMPOSE_PROFILES=mqtt,linux`.
- `ccws/.env` must have `HTTPS_CERT` and `HTTPS_KEY` (base64). If empty, generate a self-signed pair — see `README.md` § "Gerando HTTPS_CERT".
- **For hand pose (multimodal) only:** a camera on the host, and `NCL4/.env`
  set for it — `CAMERA_DEVICE` (default `/dev/video0`) and `CAMERA_GID` (the
  numeric GID owning the camera node; Fedora `video` = 39, Ubuntu/Debian = 44).
  Find yours with `getent group video | cut -d: -f3`. Skip this if you are not
  running multimodal.

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
docker compose -f docker-compose.tv30.yml build engine
cd ..

# d) (Only if you want hand pose) build the Multimodal component. Downloads
#    MediaPipe/OpenCV wheels once, so do it while online.
cd NCL4
docker compose -f docker-compose.tv30.yml --profile multimodal build multimodal
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
docker compose -f docker-compose.tv30.yml up --build engine   # or: make tv30
```

Then open **http://localhost:8080**, pick/create a profile, open the app
catalogue, select **NCL Demo**, go fullscreen. The NCL demo renders in AoP's
own player iframe.

> The NCL4 `player` container (port 7855) is only for NCL4's standalone view —
> it is NOT needed for the TV30 demo. Add it only if you want it:
> `... up --build engine player`.

### 2b. Run WITH hand pose (multimodal)

The Multimodal component is opt-in (it grabs the camera), so it only starts
under the `multimodal` profile. Start the TV30 stack (step **a** above), then
bring up the engine **and** the recognizer together:

```bash
cd NCL4
docker compose -f docker-compose.tv30.yml --profile multimodal up --build engine multimodal
```

Both the engine and the recognizer are on TV30's `ginga_net`, share the
`mosquitto` broker, and speak for the same `SERVICE_ID`
(`urn:tv30:service:ncl-demo`). The recognizer publishes hand poses on
`aop/urn:tv30:service:ncl-demo/multimodal/handPoseRecognitionEvent/stateNotification`
and the engine subscribes to exactly that. TV30's broker allows anonymous
clients and does not ACL-restrict `aop/` topics, so no credentials are needed.

**Verify it is working** — hold a pose (open palm, thumbs up, pointing up) in
front of the camera:

- `docker logs -f ncl4-multimodal` shows `connected; publishing on ...` and a
  `-> OPEN_PALM` line each time a pose is confirmed.
- `docker logs -f ncl4-engine` shows the matching multimodal event arriving.

To *see* poses do something on screen, the running NCL document must bind
`onHandPoseRecognition`. The default served demo
(`bcast/public/media/ncl-demo/main.ncl`) does not — swap in a hand-pose-enabled
document there. `NCL4/ncl-applications/handpose/main.ncl` is a working example
of the bindings.

**Debug preview (optional):** for an annotated MJPEG camera feed, use the
`multimodal-debug` profile instead and open **http://localhost:8090/**:

```bash
docker compose -f docker-compose.tv30.yml --profile multimodal-debug up --build engine multimodal-debug
```

To stop:

```bash
cd NCL4 && docker compose -f docker-compose.tv30.yml --profile multimodal down
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
docker compose -f docker-compose.tv30.yml up -d --build engine
```

**What still needs internet (re-prime with `docker compose build` while online):**

- Changing `package.json` / `package-lock.json` in aop, bcast, ccws → `npm ci` re-runs.
- Changing `go.mod` / `go.sum` in NCL4 controller or player-service → `go mod download` re-runs.
- Changing the mosquitto C plugin's apt deps or mosquitto version → apt/wget re-run.
- Pulling a base image you never primed (e.g. first `docker compose build`).

Bind-mounted content needs **no rebuild at all** — just restart or edit live:

- `bcast/public/**` (templates + media, incl. `public/media/ncl-demo/**`) is bind-mounted `:ro`.
- `TV30/user-files/**` (aop, ccws).

## 4. Quick reference

| What                                | URL / port               |
| ----------------------------------- | ------------------------ |
| AoP receiver UI (see the demo here) | http://localhost:8080    |
| bcast                               | http://localhost:8081    |
| Mosquitto WS (browser → broker)     | ws://localhost:9001/mqtt |
| Redis Commander                     | http://localhost:18081   |
| Swagger                             | http://localhost:8085    |

Engine working correctly (logs): `docker logs -f ncl4-engine` should show it
waiting on `aop/urn:tv30:service:ncl-demo/currentApp`, then a GET of
`.../media/ncl-demo/main.ncl` after you select the app.
