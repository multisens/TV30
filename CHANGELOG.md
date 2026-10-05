# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### 2026-10-04 (04/10)

L6 (where the SSDP advertiser runs) was decided, as reported by Luis on
2026-10-04: option B, a container only for the announcement, on the host
network; the edge, tv3ws and the rest stay on the `ginga_net` bridge. Platform
scope, decided by Joel (via Luis, 2026-10-04): SSDP discovery only needs to
work on native Linux with Docker Engine; Windows with WSL2 and Docker Desktop
are a documented limitation. B2 (default advertised host) is still open: the
host chain is unchanged (`SSDP_ADVERTISE_HOST` > `SERVER_URL` > local IP), and
so is the loopback warning at boot. Where the advertiser runs is a decision of
this testbed, not of the norm (C.3.4 does not say).

Approved by Luis (2026-10-04): `env_file` for `SSDP_ADVERTISE_HOST`, the
dev-host scenario 1 stopping `tv3ws-ssdp`, and a preflight warning for
`tv3ws-ssdp` left running after the `ssdp` profile is removed
(`scripts/preflight.sh`; verified: warns without the profile, silent with it
and after `docker compose --profile ssdp rm -sf tv3ws-ssdp`).

#### Added

- Root compose: service `tv3ws-ssdp` (profile `ssdp`, `network_mode: host`,
  `restart: unless-stopped`). Same `tv30-tv3ws` image and build as tv3ws, with
  `command: ["node", "dist/ssdp-announcer.js"]` (`tv3ws/src/ssdp-announcer.ts`).
  The process only announces: no Express, no Redis, no MQTT, no TCP port, no
  `user-files` volume. Its die-whole takes down only this container.
- tv3ws: `SSDP_ENABLED` turns the announcement inside tv3ws on or off. Default
  on, for tv3ws running alone on the host (dev-host scenario 1); the root
  compose sets `"false"` on the bridged tv3ws, which logs
  `[ssdp] anuncio desligado (SSDP_ENABLED=false)`.
- Announcer interface: it announces only on the IPv4 interface that holds the
  advertised IP; otherwise on the default-route interface, with a warning.
  `SSDP_INTERFACE` forces the interface. Aimed at the duplicate responses of
  test 7 in `docs/ssdp-verificacao.md`; covered by unit tests and measured
  between the WSL VM and Windows (1 response per M-SEARCH, see Verified
  below); not measured on a LAN with native Linux.
- `.env.example`: `SSDP_ADVERTISE_HOST` and `SSDP_INTERFACE` (commented) and an
  example `COMPOSE_PROFILES` with `ssdp` for native Linux.
- `scripts/preflight.sh`: with the `ssdp` profile active, warns (without
  blocking) when UDP 1900 is already in use on the host.

#### Changed

- tv3ws: `/manifest` stays in tv3ws, behind the edge, always on; the
  announcement moved to a module shared by `server.ts` (only when
  `SSDP_ENABLED` is not `false`/`0`) and by `ssdp-announcer.ts`.
- Root compose: tv3ws gets `SSDP_ENABLED: "false"`. tv3ws and `tv3ws-ssdp`
  get the same `SERVER_URL` (`environment`) and read the same env files, in
  this order: `tv3ws/.env`, then the root `.env`, which wins. That is where
  `SSDP_ADVERTISE_HOST`, `SSDP_INTERFACE` and `EDGE_HTTP_PORT`/`EDGE_HTTPS_PORT`
  come from, so `/manifest` and the `LOCATION` use the same host. Before, the
  only source was `tv3ws/.env`. These variables stay out of `environment` on
  purpose: there, even an empty `${SSDP_ADVERTISE_HOST:-}` would override the
  `tv3ws/.env` value (compose v5.4.0). Costs: a value only exported in the
  shell does not reach them, and the other root `.env` keys also enter both
  containers' environment.
- Without the `ssdp` profile nothing is announced. Before, tv3ws announced from
  inside the bridge, where the announcement did not leave the machine
  (measured on 2026-10-02).
