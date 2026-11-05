import crypto from "crypto";
import type { AdminAction, AdminResponse } from "./admin-types";

const DEFAULT_SECRET = "admin-secret-2026";
const DEFAULT_URL = "http://127.0.0.1:8080/admin/gw/v1";

function adminSecret(): string {
  return process.env.GATEWAY_ADMIN_SECRET ?? DEFAULT_SECRET;
}

function adminUrl(): string {
  return process.env.GATEWAY_ADMIN_URL ?? DEFAULT_URL;
}

export function signAdminPayload(
  action: AdminAction,
  fields: Record<string, string | number> = {},
) {
  const ts = Math.floor(Date.now() / 1000);
  const nonce = crypto.randomUUID();
  const raw = `${ts}:${nonce}`;
  const sign = crypto
    .createHmac("sha256", adminSecret())
    .update(raw)
    .digest("hex");

  return { ts, nonce, sign, action, ...fields };
}

export async function callAdminV1(
  action: AdminAction,
  fields: Record<string, string | number> = {},
): Promise<{ status: number; data: AdminResponse }> {
  const payload = signAdminPayload(action, fields);
  const res = await fetch(adminUrl(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
    cache: "no-store",
  });

  let data: AdminResponse;
  try {
    data = (await res.json()) as AdminResponse;
  } catch {
    data = { ok: false, msg: "invalid response from gateway" };
  }

  return { status: res.status, data };
}
