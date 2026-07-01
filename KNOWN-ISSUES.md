# Known Issues

## Sensory-effect POST returns HTTP 500 through KrakenD (effect still works)

**Symptom**
`POST /tv3/sensory-effect-renderers/{rendererId}` (e.g. from the uff service on
bcast) returns `500 Internal Server Error` in ~3ms, even though the effect
actually fires — the device receives the command and the lights change.

**Root cause**
The call goes `uff → KrakenD (gateway, :44642) → ccws`.

1. CCWS handles the request, sends the WebSocket command to the device (effect
   works), then replies `204 No Content` with an **empty body**
   (`ccws/src/modules/sensory-effect-renderers-api/controller.ts` →
   `res.status(204).json({})`).
2. The KrakenD endpoint for this route uses the **default `json` encoding**
   (no `no-op`), so KrakenD tries to **JSON-decode the empty 204 body**, fails,
   and returns **500** to the caller.

The side effect happens *before* the response is built, which is why it "works
but 500s." It is deterministic — reproduces on every call, and a restart does
not change it (it's code/config, not corrupted runtime state).

Confirmed in `infra/krakenD_external/krakend.json` and
`infra/krakenD_internal/krakend.json` (+ their `.linux.json` variants): the
`POST /tv3/sensory-effect-renderers/{rendererId}` endpoint has no
`output_encoding`/backend `encoding` set → defaults to JSON parsing.

**Status:** Not fixed on purpose — the effect works and a fix touches gateway
config / backend response shape that we don't want to disturb right now.

**Fix options (when we decide to address it)**

- *Option A (gateway, recommended):* set `"output_encoding": "no-op"` on the
  endpoint and `"encoding": "no-op"` on its backend, in all four KrakenD config
  files. KrakenD then passes the 204 through without parsing. Config-only, no
  rebuild.
- *Option B (backend):* return a JSON body instead of an empty 204, e.g.
  `res.status(200).json({ status: "ok" })` in the CCWS controller. Requires
  rebuilding/redeploying the CCWS image and deviates from the spec's 204.

**Quick verification (fires the light once):** direct call to CCWS returns a
clean 204, gateway call returns 500:

```
curl -i -X POST http://localhost:44652/tv3/sensory-effect-renderers/{id} \
  -H 'Content-Type: application/json' \
  -d '{"effectType":"LightType","action":"start","properties":[]}'   # → 204

curl -i -X POST http://localhost:44642/tv3/sensory-effect-renderers/{id} \
  -H 'Content-Type: application/json' \
  -d '{"effectType":"LightType","action":"start","properties":[]}'   # → 500
```
