# Developer portal (minimal, P3-5)

This gateway exposes a **data plane** on `GET/POST /*` with `X-Api-Key` or OAuth2 Bearer, and a **control plane** on `/admin/gw/v1` (HMAC).

## Apply for an API key

1. Contact your platform admin (or use CI bootstrap key `mini-key` in dev).
2. Admin issues a key via `upsert_apikey` (see [operation-doc.md](../operation-doc.md)).
3. Call the gateway with header `X-Api-Key: <your-key>`.

## OpenAPI sketch

Base URL: `http://127.0.0.1:8080`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | none | Liveness |
| GET | `/ready` | none | Storage readiness |
| GET | `/metrics` | none | Prometheus text |
| ANY | `/*` | `X-Api-Key` or Bearer | Proxied upstream |
| POST | `/admin/gw/v1` | HMAC body | Admin actions |

Import the [Postman collection](../postman/) for concrete examples.