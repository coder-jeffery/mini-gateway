# mini-gateway Product Development Plan (MVP First)

> **Goal:** Evolve the existing OpenResty gateway prototype through **minimal shippable MVP → production-ready → capability expansion**, aligned with the usual API gateway split of **control plane / data plane / observability plane**, without boiling the ocean on all 15 items in `develop-design.md` at once.

**Languages:** [中文](to-do-list.md) · English (this file)

---

## 1. Architecture Layers (This Repo)

How common “multi-plane” gateway terminology maps here (clear boundaries only—we are not deploying the full enterprise stack):

| Plane | Responsibility | Where it lives in mini-gateway |
|-------|----------------|--------------------------------|
| **Data plane** | Proxy, auth, rate limits, circuit breaker execution | `nginx/lua/access_check.lua`, `oauth_validate.lua`, `nginx.conf` |
| **Control plane** | Config CRUD, distribution, storage backends | `admin_api.lua`, `admin_api_v1.lua`, `store/*` |
| **Management plane** | Human-facing console | `ui/` (Next.js → HMAC to `/admin/gw/v1`) |
| **Observability plane** | Metrics, logs, alerting | `log_access.lua`; **gaps:** `/metrics`, redaction, dashboards |
| **Policy / security plane** | Central policies (WAF, OPA, etc.) | Today: **IP whitelist + admin IP whitelist + OAuth scopes**; later OPA / path blocklists |
| **Extension plane** | Plugins / Wasm / external auth | **Not built**; out of MVP scope |
| **Developer plane** | Portal, docs, key onboarding | **Not built**; optional in P3 |
| **AI plane** | Model routing, token metering | **Not built**; optional in P4 |

Capability matrix (aligned with typical gateway checklists, with phase tags):

| Domain | Capability | Status | Phase |
|--------|------------|--------|-------|
| Ingress & routing | Fixed upstream proxy | ✅ httpbin demo | **P0** configurable upstream |
| | Dynamic routing / canary / mirror | ❌ | P3 |
| AuthN/Z | API Key | ✅ | — |
| | OAuth2 JWT (HS256/RS256) | ✅ | — |
| | Admin Bearer + HMAC | ✅ v0/v1 | **P0** unify admin APIs |
| Security | Business + admin IP whitelists | ✅ | — |
| | Log redaction, path/UA blocking | ❌ | P0 redaction; P2 path blocklist |
| Traffic control | Sliding window, per-key quota | ✅ | — |
| | Multi-dimension / per-route / global caps | ❌ | P2 |
| | Error-rate circuit breaker | ⚠️ simple pass/reject on storage errors | **P1** |
| | Leaky-bucket queueing | ❌ | P3 |
| Observability | Async access logs, request ID | ✅ | — |
| | Prometheus `/metrics` | ❌ | **P1** |
| | Log sampling, admin audit event types | ❌ | P2 |
| Admin / storage | memory / redis / sqlite | ✅ data path | **P0** UI + v1 same storage story |
| Protocol | HTTP | ✅ | P4 WebSocket |

---

## 2. Baseline (Shipped — No Further Scheduling)

Source of truth is the repo; regression via `test/`, `postman/`, `operation-doc.md`.

- [x] **Data plane:** `X-Api-Key` / OAuth2 Bearer (`api_key` \| `bearer` \| `both`)
- [x] **Rate limiting:** sliding window; per API Key `limit`/`window`; OAuth defaults configurable
- [x] **Whitelists:** business IPs skip rate limits; admin IPs protect admin APIs
- [x] **Storage:** `GATEWAY_STORAGE=memory|redis|sqlite` + worker bootstrap
- [x] **Control plane v0:** `/admin/gw` (Bearer admin token + full store abstraction)
- [x] **Control plane v1:** `/admin/gw/v1` (HMAC + nonce replay protection; **Redis-only today**)
- [x] **Management plane:** UI with three tabs (API keys, business/admin whitelists)
- [x] **Light observability:** `X-Request-Id`, rate-limit headers, async access logs via `log_by_lua`
- [x] **Deployment:** Docker Compose three-container scripts, `.env.example`

---

