"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { Alert } from "./Alert";
import type { ServiceRecord } from "@/lib/admin-types";

type Notice = { tone: "ok" | "err"; message: string } | null;

const emptyForm = {
  name: "",
  path_prefix: "",
  upstream_url: "",
  upstream_peers: "",
  cors_enabled: "0",
  cors_allow_origins: "",
  cors_allow_methods: "GET,POST,OPTIONS",
  cors_allow_headers: "Content-Type,X-Api-Key",
  cors_allow_credentials: "0",
};

export function ServiceRoutePanel() {
  const [services, setServices] = useState<ServiceRecord[]>([]);
  const [form, setForm] = useState(emptyForm);
  const [notice, setNotice] = useState<Notice>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const res = await fetch("/api/admin", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "service_list" }),
    });
    const data = (await res.json()) as { ok?: boolean; msg?: string; services?: ServiceRecord[] };
    if (!res.ok || !data.ok) {
      setNotice({ tone: "err", message: data.msg || "加载服务失败" });
      return;
    }
    setServices(data.services || []);
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void load();
    }, 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  async function createService(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setNotice(null);
    try {
      const res = await fetch("/api/admin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "service_create",
          ...form,
          cors_enabled: Number(form.cors_enabled),
          cors_allow_credentials: Number(form.cors_allow_credentials),
        }),
      });
      const data = (await res.json()) as { ok?: boolean; msg?: string };
      if (!res.ok || !data.ok) {
        setNotice({ tone: "err", message: data.msg || "创建失败" });
        return;
      }
      setForm(emptyForm);
      setNotice({ tone: "ok", message: "服务已创建" });
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function removeService(id: string) {
    setBusy(true);
    setNotice(null);
    try {
      const res = await fetch("/api/admin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "service_delete", id }),
      });
      const data = (await res.json()) as { ok?: boolean; msg?: string };
      if (!res.ok || !data.ok) {
        setNotice({ tone: "err", message: data.msg || "删除失败" });
        return;
      }
      setNotice({ tone: "ok", message: "服务已删除" });
      await load();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      {notice ? <Alert tone={notice.tone} message={notice.message} /> : null}
      <form onSubmit={createService} className="grid gap-3">
        <input className="rounded border px-3 py-2 text-sm" placeholder="name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
        <input className="rounded border px-3 py-2 text-sm" placeholder="path_prefix，例如 /api/orders" value={form.path_prefix} onChange={(e) => setForm({ ...form, path_prefix: e.target.value })} required />
        <input className="rounded border px-3 py-2 text-sm" placeholder="upstream_url，例如 http://127.0.0.1:9001" value={form.upstream_url} onChange={(e) => setForm({ ...form, upstream_url: e.target.value })} required />
        <input className="rounded border px-3 py-2 text-sm" placeholder="upstream_peers，可选 host:port[:weight],..." value={form.upstream_peers} onChange={(e) => setForm({ ...form, upstream_peers: e.target.value })} />
        <input className="rounded border px-3 py-2 text-sm" placeholder="cors origins" value={form.cors_allow_origins} onChange={(e) => setForm({ ...form, cors_allow_origins: e.target.value })} />
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={form.cors_enabled === "1"} onChange={(e) => setForm({ ...form, cors_enabled: e.target.checked ? "1" : "0" })} />
          启用 CORS
        </label>
        <button type="submit" disabled={busy} className="rounded bg-zinc-900 px-3 py-2 text-sm text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900">
          创建服务
        </button>
      </form>
      <ul className="divide-y divide-zinc-200 dark:divide-zinc-800">
        {services.map((service) => (
          <li key={service.id} className="flex items-start justify-between gap-3 py-3 text-sm">
            <div>
              <p className="font-medium">{service.name}</p>
              <p className="text-zinc-500">{service.path_prefix} → {service.upstream_url}</p>
              {service.upstream_peers ? <p className="text-zinc-500">{service.upstream_peers}</p> : null}
            </div>
            <button type="button" disabled={busy} onClick={() => void removeService(service.id)} className="text-red-600">
              删除
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