- C8 of `docs/decisoes-pendentes.md` (an SSDP failure took the whole tv3ws
  down): solved for the container deploy, since only `tv3ws-ssdp` dies and
  restarts. It still applies to tv3ws alone on the host with `SSDP_ENABLED`
  on.
- Docs: `docs/decisoes-pendentes.md` (B1 decided, C8), `docs/ssdp-verificacao.md`
  (decided arrangement, how to enable it on native Linux, measurements marked
  as taken with the previous arrangement), `README.md` (section
  *Descoberta SSDP (só Linux nativo)*), `docs/dev-local.md`,
  `docs/instalacao.md`, `ARCHITECTURE.md`, `docs/arquitetura.md`,
  `infra/docs/05-autenticacao.md`, `KNOWN-ISSUES.md` (where to set
  `SSDP_ADVERTISE_HOST`), `docs/avaliacao-item9-credenciais.md` (L6 row) and
  `docs/index.md`.
- `KNOWN-ISSUES.md`: new entry. `tv3ws-ssdp` stays up when the `ssdp`
  profile is removed.

#### Fixed

- tv3ws (`src/ssdp-server.ts`): after the `ssdp:byebye` sent on SIGTERM or
  SIGINT, no `ssdp:alive` goes out during the 300 ms before exit. The library
  ad loop (every 10 s) and its first announcement (3 s after bind) kept
  running, so a signal landing in the 300 ms before a periodic announcement
  sent an alive (`max-age=1800`) right after the byebye. A guard on the
  instance's `advertise()` covers both timers; `stop()` is not used because it
  closes the sockets at once and may drop the byebye. The SIGTERM log line
  now shows at the default `LOG_LEVEL`. The unit test checks both.
- `scripts/test-dev-host.sh`: scenario 1 stops `tv3ws-ssdp` if it is running
  and brings it back on restore. Without this, the host network had two
  advertisers with the same UDN, and the `tv3ws-ssdp` `LOCATION` (host from the
  root `.env`) could differ from the `/manifest` that actually answers (tv3ws on
  the host, which does not read the root `.env`).
- Docs: the "same host in `LOCATION` and `/manifest`" statements are limited to
  the compose; `docs/dev-local.md` explains the dev-host case (`SSDP_ENABLED=false`
  alone removes the second advertiser, not the host mismatch). Docker Desktop is
  marked as not measured (`.env.example`, compose comments,
  `docs/dev-local.md`, `docs/decisoes-pendentes.md`,
  `docs/ssdp-verificacao.md`). The platform restriction is attributed to Joel
  in `ARCHITECTURE.md`, `docs/arquitetura.md` and
  `infra/docs/05-autenticacao.md`, whose code line now lists `ssdp-server.ts`,
  `ssdp-interface.ts` and `manifest.ts`. `docs/decisoes-pendentes.md` lists the
  two compose points that await Luis (`env_file` instead of `environment`, and
  `tv3ws-ssdp` left up when the profile is removed).

#### Verified (integration run on 2026-10-04, option B, image `tv3ws` rebuilt locally)

Windows 11 + WSL2 (NAT), Docker Engine in WSL, compose v5.4.0. The
announcement was turned on with `COMPOSE_PROFILES=mqtt,linux,ssdp` in the
shell. `SSDP_ADVERTISE_HOST` (the WSL VM `eth0` IP) came from a test env file
that a compose override added to both services, so the root `.env` was left
unchanged. Details are in tests 14 to 23 of `docs/ssdp-verificacao.md`.

- `docker compose build tv3ws`: rc 0; `dist/ssdp-announcer.js` in the image.
- Default stack (no `ssdp` profile): no `tv3ws-ssdp`; tv3ws logs
  `[ssdp] anuncio desligado (SSDP_ENABLED=false)`; no UDP 1900 socket in
  tv3ws; 0 UDP 1900 packets in 30 s on the `ginga_net` bridge and on `any`;
  `GET /manifest` through the edge (44642) 200.
- `ssdp` profile on: `tv3ws-ssdp` runs in `network_mode: host` with one
  socket (UDP 0.0.0.0:1900) and no TCP listener. NOTIFY goes only out of the
  VM `eth0` (6 packets in 25 s, TTL 4); 0 on `docker0`, the `br-*` bridges and
  `sta0`. `LOCATION http://172.27.57.172:44642/manifest` and the
  `Server-BaseURL` from `/manifest` match.