## 3. MVP Definition (P0: Minimal Product Grade)

**One-liner:** The team can attach the gateway to a **real upstream** using **config + admin UI + health probes**, operate keys and whitelists on **redis or sqlite**, and **never leak secrets in logs**.

### 3.1 Success Criteria (Acceptance)

| # | Criterion | How to verify |
|---|-----------|---------------|
| M1 | Upstream URL, timeouts, and Host header configurable **without** code changes for release | Env or admin config + `curl` to a real backend |
| M2 | `GET /health` (process) and `GET /ready` (storage reachable) | K8s/Compose healthchecks pass |
| M3 | **One admin path story:** UI and automation can CRUD in the chosen storage mode | `test_hmac.py` + UI manual; same for sqlite mode |
| M4 | Access and error logs **redact** `api_key` and Bearer tokens | Spot-check `gateway:access_log` / file logs |
| M5 | Root **README:** architecture, capability table, storage mode guide, ops entrypoints | New engineer brings up full stack in ~30 minutes |
| M6 | **CI** runs at least `test/test.py`, `test_hmac.py`, `test_oauth2.py` (optional merge gate) | Green PRs |

### 3.2 P0 Task List

| ID | Priority | Task | Deliverables | Depends on |
|----|----------|------|--------------|------------|
| P0-1 | P0 | **Configurable upstream:** `GATEWAY_UPSTREAM_URL` (+ proxy timeouts) | `nginx.conf` + `gateway_config.lua` | — |
| P0-2 | P0 | **Health endpoints:** `/health`, `/ready` (ready probes current storage) | New `location`s + docs | P0-1 |
| P0-3 | P0 | **Unify control plane:** `admin_api_v1` on `store` abstraction (same backends as v0) | Lua refactor + test updates | — |
| P0-4 | P0 | **UI storage modes:** sqlite/memory via v0 proxy or unified v1; document in Compose/README | `ui` route + README | P0-3 |
| P0-5 | P0 | **Audit redaction:** mask `api_key` and `Authorization` in `log_access.lua` | Lua + test/script | — |
| P0-6 | P1→P0 | **token_list:** implement or remove “not implemented” from admin docs | `admin_api.lua` | — |
| P0-7 | P0 | **Product README** aligned with capability matrix in this doc | `README.md` | — |
| P0-8 | P0 | **CI workflow:** GitHub Actions for Python tests + UI build | `.github/workflows/*` | — |

> **Intentionally out of P0:** Prometheus, multi-dimension rate limits, canary, RBAC, business HMAC, WebSocket, AI plugins (see P1+).

---

## 4. Roadmap (P1 → P4)

Aligned with the recommended order in `develop-design.md`, plus product gaps.

### P1 — Production-Ready (Observability + Resilience)

**Goal:** Hook up monitoring and alerting; storage blips should not mean “one error → pass everything.”

| ID | Task | Acceptance |
|----|------|------------|
| P1-1 | **Error-rate circuit breaker** (`lua_shared_dict` window stats + half-open probes) | Inject Redis failures; observe state machine and response headers |
| P1-2 | **`GET /metrics`** (Prometheus: 2xx/401/429/503, rate-limit hits, breaker, storage errors) | `curl /metrics` + optional Grafana dashboard JSON |
| P1-3 | **Configurable breaker/degrade policy** (pass/reject + threshold env vars) | Document in `.env.example` |
| P1-4 | **Admin action audit** (separate stream/list from access logs) | Key changes are traceable |
| P1-5 | **shared_dict local cache** (apikey metadata, business whitelist TTL + invalidation on admin writes) | Load test shows lower Redis QPS (documented) |

### P2 — Policy Depth (Rate Limits + Security)

**Goal:** Move from “one key, one quota” to operable policy.

| ID | Task | Acceptance |
|----|------|------------|
| P2-1 | **Rate-limit dimensions:** `api_key` / `ip` / `api_key+ip` (env or per-key metadata) | `wrk` with multiple source IPs |
| P2-2 | **Per-route quota:** URI prefix → limit/window (admin actions) | Same key, different paths → different 429 behavior |
| P2-3 | **Global gateway QPS cap** | Over cap → 429 + metric |
| P2-4 | **URI blocklist + UA filtering** (admin-configured) | Match → 403 |
| P2-5 | **Access log sampling** (always sample failures; configurable success ratio) | Redis pressure bounded at high QPS |

