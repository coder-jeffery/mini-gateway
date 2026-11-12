# Service CORS Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Redis-backed Service CRUD, longest-prefix dynamic routing, per-Service CORS policies, and a master-detail management page.

**Architecture:** Store each Service as JSON under `service:{id}` with IDs in `service:index`. A focused Service repository provides validation and CRUD to both admin APIs; a router caches sorted Service snapshots in `lua_shared_dict`, resolves the request before authentication, and sets the dynamic proxy target. The existing CORS module reads the matched Service policy first and falls back to environment configuration.

**Tech Stack:** OpenResty/Lua, Redis and existing store abstraction, Nginx variable proxying, Next.js 16/React 19/TypeScript, Python smoke tests.

---

## File map

- Create `nginx/lua/service_admin.lua`: Service validation, uniqueness, CRUD, serialization.
- Create `nginx/lua/service_router.lua`: cached snapshot loading, path-boundary matching, proxy target construction.
- Create `test/test_service_admin.py`: HMAC admin CRUD and validation smoke tests.
- Create `test/test_service_routing.py`: routing and Service CORS integration smoke tests.
- Create `ui/src/components/ServiceCorsPanel.tsx`: master-detail Service management.
- Modify `nginx/lua/admin_api.lua`: expose shared Service actions through v0.
- Modify `nginx/lua/admin_api_v1.lua`: expose shared Service actions through HMAC v1.
- Modify `nginx/lua/access_check.lua`: resolve Service before CORS and authentication.
- Modify `nginx/lua/cors.lua`: read per-request Service policy with environment fallback.
- Modify `nginx/conf/nginx.conf`: shared cache and dynamic proxy variables.
- Modify `ui/src/lib/admin-types.ts`: Service types and actions.
- Modify `ui/src/app/api/admin/route.ts`: allow Service actions.
- Modify `ui/src/components/AdminDashboard.tsx`: add Service CORS tab.
- Modify `README.md`: document Service routing and management.

### Task 1: Service repository and validation

**Files:**
- Create: `nginx/lua/service_admin.lua`
- Create: `test/test_service_admin.py`

- [ ] **Step 1: Write failing CRUD tests**

Add tests that call signed HMAC actions:

```python
def test_service_crud() -> None:
    create = signed_payload(
        "service_create",
        name="orders",
        path_prefix="/api/orders",
        upstream_url="http://orders:8080",
        cors_enabled=1,
        cors_allow_origins="https://app.example.com",
        cors_allow_methods="GET,POST,OPTIONS",
        cors_allow_headers="Content-Type,Authorization,X-Api-Key",
        cors_expose_headers="X-Request-Id",
        cors_max_age=600,
        cors_allow_credentials=0,
    )
    status, data = post_admin_v1(create)
    assert status == 201, data
    service_id = data["service"]["id"]
    status, data = post_admin_v1(signed_payload("service_get", id=service_id))
    assert status == 200 and data["service"]["name"] == "orders", data
```

Also assert duplicate `name` and `path_prefix` return 409, malformed paths and upstream URLs return 400, update persists, and delete returns 200.

- [ ] **Step 2: Run tests and verify the missing action failure**

Run:

```bash
python3 test/test_service_admin.py
```

Expected: first create request returns `400 unknown action`.

- [ ] **Step 3: Implement the repository**

Implement these entry points in `service_admin.lua`:

```lua
function _M.create_backend(backend, handle, req) end
function _M.update_backend(backend, handle, req) end
function _M.delete_backend(backend, handle, id) end
function _M.get_backend(backend, handle, id) end
function _M.list_backend(backend, handle) end
function _M.clear_cache() ngx.shared.service_cache:flush_all() end
```

Normalize trailing slashes except `/`, parse booleans from `0|1`, clamp `cors_max_age` to a non-negative integer, reject credentials combined with wildcard origins, and scan `service:index` for uniqueness.

- [ ] **Step 4: Run repository syntax checks**

Run:

```bash
luac -p nginx/lua/service_admin.lua
```

Expected: exit 0.

### Task 2: Wire Service actions into both admin APIs

**Files:**
- Modify: `nginx/lua/admin_api.lua`
- Modify: `nginx/lua/admin_api_v1.lua`

- [ ] **Step 1: Add shared action dispatch**

Require `service_admin` and map:

```lua
service_create -> create_backend
service_update -> update_backend
service_delete -> delete_backend
service_get    -> get_backend
service_list   -> list_backend
```

For v1, wrap the existing Redis connection as:

```lua
local backend = require "store.backends.redis"
local handle = { _kind = "redis", _red = red }
```

Return repository status codes unchanged and close each handle exactly once.

- [ ] **Step 2: Run the CRUD smoke tests**

Run:

```bash
python3 test/test_service_admin.py
```

Expected: all Service CRUD and validation tests pass.

- [ ] **Step 3: Run existing admin regression tests**

Run:

```bash
python3 test/test_hmac.py
```

Expected: all HMAC tests pass.

### Task 3: Longest-prefix router and dynamic upstream

**Files:**
- Create: `nginx/lua/service_router.lua`
- Create: `test/test_service_routing.py`
- Modify: `nginx/lua/access_check.lua`
- Modify: `nginx/conf/nginx.conf`

- [ ] **Step 1: Write failing routing tests**

Create Services for `/api` and `/api/orders`, then assert:

```python
status, body = request("/api/orders/42?detail=1", api_key="mini-key")
assert status == 200
assert body["url"].endswith("/api/orders/42?detail=1")
assert body["headers"]["Host"] == expected_orders_host
```