- Windows client bound to `vEthernet (WSL)`, multicast TTL 1: 6 responses to
  6 M-SEARCH (1 per search; test 7 had 32 to about 5); `GET` on the
  `LOCATION` 200 through the edge.
- Die-whole isolated: after `kill -9`, Docker restarted the process in about
  1 s. With UDP 1900 held without `SO_REUSEADDR`, the preflight warned and
  `tv3ws-ssdp` exited 1 with `[ssdp] FALHA ... bind EADDRINUSE`, restarting 8
  times in about 30 s, then recovered about 10 s after the port was freed.
  With `SSDP_INTERFACE=eth9` it exited 1 with `[ssdp] FALHA`. In all three
  cases tv3ws kept its `StartedAt`, and the edge answered 200.
- Removing `ssdp` from the profiles and running `up -d` or `down` leaves
  `tv3ws-ssdp` running with its old config. Only
  `docker compose --profile ssdp rm -sf tv3ws-ssdp` removes it.
- tv3ws `npx tsc --noEmit` exit 0; `npm test`: 62 PASS, 0 FAIL.
- `scripts/test-auth.sh`: 148 PASS, 0 FAIL.
- `scripts/test-dev-host.sh` (scenarios 1, 2, 3, docker mode): 27 PASS, 0
  FAIL. In scenario 1, tv3ws on the host (`SSDP_ENABLED` default) announced on
  `eth0` via the default route.
- `scripts/test-consolidacao.sh`: exit 0, every printed check as expected.
- Not measured: discovery by a second device on a LAN with native Linux.

#### Verified (after the fixes above, 2026-10-04, same machine and arrangement)

Details are in tests 24 to 27 of `docs/ssdp-verificacao.md`.

- `docker compose build tv3ws`: rc 0; the guard and the new SIGTERM log line
  are in `dist/ssdp-server.js`. tv3ws `npx tsc --noEmit` exit 0; `npm test`:
  62 PASS, 0 FAIL.
- `scripts/test-auth.sh` (default stack, warn): 148 PASS, 0 FAIL.
- `ssdp` profile on: 4 `ssdp:alive` on the VM `eth0` in 25 s, 0 on the
  `ginga_net` bridge; `LOCATION http://172.27.57.172:44642/manifest` matches
  `Server-Baseurl: 172.27.57.172:44642`.
- Preflight: with the profile in `COMPOSE_PROFILES` it logs
  `ok: UDP 1900 em uso pelo tv3ws-ssdp`; with the profile only on `--profile`
  it receives `COMPOSE_PROFILES=mqtt,linux` and says nothing about UDP 1900.
- `docker compose stop tv3ws-ssdp` with the profile not active: rc 0, exit
  143, 2 `ssdp:byebye` and no `ssdp:alive` after them.
- SIGTERM about 145 ms before a periodic announcement: with the guard
  disabled (control), 2 `ssdp:alive` went out 138 ms after the byebye; with
  the guard, none. The SIGTERM line shows with `LOG_LEVEL=ERROR`.
- `scripts/test-dev-host.sh --cenario 1` with `tv3ws-ssdp` up beforehand: 10
  PASS, 0 FAIL. During the scenario `tv3ws-ssdp` was stopped and every alive on
  `eth0` came from tv3ws on the host; on restore `tv3ws-ssdp` came back.

### 2026-10-03 (03/10)

Three open points were decided by Luis on 2026-10-03, not by the advisor:
A1, A2 and A5 of `docs/decisoes-pendentes.md` (also recorded in
`docs/avaliacao-item9-credenciais.md`), labelled D-L1, D-L2 and D-L4 in code,
scripts and other documents. A3 (where the C.6.8 API lives) is still open, and
so is P1.3 (own origin per broadcaster app), which A5 did not decide.
Credential validation stays in **warn** mode by default. Two changes below
still await Luis's confirmation: 101 for a blocked `clientid` and the `kex`
fix.

