import { NextRequest, NextResponse } from "next/server";
import { callAdmin, probeGatewayStorage } from "@/lib/admin-client";
import type { AdminAction } from "@/lib/admin-types";

const ACTIONS: AdminAction[] = [
  "upsert_apikey",
  "del_apikey",
  "get_apikey",
  "apikey_list",
  "whitelist_add",
  "whitelist_del",
  "whitelist_list",
  "admin_whitelist_add",
  "admin_whitelist_del",
  "admin_whitelist_list",
];

export async function POST(req: NextRequest) {
  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ ok: false, msg: "invalid json" }, { status: 400 });
  }

  const action = body.action as AdminAction | undefined;
  if (!action || !ACTIONS.includes(action)) {
    return NextResponse.json(
      { ok: false, msg: "missing or invalid action" },
      { status: 400 },
    );
  }

  const fields: Record<string, string | number> = {};
  for (const [key, value] of Object.entries(body)) {
    if (key === "action") continue;
    if (typeof value === "string" || typeof value === "number") {
      fields[key] = value;
    }
  }

  try {
    const { status, data } = await callAdmin(action, fields);
    return NextResponse.json(data, { status });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "gateway unreachable";
    return NextResponse.json({ ok: false, msg }, { status: 502 });
  }
}

/** Connectivity probe; returns gateway `storage` (memory | redis | sqlite). */
export async function GET() {
  try {
    const probe = await probeGatewayStorage();
    if (!probe.ok) {
      return NextResponse.json(
        { ok: false, msg: probe.msg ?? "gateway unreachable" },
        { status: 502 },
      );
    }
    return NextResponse.json({
      ok: true,
      storage: probe.storage,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "gateway unreachable";
    return NextResponse.json({ ok: false, msg }, { status: 502 });
  }
}
