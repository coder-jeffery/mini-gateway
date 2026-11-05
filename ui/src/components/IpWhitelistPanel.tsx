"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import { Alert } from "./Alert";

type Mode = "business" | "admin";

const CONFIG: Record<
  Mode,
  {
    title: string;
    description: string;
    listAction: "whitelist_list" | "admin_whitelist_list";
    addAction: "whitelist_add" | "admin_whitelist_add";
    delAction: "whitelist_del" | "admin_whitelist_del";
    listKey: "whitelist" | "admin_whitelist";
  }
> = {
  business: {
    title: "业务 IP 白名单",
    description: "网关 access 阶段使用的 whitelist:ip（业务侧放行 IP）。",
    listAction: "whitelist_list",
    addAction: "whitelist_add",
    delAction: "whitelist_del",
    listKey: "whitelist",
  },
  admin: {
    title: "管理端 IP 白名单",
    description: "admin_api_v1 校验的 admin:whitelist:ip（允许调用管理接口的 IP）。",
    listAction: "admin_whitelist_list",
    addAction: "admin_whitelist_add",
    delAction: "admin_whitelist_del",
    listKey: "admin_whitelist",
  },
};

export function IpWhitelistPanel({ mode }: { mode: Mode }) {
  const cfg = CONFIG[mode];
  const [ips, setIps] = useState<string[]>([]);
  const [newIp, setNewIp] = useState("");
  const [status, setStatus] = useState<{ tone: "ok" | "err"; msg: string } | null>(
    null,
  );
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    setBusy(true);
    setStatus(null);
    try {
      const res = await adminAction(cfg.listAction);
      const list =
        cfg.listKey === "whitelist"
          ? ("whitelist" in res ? (res.whitelist ?? []) : [])
          : ("admin_whitelist" in res ? (res.admin_whitelist ?? []) : []);
      setIps([...list].sort());
    } catch (err) {
      setStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "加载失败",
      });
    } finally {
      setBusy(false);
    }
  }, [cfg.listAction, cfg.listKey]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function onAdd(e: FormEvent) {
    e.preventDefault();
    const ip = newIp.trim();
    if (!ip) return;
    setBusy(true);
    setStatus(null);
    try {
      const res = await adminAction(cfg.addAction, { ip });
      setStatus({ tone: "ok", msg: res.msg ?? "已添加" });
      setNewIp("");
      await refresh();
    } catch (err) {
      setStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "添加失败",
      });
    } finally {
      setBusy(false);
    }
  }

  async function onRemove(ip: string) {
    setBusy(true);
    setStatus(null);
    try {
      const res = await adminAction(cfg.delAction, { ip });
      setStatus({ tone: "ok", msg: res.msg ?? "已移除" });
      await refresh();
    } catch (err) {
      setStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "移除失败",
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold tracking-tight">{cfg.title}</h2>
        <p className="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
          {cfg.description}
        </p>
      </div>

      {status ? <Alert tone={status.tone} message={status.msg} /> : null}

      <form
        onSubmit={onAdd}
        className="flex flex-col gap-3 rounded-xl border border-zinc-200 p-5 sm:flex-row sm:items-end dark:border-zinc-800"
      >
        <label className="grid flex-1 gap-1 text-sm">
          <span>IP 地址</span>
          <input
            required
            value={newIp}
            onChange={(e) => setNewIp(e.target.value)}
            placeholder="127.0.0.1"
            className="rounded-md border border-zinc-300 bg-white px-3 py-2 font-mono text-sm dark:border-zinc-700 dark:bg-zinc-950"
          />
        </label>
        <button
          type="submit"
          disabled={busy}
          className="rounded-md bg-zinc-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900"
        >
          添加
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => void refresh()}
          className="rounded-md border border-zinc-300 px-4 py-2 text-sm disabled:opacity-50 dark:border-zinc-700"
        >
          刷新
        </button>
      </form>

      <div className="overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
        <table className="w-full text-left text-sm">
          <thead className="bg-zinc-50 text-zinc-600 dark:bg-zinc-900/80 dark:text-zinc-400">
            <tr>
              <th className="px-4 py-3 font-medium">IP</th>
              <th className="px-4 py-3 font-medium w-28">操作</th>
            </tr>
          </thead>
          <tbody>
            {ips.length === 0 ? (
              <tr>
                <td
                  colSpan={2}
                  className="px-4 py-8 text-center text-zinc-500 dark:text-zinc-400"
                >
                  {busy ? "加载中…" : "暂无白名单 IP"}
                </td>
              </tr>
            ) : (
              ips.map((ip) => (
                <tr
                  key={ip}
                  className="border-t border-zinc-100 dark:border-zinc-800"
                >
                  <td className="px-4 py-3 font-mono">{ip}</td>
                  <td className="px-4 py-3">
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void onRemove(ip)}
                      className="text-sm text-red-600 hover:underline disabled:opacity-50 dark:text-red-400"
                    >
                      移除
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