#### Changed

- A1, Redis admin UI: the redis-commander (debug UI, helper process inside
  the `redis` container) now requires a login, with `REDIS_COMMANDER_USER`
  (default `admin`) and `REDIS_COMMANDER_PASSWORD` (default
  `tv30-redis-admin`) from the root `.env`. In the installed version (0.9.0)
  this is not HTTP basic auth: the login page opens without credentials and
  the data routes answer 401 without the token the login returns. The
  password is never logged. The Redis connection itself is unchanged: no password, 6379
  published; clients, seed and healthcheck untouched. The risk of the open
  6379 remains (`KNOWN-ISSUES.md`).
- A2, `clientid` reuse: `GET /tv3/authorize` answers 404 `{"error":101}` when
  the `clientid` was used before, for every client class (Table C.3 and
  C.6.1.4.4 of ABNT NBR 25608). tv3ws no longer re-issues the refresh token of
  an already authorized local client called without `pm`. A `clientid` the
  viewer refused (`clients:blocked`) now gets 101 instead of 102, as the note
  of Table C.3 says; this is a reading of D-L2 made during implementation and
  awaits Luis's confirmation. 102 stays for a refusal in the pop-up itself. A
  client that lost its refresh token must run the authorization again with a
  new `clientid` (C.6.1.4.5), which asks the viewer again. Behaviour and
  consequences in `docs/apis-tv3ws.md`.
- A5 (L1), associated-client recognition by `Origin`: no behaviour change,
  risk accepted (a forged `Origin` outside a browser passes as associated).
  The L1 `PENDENTE (Joel)` comment in the edge plugin became
  `DECIDIDO (Luis, 03/10): risco aceito`, and tv3ws's client classification
  (same criterion) got the same marker. Still open, not decided: P1.3 (own
  origin per app). Broadcaster apps served through the AoP proxy carry the
  AoP's `Origin`, while the AoP records the app's own origin in
  `origins:associated`, so they are not recognised as associated: they get
  `X-TV30-Auth-Warn: 107` in warn and would be blocked in enforce
  (`KNOWN-ISSUES.md`).
- redis-commander pinned to `redis-commander@0.9.0` in
  `infra/redis/Dockerfile`: the login reads `HTTP_USER`/`HTTP_PASSWORD`, the
  names this version maps, and without them the UI starts open with no
  warning. The entrypoint comment now says where the password really is: out
  of `ps` and of the log, but in the whole container environment
  (`docker inspect`, `docker exec`), because compose passes it in
  `environment`.

#### Fixed

- Edge: when the backend was slower than KrakenD's default 2 s timeout (the
  24 routes without their own `timeout`) or down, KrakenD answered 500 with an
  empty body, outside the C.3.2 format. The `tv30-auth` plugin now replaces
  any 5xx leaving KrakenD with 404
  `{"error":200,"description":"Platform resource unavailable: <reason>"}`,
  `Content-Type: application/json`, `Access-Control-Allow-Origin: *` and
  `API-Version`, in both modes. Timeouts are unchanged.
- tv3ws, `kex` pairing: `GET /tv3/authorize?pm=kex` answered only
  `{"challenge"}`; it now answers `{"challenge","key"}`, `key` being the
  server-side ECDH partial key (SEC 1 uncompressed point, base64url), as
  Table C.3 response format (3) and C.4.3.3 step 1 require. Without it a
  non-local client could not derive the symmetric key, so `kex` pairing never
  completed. Found by the new `kex` case of `scripts/test-auth.sh` and fixed
  during the integration run (`qrcode` answer unchanged). A conformance fix,
  not a design decision, but it awaits Luis's approval before commit. The PIN
  is still published without leading zeros (e.g. `42`); not changed.
- `scripts/test-consolidacao.sh`: the commander password no longer goes on
  the `curl` command line nor in the test container's environment; it is
  piped through stdin (`--data-urlencode "password@-"`).
- `scripts/test-auth.sh`: the `clientid` reuse case of the `kex` client now
  calls `/tv3/authorize` with `pm=kex&key=...` (it used `pm=qrcode` in both
  iterations).