### P3 — Platform (Routing + Governance)

| ID | Task | Acceptance |
|----|------|------------|
| P3-1 | **Canary routing** (apikey/ip/percent → multiple upstreams, `X-Gray-Tag`) | Rules CRUD-able |
| P3-2 | **Header/URI rewrite** (admin rule table) | Integration tests |
| P3-3 | **Admin RBAC** (roles + permissions; `token_issue` binds role) | read_only cannot delete keys |
| P3-4 | **Config snapshots & rollback** (keys, whitelists, routes) | Mistakes recoverable |
| P3-5 | **Minimal developer plane:** static OpenAPI + key request flow (docs + Postman OK) | Optional |

### P4 — Extensions (As Needed)

| ID | Task | Notes |
|----|------|-------|
| P4-1 | Leaky-bucket queueing rate limit | Breaker interaction: `develop-design.md` §2 |
| P4-2 | Business HMAC signature validation | Distinct from Admin v1 |
| P4-3 | Rate warm-up (ramp quota for new keys) | |
| P4-4 | WebSocket + connection/message limits | Large `nginx.conf` changes |
| P4-5 | Bandwidth rate limiting | Byte counting |
| P4-6 | AI plane: model routing, token metering, safety | Often better as a separate sub-project |

---

## 5. Suggested Iteration Cadence

| Iteration | Suggested duration | Theme | Must ship |
|-----------|-------------------|-------|-----------|
| **Iter-0** | Current | Technical proof | Baseline (§2) |
| **Iter-1** | 2–3 weeks | **P0 MVP** | P0-1–P0-8 green + M1–M6 |
| **Iter-2** | 2 weeks | **P1 observability** | P1-1, P1-2, P1-3 |
| **Iter-3** | 2–3 weeks | **P1 perf/audit** | P1-4, P1-5 |
| **Iter-4+** | Business-driven | P2/P3 slices | One demonstrable policy feature per iteration |

**Principles**

1. **Data plane defaults unchanged:** new behavior behind env flags; defaults match today’s production behavior.  
2. **Control plane before management plane:** admin action + tests first, then UI.  
3. **Observability ships with features:** each new policy adds metrics and log fields.  
4. **Single storage abstraction:** no new “Redis-only” admin paths after P0-3.

---

## 6. Docs & Test Mapping

| Doc | Purpose |
|-----|---------|
| `operation-doc.md` | Ops curl / OAuth / HMAC playbook (update upstream + health in P0) |
| `develop-design.md` | Detailed design for P2+; **not in P0 scope** |
| `QA.md` | Design/interview notes; breaker and log timer behavior |
| `postman/` | External API contract; add health/metrics after P0 |
| `test/*.py` | CI source of truth; add cases for each new admin action |

---

## 7. Quick Checklist (for Planning)

**P0 MVP (no “product release” tag until all are done)**

- [ ] P0-1 Configurable upstream  
- [ ] P0-2 `/health`, `/ready`  
- [ ] P0-3 admin v1 → store abstraction  
- [ ] P0-4 UI all storage modes  
- [ ] P0-5 Log redaction  
- [ ] P0-6 `token_list` or remove from docs  
- [ ] P0-7 Product README  
- [ ] P0-8 CI  

**P1 production-ready**

- [ ] P1-1 Error-rate circuit breaker  
- [ ] P1-2 `/metrics`  
- [ ] P1-3 Breaker policy configuration  
- [ ] P1-4 Admin audit log  
- [ ] P1-5 Config local cache  

(P2–P4 items: see §4; pull from backlog per iteration.)

---

## 8. Changelog

| Date | Description |
|------|-------------|
| 2026-03-26 | MVP-first rewrite (CN): layers, baseline, P0 acceptance, P1–P4 roadmap, aligned with `develop-design.md` |
| 2026-03-26 | English edition (`to-do-list.en.md`) |
