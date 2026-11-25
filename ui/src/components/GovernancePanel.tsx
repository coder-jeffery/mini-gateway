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
    <div className="flex flex-col gap-8">
      <section className="ui-panel overflow-hidden">
        <div className="ui-panel-header">
          <span>管理审计</span>
          <div className="ui-panel-header-actions">
            <button
              type="button"
              className="ui-btn-ghost"
              onClick={() => void refreshAudit()}
            >
              刷新
            </button>
          </div>
        </div>
        <div className="space-y-4 p-5 sm:p-6">
          {auditStatus ? <Alert tone="err" message={auditStatus} /> : null}
          <ul
            className="overflow-hidden rounded-md border text-sm [&>li+li]:border-t"
            style={{ borderColor: "var(--border-subtle)" }}
          >
            {audit.length === 0 ? (
              <li className="p-4" style={{ color: "var(--fg-muted)" }}>
                暂无记录
              </li>
            ) : (
              audit.map((ev, i) => (
                <li
                  key={i}
                  className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-[var(--border-subtle)] p-3 font-mono text-xs"
                >
                  <span className="font-medium" style={{ color: "var(--fg-primary)" }}>
                    {ev.action}
                  </span>
                  <span style={{ color: "var(--fg-muted)" }}>{ev.ip}</span>
                  <span style={{ color: "var(--fg-muted)" }}>{ev.actor}</span>
                  {ev.ts ? (
                    <span className="ml-auto text-[10px]" style={{ color: "var(--fg-muted)" }}>
                      {new Date(ev.ts * 1000).toLocaleString()}
                    </span>
                  ) : null}
                </li>
              ))
            )}
          </ul>
        </div>
      </section>

      <section className="ui-panel overflow-hidden">
        <div className="ui-panel-header">
          <span>RBAC · v1</span>
        </div>
        <div className="space-y-4 p-5 sm:p-6">
          <form onSubmit={onRoleSave} className="flex flex-wrap items-end gap-3">
            <label className="flex min-w-[12rem] flex-col gap-1 text-sm">
              <span style={{ color: "var(--fg-secondary)" }}>角色</span>
              <select
                value={role}
                onChange={(e) => setRole(e.target.value)}
                className="ui-input"
              >
                <option value="full_admin">full_admin</option>
                <option value="operator">operator</option>
                <option value="read_only">read_only</option>
              </select>
            </label>
            <button type="submit" className="ui-btn-primary">
              保存
            </button>
          </form>
          {roleMsg ? (
            <Alert
              tone={roleMsg.includes("失败") ? "err" : "ok"}
              message={roleMsg}
            />
          ) : null}
        </div>
      </section>

      <section className="ui-panel overflow-hidden">
        <div className="ui-panel-header">
          <span>数据面策略</span>
        </div>
        <div className="space-y-5 p-5 sm:p-6">
          {policyMsg ? (
            <Alert
              tone={policyMsg.includes("失败") ? "err" : "ok"}
              message={policyMsg}
            />
          ) : null}
          <form onSubmit={onUriAdd} className="flex flex-wrap items-end gap-2">
            <label className="flex min-w-[14rem] flex-1 flex-col gap-1 text-sm">
              <span style={{ color: "var(--fg-secondary)" }}>URI 前缀封禁</span>
              <input
                placeholder="/internal"
                value={uriPrefix}
                onChange={(e) => setUriPrefix(e.target.value)}
                className="ui-input font-mono"
              />
            </label>
            <button type="submit" className="ui-btn-primary">
              添加封禁
            </button>
          </form>
          <ul className="text-sm">
            {uriBlocks.length === 0 ? (
              <li style={{ color: "var(--fg-muted)" }}>暂无封禁前缀</li>
            ) : (
              uriBlocks.map((p) => (
                <li
                  key={p}
                  className="flex items-center justify-between border-b py-2 last:border-0"
                  style={{ borderColor: "var(--border-subtle)" }}
                >
                  <code className="ui-code">{p}</code>
                  <button
                    type="button"
                    className="ui-link ui-link-danger"
                    onClick={() => void removeUri(p)}
                  >
                    删除
                  </button>
                </li>
              ))
            )}
          </ul>
          <form
            onSubmit={onRouteQuota}
            className="flex flex-wrap items-end gap-2 border-t pt-4"
            style={{ borderColor: "var(--border-subtle)" }}
          >
            <label className="flex min-w-[10rem] flex-1 flex-col gap-1 text-sm">
              <span style={{ color: "var(--fg-secondary)" }}>路由配额</span>
              <input
                value={rqPrefix}
                onChange={(e) => setRqPrefix(e.target.value)}
                className="ui-input font-mono"
                placeholder="路由前缀"
              />
            </label>
            <label className="flex w-24 flex-col gap-1 text-sm">
              <span style={{ color: "var(--fg-secondary)" }}>Limit</span>
              <input
                value={rqLimit}
                onChange={(e) => setRqLimit(e.target.value)}
                className="ui-input"
              />
            </label>
            <label className="flex w-24 flex-col gap-1 text-sm">
              <span style={{ color: "var(--fg-secondary)" }}>Window</span>
              <input
                value={rqWindow}
                onChange={(e) => setRqWindow(e.target.value)}
                className="ui-input"
              />
            </label>
            <button type="submit" className="ui-btn-primary">
              保存配额
            </button>
          </form>
        </div>
      </section>
    </div>
  );
}