#### Added

- tv3ws unit test `test/client-identification.test.ts` (in `npm test`):
  `clientid` reuse gives 101 without pop-up for each class, the stored
  refresh token still works on `/tv3/token`, a new `clientid` asks the viewer
  again, and a refused `clientid` gets 102 in the pop-up and 101 afterwards;
  `pm=kex` answers with `key` and a client that derives the secret from it
  solves the challenge and decrypts the first `/tv3/token`; `pm=qrcode` has
  no `key`.
- `scripts/test-auth.sh`:
  - every expected error also checks who answered: the edge (no
    `X-Powered-By: Express`) or tv3ws (with it); the 107 cases in `enforce`
    (no token, tampered, expired, no `Bearer`, blocked client) must come from
    the edge;
  - real non-local client flow with both pairing methods, `qrcode` and `kex`
    (PIN, ECDH P-256): `/tv3/authorize`, key read from the MQTT pop-up topic,
    `challenge-response`, encrypted first `/tv3/token` answer, access token
    with `class=non-local` used on the routes; skipped with an explicit
    warning when tv3ws has no HTTPS;
  - second `/tv3/authorize` with the same `clientid` -> 404 `{error:101}`;
    tv3ws stopped -> edge answers 404 `{error:200}` with
    `Access-Control-Allow-Origin` instead of an empty 500;
  - the same in warn mode, with tv3ws paused (`docker pause`, so its ports
    are not republished): 404 `{error:200}` from the edge that keeps
    `X-TV30-Auth-Warn: 107` (before, only the Go test covered warn).
- `scripts/test-template.sh`: runs the component template
  (`templates/componente/`, which now carries a minimal runnable example) for
  real in a temporary directory, checks that it joins `ginga_net`, talks to
  `mosquitto` and `redis` by service name, and that killing the inner process
  takes the container down and `restart` brings it back; it cleans up at the
  end.

#### Verified (integration run on 2026-10-04, images rebuilt locally)

Images `redis`, `edgegateway` and `tv3ws` rebuilt (`docker compose build`),
full stack up, edge in `warn`, variant `linux`. Real counts:

- edge plugin `go test` (krakend/builder:2.7.2, go1.22.7): 44 PASS, 0 FAIL;
  `gofmt`, `go vet` and `-buildmode=plugin` clean.
- tv3ws `npx tsc --noEmit` exit 0; `npm test`: 46 PASS, 0 FAIL.
- `scripts/test-auth.sh`: 145 PASS, 0 FAIL (warn + enforce; error origin;
  `clientid` reuse 101 for local, `qrcode` and `kex`; non-local pairing with
  `qrcode` and `kex` through 44642 and use/renewal through 44643; tv3ws
  stopped and paused -> 404 `{error:200}` from the edge).
- `scripts/test-template.sh`: 13 PASS, 0 FAIL.
- `scripts/test-dev-host.sh` (scenarios 1, 2, 3, docker mode): 27 PASS, 0 FAIL.
- `scripts/test-consolidacao.sh`, `scripts/test-fase0.sh`,
  `scripts/test-bcast-shutdown.sh`: exit 0, every printed check as expected
  (they print no PASS/FAIL count); commander: 401 without login, 200 with it.
- Redis 6379 without password still reached by tv3ws, aop, the edge plugin
  and `redis-cli`; the commander password appears in no container log and
  in no process command line.

#### Verified (correction run on 2026-10-04, images `redis` and `tv3ws` rebuilt locally)

- Image `tv30-redis`: redis-commander `0.9.0`, `httpAuth` mapped to
  `HTTP_USER`/`HTTP_PASSWORD`.
- `scripts/test-consolidacao.sh`: exit 0; commander 401 without login, 200
  with it, wrong password refused. Host `ps` sampled during the run: 14 lines
  with the `signin` call, 0 with the password.
- After `docker restart redis`: commander 401/200 again, password in 0 log
  lines and 0 process command lines, `PING` on 6379 from the host `+PONG`,
  `requirepass` empty.