Assert `/api/orders-v2` selects `/api`, and an unmatched path uses the default upstream.

- [ ] **Step 2: Add router cache and matcher**

Implement:

```lua
function _M.resolve(uri, request_uri)
    -- load service:snapshot from ngx.shared.service_cache or current store
    -- sort descending by #path_prefix
    -- return matching service and upstream_url .. request_uri
end
```

Use a five-second cache TTL. A prefix matches only when the URI is equal to the prefix or the next character is `/`.

- [ ] **Step 3: Resolve before CORS/authentication**

At the start of `access_check.lua`:

```lua
local service, target, err = service_router.resolve(ngx.var.uri, ngx.var.request_uri)
if err then return deny(503, "service configuration unavailable") end
ngx.ctx.gateway_service = service
if target then ngx.var.gateway_proxy_url = target end
```

- [ ] **Step 4: Enable variable proxying**

Declare:

```nginx
lua_shared_dict service_cache 4m;
set $gateway_proxy_url "https://httpbin.org/get";
proxy_pass $gateway_proxy_url;
proxy_set_header Host $proxy_host;
```

- [ ] **Step 5: Run routing tests**

Run:

```bash
python3 test/test_service_routing.py
```

Expected: longest-prefix, path-boundary, query preservation, and fallback tests pass.

### Task 4: Per-Service CORS policy

**Files:**
- Modify: `nginx/lua/cors.lua`
- Modify: `test/test_service_routing.py`

- [ ] **Step 1: Add failing Service CORS cases**

Assert the `/api/orders` Service permits its configured Origin while `/api/users` rejects that Origin, and a 401 response on the orders path still exposes `Access-Control-Allow-Origin`.

- [ ] **Step 2: Introduce policy accessors**

Replace direct environment reads with a policy object:

```lua
local function current_policy()
    local service = ngx.ctx.gateway_service
    if service then return service end
    return {
        cors_enabled = config.cors_enabled(),
        cors_allow_origins = config.cors_allow_origins(),
        -- remaining CORS values
    }
end
```

All preflight and response functions must use the same policy snapshot.

- [ ] **Step 3: Run CORS regressions**

Run:

```bash
python3 test/test_cors.py
python3 test/test_service_routing.py
```

Expected: global fallback and Service-specific tests pass.

### Task 5: Admin API types and proxy allowlist

**Files:**
- Modify: `ui/src/lib/admin-types.ts`
- Modify: `ui/src/app/api/admin/route.ts`

- [ ] **Step 1: Add Service types**

Define:

```ts
export type ServiceRecord = {
  id: string;
  name: string;
  path_prefix: string;
  upstream_url: string;
  cors_enabled: boolean;
  cors_allow_origins: string;
  cors_allow_methods: string;
  cors_allow_headers: string;
  cors_expose_headers: string;
  cors_max_age: number;
  cors_allow_credentials: boolean;
};
```

Add the five Service actions and response fields `service?: ServiceRecord` and `services?: ServiceRecord[]`.

- [ ] **Step 2: Allow actions through the Next route**

Add all five actions to `ACTIONS`. Keep request fields as strings/numbers; the page sends booleans as `0|1`.

- [ ] **Step 3: Run TypeScript lint**

Run:

```bash
cd ui && npm run lint
```

Expected: exit 0.

### Task 6: Master-detail Service CORS page

**Files:**
- Create: `ui/src/components/ServiceCorsPanel.tsx`
- Modify: `ui/src/components/AdminDashboard.tsx`

- [ ] **Step 1: Build list and selection state**

The component loads `service_list`, sorts by `path_prefix`, and renders the selected record on the right. Include explicit loading, empty, and API error states.

- [ ] **Step 2: Build the route form**

Add controlled inputs for `name`, `path_prefix`, and `upstream_url`. Create uses `service_create`; editing uses `service_update` with immutable `id`.

- [ ] **Step 3: Build the CORS form**

Add enable and credentials checkboxes, comma-separated inputs for Origins/Methods/Allow Headers/Expose Headers, and numeric Max Age. Disable CORS detail fields when CORS is off.

- [ ] **Step 4: Add save and delete behavior**

On success refresh the list and retain the saved Service selection. Confirm before delete; after deletion select the next record.

- [ ] **Step 5: Add the dashboard tab**

Extend:

```ts
type Tab = "apikeys" | "business-ip" | "admin-ip" | "services";
```

Render `ServiceCorsPanel` for the `services` tab.

- [ ] **Step 6: Run frontend verification**

Run:

```bash
cd ui
npm run lint
npm run build
```

Expected: both commands exit 0.

### Task 7: Documentation and full verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document Service examples**

Document Redis mode, path matching, original URI preservation, five-second propagation delay, and the Service CORS page.

- [ ] **Step 2: Validate syntax and diffs**

Run:

```bash
luac -p nginx/lua/service_admin.lua nginx/lua/service_router.lua nginx/lua/cors.lua nginx/lua/access_check.lua
docker compose config --quiet
git diff --check
```

Expected: exit 0.

- [ ] **Step 3: Run the complete gateway smoke suite**

Run with Redis-mode containers:

```bash
python3 test/test_hmac.py
python3 test/test_service_admin.py
python3 test/test_cors.py
python3 test/test_service_routing.py
```

Expected: all scripts print their success message and exit 0.

- [ ] **Step 4: Review scope**

Confirm no generated `.superpowers/brainstorm`, `.DS_Store`, build output, or unrelated files are staged.
