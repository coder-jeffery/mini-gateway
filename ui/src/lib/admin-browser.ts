"use client";

import type { AdminAction, AdminResponse } from "./admin-types";

export async function adminAction(
  action: AdminAction,
  fields: Record<string, string | number> = {},
): Promise<AdminResponse> {
  const res = await fetch("/api/admin", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, ...fields }),
  });
  const data = (await res.json()) as AdminResponse;
  if (!res.ok || !data.ok) {
    const msg = !data.ok ? data.msg : "request failed";
    throw new Error(msg);
  }
  return data;
}