- tv3ws `npx tsc --noEmit` exit 0; `npm test`: 46 PASS, 0 FAIL.
- `scripts/test-auth.sh`: 148 PASS, 0 FAIL (the 145 before plus the 3 warn
  cases with tv3ws paused).
- Stack left up: 6 containers, 0 restarts, edge `warn`, variant `linux`.

### Week of 2026-09-28 (semana de 28/09)

Decisions D1-D6 of the 28/09 meeting (see `docs/avaliacao-item9-credenciais.md`).
Credential validation ships in **warn** mode: no credential failure is blocked
yet; only undeclared routes (100) and router panics (200) are blocked, in both
modes. The provisional behaviour for the open questions (L1, L2, L4, L5) runs in
both modes: warn only logs and marks `X-TV30-Auth-Warn`, enforce blocks or lets
through. tv3ws itself still answers 107 to an invalid `Authorization` and 106 to
a non-local client over HTTP, in both modes (D1 clean-up pending).

#### Added

- Edge credential validation: new Go plugin `tv30-auth` (KrakenD http-server,
  standard library only) on both edge surfaces. It validates the access token
  (HS256, expiry, issuer, blocked client), the bind-token (keys registered via
  C.6.8 for the current service; HS256/HS512/RS256/RS512) and the client class,
  following a per-route policy (`auth`/`classes` in
  `infra/edgegateway/routes.json`). Errors use the C.3.2 format (404 + JSON).
  `AUTH_ENFORCE=warn` (default) only logs `[tv30-auth] WARN` and adds the
  `X-TV30-Auth-Warn` response header; `enforce` rejects.
- C.6.8 Broadcaster security APIs in tv3ws (`POST|GET|DELETE /tv3/bind-context`).
  Registered keys live in Redis `bind-context:{serviceId}` (`docs/modelo-redis.md`).
  The testbed does not issue bind-tokens.
- Edge routes `/tv3/bind-context` and `GET /manifest`.
- Edge: every response carries `Access-Control-Allow-Origin: *` (C.4.1.9.2),
  also when the request has no `Origin`; a non-preflight `OPTIONS` on a
  declared path gets 200 with `Access-Control-Allow-Origin`,
  `Access-Control-Allow-Methods` and `Access-Control-Allow-Headers`
  (C.4.1.9.3).
- `scripts/test-dev-host.sh` rewritten: runs a REAL module (tv3ws, aop or
  bcast) outside Docker with `npm ci && npm run dev` (host node, or
  `docker run --network host` when there is no node) in three combinations,
  checking host->Redis, host->MQTT and each module's own path, and restores
  the default stack at the end.
- Compose template for new components: `templates/componente/`.
- `scripts/test-auth.sh`: integration test of the edge credential checks
  against the running stack (44642/44643). Warn-mode checks, then the edge is
  recreated in `enforce` for 107/104/106/108/100, the real
  `/tv3/authorize` + `/tv3/token` flow, C.6.8 with HS256/HS512/RS256/RS512,
  service isolation, algorithm confusion and CORS preflight; it restores the
  previous mode and the Redis state at the end.
- `docs/ssdp-verificacao.md`: SSDP announcement measured at the tv3ws
  container, the `ginga_net` bridge and the WSL VM (it does not leave the VM),
  plus the home-network procedure and a node-ssdp client script.

#### Changed

- SSDP (tv3ws): advertised base URLs and LOCATION point to the edge ports
  (44642/44643, `/manifest`); an SSDP failure now ends the process
  (die-whole). The advertiser stays in tv3ws (open question L6). At boot it
  logs `[ssdp] AVISO` when the advertised host is loopback (the compose default
  `SERVER_URL=localhost`), when `EDGE_HTTP_PORT` is not 44642, and that
  `Server-SecureBaseURL` points to a port without TLS (L3).
- C.6.8 in tv3ws: RSA keys follow the same parsing rules as the edge (PEM only
  with a leading `-----BEGIN` and one of four labels; strict base64), checked by
  a shared fixture on both sides; RS256/RS512 keys too small for PKCS#1 v1.5
  get 101; HS duplicates are exact matches; `DELETE /tv3/bind-context` with no
  current service answers `{}`; `boundServices[].serviceId` is an integer.
