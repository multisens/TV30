# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

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
  in enforce a forged `Origin` outside a browser skips every credential),
  L2 per-service context id, L3 TLS/PKI at the edge, L4 tokens for associated
  clients, L5 bind-token clock, L6 SSDP advertiser placement, L7 releasing
  shared resources on key revocation, L8 bcast SSH URL in `.gitmodules`.
- Before any `enforce`: Redis has no password and 6379 is published on the
  host, and the edge trusts its keys (`origins:associated`, `bind-context:*`).
- Where the C.6.8 API lives (tv3ws or edge plugin) was not decided.
- `GET /tv3/authorize` without `pm` re-issues the refresh token of any already
  authorized `clientid` (pre-existing; the norm expects 101 on `clientid`
  reuse, C.6.1.4.4).
- SSDP default host is loopback; what `Server-SecureBaseURL` should announce
  while the edge has no TLS.

### Initial

#### Added

- Basic HTML application to simulate DTV+ app-based interface
- Lua Scheduler for managing the application state
- Node.js CC Webservice APIs
- Web app to explore MQTT broker topics
- Web app to debug remote device messages
