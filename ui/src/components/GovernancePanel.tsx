"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import { Alert } from "./Alert";

type AuditEvent = {
  action?: string;
  ip?: string;
  actor?: string;
  ts?: number;
};

export function GovernancePanel() {
  const [audit, setAudit] = useState<AuditEvent[]>([]);
  const [auditStatus, setAuditStatus] = useState<string | null>(null);
  const [role, setRole] = useState("full_admin");
  const [roleMsg, setRoleMsg] = useState<string | null>(null);
  const [uriBlocks, setUriBlocks] = useState<string[]>([]);
  const [uriPrefix, setUriPrefix] = useState("");
  const [policyMsg, setPolicyMsg] = useState<string | null>(null);
  const [rqPrefix, setRqPrefix] = useState("/api/");
  const [rqLimit, setRqLimit] = useState("10");
  const [rqWindow, setRqWindow] = useState("60");

  const refreshAudit = useCallback(async () => {
    setAuditStatus(null);
    try {
      const res = (await adminAction("audit_list", { limit: 30 })) as {
        ok: true;
        events?: AuditEvent[];
      };
      setAudit(res.events ?? []);
    } catch (e) {
      setAuditStatus(e instanceof Error ? e.message : "加载审计失败");
    }
  }, []);

  const refreshRole = useCallback(async () => {
    try {
      const res = (await adminAction("admin_role_get")) as {
        ok: true;
        role?: string;
      };
      if (res.role) setRole(res.role);
    } catch {
      /* ignore */
    }
  }, []);

  const refreshUriBlocks = useCallback(async () => {
    try {
      const res = (await adminAction("uri_block_list")) as {
        ok: true;
        uri_blocks?: string[];
      };
      setUriBlocks(res.uri_blocks ?? []);
    } catch (e) {
      setPolicyMsg(e instanceof Error ? e.message : "加载 URI 黑名单失败");
    }
  }, []);

  useEffect(() => {
    void refreshAudit();
    void refreshRole();
    void refreshUriBlocks();
  }, [refreshAudit, refreshRole, refreshUriBlocks]);

  async function onRoleSave(e: FormEvent) {
    e.preventDefault();
    setRoleMsg(null);
    try {
      await adminAction("admin_role_set", { role });
      setRoleMsg("角色已更新");
    } catch (err) {
      setRoleMsg(err instanceof Error ? err.message : "保存失败");
    }
  }

  async function onUriAdd(e: FormEvent) {
    e.preventDefault();
    setPolicyMsg(null);
    if (!uriPrefix.trim()) return;
    try {
      await adminAction("uri_block_add", { prefix: uriPrefix.trim() });
      setUriPrefix("");
      await refreshUriBlocks();
      setPolicyMsg("已添加 URI 前缀拦截");
    } catch (err) {
      setPolicyMsg(err instanceof Error ? err.message : "添加失败");
    }
  }

  async function removeUri(prefix: string) {
    try {
      await adminAction("uri_block_del", { prefix });
      await refreshUriBlocks();
    } catch (err) {
      setPolicyMsg(err instanceof Error ? err.message : "删除失败");
    }
  }

  async function onRouteQuota(e: FormEvent) {
    e.preventDefault();
    setPolicyMsg(null);
    try {
      await adminAction("route_quota_set", {
        prefix: rqPrefix.trim(),
        limit: Number(rqLimit),
        window: Number(rqWindow),
      });
      setPolicyMsg("路由配额已保存");
    } catch (err) {
      setPolicyMsg(err instanceof Error ? err.message : "保存失败");
    }
  }

  return (
    <div className="flex flex-col gap-10">
      <section className="space-y-3">
        <h2 className="text-lg font-medium">管理审计</h2>
        {auditStatus ? <Alert tone="err" message={auditStatus} /> : null}
        <button
          type="button"
          className="rounded bg-zinc-900 px-3 py-1.5 text-sm text-white dark:bg-zinc-100 dark:text-zinc-900"
          onClick={() => void refreshAudit()}
        >
          刷新
        </button>
        <ul className="divide-y divide-zinc-200 rounded border border-zinc-200 text-sm dark:divide-zinc-800 dark:border-zinc-800">
          {audit.length === 0 ? (
            <li className="p-3 text-zinc-500">暂无记录</li>
          ) : (
            audit.map((ev, i) => (
              <li key={i} className="flex flex-wrap gap-2 p-3 font-mono text-xs">
                <span>{ev.action}</span>
                <span className="text-zinc-500">{ev.ip}</span>
                <span className="text-zinc-500">{ev.actor}</span>
              </li>
            ))
          )}
        </ul>
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-medium">RBAC（v1 主体角色）</h2>
        <form onSubmit={onRoleSave} className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-sm">
            角色
            <select
              value={role}
              onChange={(e) => setRole(e.target.value)}
              className="rounded border px-2 py-1 dark:border-zinc-700 dark:bg-zinc-900"
            >
              <option value="full_admin">full_admin</option>
              <option value="operator">operator</option>
              <option value="read_only">read_only</option>
            </select>
          </label>
          <button
            type="submit"
            className="rounded bg-zinc-900 px-3 py-1.5 text-sm text-white dark:bg-zinc-100 dark:text-zinc-900"
          >
            保存
          </button>
        </form>
        {roleMsg ? <p className="text-sm text-zinc-600">{roleMsg}</p> : null}
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-medium">策略（URI 封禁 / 路由配额）</h2>
        {policyMsg ? <Alert tone="ok" message={policyMsg} /> : null}
        <form onSubmit={onUriAdd} className="flex flex-wrap gap-2">
          <input
            placeholder="URI 前缀，如 /internal"
            value={uriPrefix}
            onChange={(e) => setUriPrefix(e.target.value)}
            className="min-w-[12rem] rounded border px-2 py-1 text-sm dark:border-zinc-700 dark:bg-zinc-900"
          />
          <button type="submit" className="rounded border px-3 py-1 text-sm">
            添加封禁
          </button>
        </form>
        <ul className="text-sm">
          {uriBlocks.map((p) => (
            <li key={p} className="flex items-center justify-between py-1">
              <code>{p}</code>
              <button type="button" className="text-red-600" onClick={() => void removeUri(p)}>
                删除
              </button>
            </li>
          ))}
        </ul>
        <form onSubmit={onRouteQuota} className="flex flex-wrap gap-2 border-t pt-4 dark:border-zinc-800">
          <input
            value={rqPrefix}
            onChange={(e) => setRqPrefix(e.target.value)}
            className="rounded border px-2 py-1 text-sm dark:border-zinc-700 dark:bg-zinc-900"
            placeholder="路由前缀"
          />
          <input
            value={rqLimit}
            onChange={(e) => setRqLimit(e.target.value)}
            className="w-20 rounded border px-2 py-1 text-sm"
            placeholder="limit"
          />
          <input
            value={rqWindow}
            onChange={(e) => setRqWindow(e.target.value)}
            className="w-20 rounded border px-2 py-1 text-sm"
            placeholder="window"
          />
          <button type="submit" className="rounded border px-3 py-1 text-sm">
            保存路由配额
          </button>
        </form>
      </section>
    </div>
  );
}