- Root compose: `extra_hosts` (host.docker.internal) on aop,
  `BCAST_HOSTNAME` overridable, `JWT_ISSUER` passed to tv3ws from the same
  source as the edge. The edge gets `JWT_SECRET`, `JWT_ISSUER`, Redis and
  `AUTH_ENFORCE`.
- Docs: `ccws` leftovers renamed to `tv3ws`; `docs/apis-ccws.md` ->
  `docs/apis-tv3ws.md`; `docs/dev-local.md` rewritten; architecture docs
  aligned with the code (internal traffic is not MQTT-only; the broker plugin
  validates schemas only); note on old clones (`git submodule sync`).
- Scripts no longer hard-code `/mnt/d/...`; `test-virgin-up.sh` uses
  `tv3ws`; `test-consolidacao.sh` tests an existing route instead of the
  removed `POST /tv3/users`.

#### Fixed

- Edge: an undeclared path no longer resets the connection (Gin router
  panic, see `KNOWN-ISSUES.md`); the plugin answers 404 `{error:100}` before
  the router, on both surfaces and in both modes. A non-preflight `OPTIONS`
  on an undeclared path now gets the same C.3.2 error instead of Gin's
  plain-text 404/405.
- Edge: `POST /tv3/{serviceContextId}/users` reaches the same tv3ws handler as
  `POST /tv3/current-service/users` (C.6.14.1, bind-token *shall*) but was
  `token` only, so the bind-token could be skipped by changing the path. It is
  `token+bind` now (open question: keep or drop this non-normative route).
- Edge: an invalid `Authorization` no longer hides an associated `Origin` from
  the 106 check (L4); a token with class `local-associated` is checked against
  `clients:blocked`; the request path is quoted in the log (no forged lines).
- tv3ws: the yes/no authorization pop-up treated the AoP's `"false"` answer
  ("Nao" or timeout) as consent (`Boolean("false") === true`), authorizing
  the very client the viewer refused. Only `"true"` authorizes now.
- `scripts/preflight.sh`: a second `docker compose up -d` on a running stack
  failed with "a porta 44642 esta ocupada (-)", because without
  CAP_SYS_PTRACE the container cannot see that `docker-proxy` owns the port.
  The owner is now also identified by the `docker-proxy` command line. A
  native process on 44642 still blocks the start-up.
- `KNOWN-ISSUES.md`: removed the obsolete sensory-effect 500 entry (fixed
  by the no-op encoding of every edge route; tv3ws answers 200 with the
  renderer state).

#### Open (no decision yet; the provisional behaviour applies in both modes)

- L1 associated-client recognition (today: `Origin` in `origins:associated`;
  in enforce a forged `Origin` outside a browser skips every credential;
  decided by Luis on 2026-10-03: risk accepted; P1.3, own origin per app,
  still open),
  L2 per-service context id, L3 TLS/PKI at the edge, L4 tokens for associated
  clients, L5 bind-token clock, L6 SSDP advertiser placement (decided on
  2026-10-04: option B, a separate advertiser container), L7 releasing
  shared resources on key revocation, L8 bcast SSH URL in `.gitmodules`.
- Before any `enforce`: Redis has no password and 6379 is published on the
  host, and the edge trusts its keys (`origins:associated`, `bind-context:*`).
  Decided by Luis on 2026-10-03: the connection stays as is; only the admin
  UI got a password.
- Where the C.6.8 API lives (tv3ws or edge plugin) was not decided.
- `GET /tv3/authorize` without `pm` re-issued the refresh token of any already
  authorized `clientid` (pre-existing; the norm expects 101 on `clientid`
  reuse, C.6.1.4.4). Decided by Luis on 2026-10-03: 101 on reuse; no longer
  re-issued.
- SSDP default host is loopback; what `Server-SecureBaseURL` should announce
  while the edge has no TLS.

### Initial

#### Added

- Basic HTML application to simulate DTV+ app-based interface
- Lua Scheduler for managing the application state
- Node.js CC Webservice APIs
- Web app to explore MQTT broker topics
- Web app to debug remote device messages
