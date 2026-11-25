"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import { Alert } from "./Alert";

type Mode = "business" | "admin";
type PanelMode = "list" | "create";

const CONFIG: Record<
  Mode,
  {
    title: string;
    description: string;
    listAction: "whitelist_list" | "admin_whitelist_list";
    addAction: "whitelist_add" | "admin_whitelist_add";
    delAction: "whitelist_del" | "admin_whitelist_del";
    listKey: "whitelist" | "admin_whitelist";
    addLabel: string;
  }
> = {
  business: {
    title: "业务 IP 白名单",
    description:
      "网关 access 阶段使用的 whitelist:ip。点击「新增 IP」在列表区域录入，保存后恢复列表。",
    listAction: "whitelist_list",
    addAction: "whitelist_add",
    delAction: "whitelist_del",
    listKey: "whitelist",
    addLabel: "新增 IP",
  },
  admin: {
    title: "管理端 IP 白名单",
    description:
      "admin_api_v1 校验的 admin:whitelist:ip。点击「新增 IP」在列表区域录入，保存后恢复列表。",
    listAction: "admin_whitelist_list",
    addAction: "admin_whitelist_add",
    delAction: "admin_whitelist_del",
    listKey: "admin_whitelist",
    addLabel: "新增 IP",
  },
};

export function IpWhitelistPanel({ mode }: { mode: Mode }) {
  const cfg = CONFIG[mode];
  const [ips, setIps] = useState<string[]>([]);
  const [panelMode, setPanelMode] = useState<PanelMode>("list");
  const [newIp, setNewIp] = useState("");

  const [listStatus, setListStatus] = useState<{
    tone: "ok" | "err";
    msg: string;
  } | null>(null);
  const [formStatus, setFormStatus] = useState<{
    tone: "ok" | "err";
    msg: string;
  } | null>(null);
  const [listLoading, setListLoading] = useState(false);
  const [formSubmitting, setFormSubmitting] = useState(false);

  const refreshList = useCallback(
    async (silent = false) => {
      setListLoading(true);
      if (!silent) {
        setListStatus(null);
      }
      try {
        const res = await adminAction(cfg.listAction);
        const list =
          cfg.listKey === "whitelist"
            ? "whitelist" in res
              ? (res.whitelist ?? [])
              : []
            : "admin_whitelist" in res
              ? (res.admin_whitelist ?? [])
              : [];
        setIps([...list].sort());
      } catch (err) {
        setListStatus({
          tone: "err",
          msg: err instanceof Error ? err.message : "加载失败",
        });
      } finally {
        setListLoading(false);
      }
    },
    [cfg.listAction, cfg.listKey],
  );

  useEffect(() => {
    void refreshList();
  }, [refreshList]);

  function closeForm() {
    setPanelMode("list");
    setNewIp("");
    setFormStatus(null);
  }

  function openCreate() {
    setNewIp("");
    setFormStatus(null);
    setPanelMode("create");
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const ip = newIp.trim();
    if (!ip) return;
    setFormSubmitting(true);
    setFormStatus(null);
    try {
      const res = await adminAction(cfg.addAction, { ip });
      closeForm();
      setListStatus({ tone: "ok", msg: res.msg ?? "已添加" });
      await refreshList(true);
    } catch (err) {
      setFormStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "添加失败",
      });
    } finally {
      setFormSubmitting(false);
    }
  }

  async function onRemove(ip: string) {
    if (!confirm(`从白名单移除「${ip}」？`)) return;
    setListLoading(true);
    setListStatus(null);
    try {
      const res = await adminAction(cfg.delAction, { ip });
      setListStatus({ tone: "ok", msg: res.msg ?? "已移除" });
      await refreshList(true);
    } catch (err) {
      setListStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "移除失败",
      });
      setListLoading(false);
    }
  }

  const showingForm = panelMode === "create";

  return (
    <div className="ui-panel overflow-hidden">
      <div className="ui-panel-header">
        <span>
          {showingForm ? `${cfg.addLabel}` : `记录 · ${ips.length} 条`}
        </span>
        <div className="ui-panel-header-actions">
            {showingForm ? (
              <button
                type="button"
                disabled={formSubmitting}
                onClick={closeForm}
                className="ui-btn-ghost disabled:opacity-50"
              >
                返回列表
              </button>
            ) : (
              <>
                <button
                  type="button"
                  disabled={listLoading}
                  onClick={openCreate}
                  className="ui-btn-primary disabled:opacity-50"
                >
                  {cfg.addLabel}
                </button>
                <button
                  type="button"
                  disabled={listLoading}
                  onClick={() => void refreshList()}
                  className="ui-btn-ghost disabled:opacity-50"
                >
                  刷新列表
                </button>
              </>
            )}
          </div>
        </div>

        {listStatus && !showingForm ? (
          <div className="border-b border-[var(--border-subtle)] px-4 py-2">
            <Alert tone={listStatus.tone} message={listStatus.msg} />
          </div>
        ) : null}

        {showingForm ? (
          <form
            onSubmit={onSubmit}
            className="flex min-h-[240px] flex-col px-6 py-8 sm:px-8"
          >
            {formStatus ? (
              <div className="mb-4">
                <Alert tone={formStatus.tone} message={formStatus.msg} />
              </div>
            ) : null}

            <div className="grid flex-1 gap-4 content-start">
              <label className="grid max-w-md gap-1 text-sm">
                <span>IP 地址</span>
                <input
                  required
                  autoFocus
                  value={newIp}
                  onChange={(e) => setNewIp(e.target.value)}
                  placeholder="127.0.0.1"
                  className="ui-input font-mono"
                />
              </label>
            </div>

            <div className="mt-6 flex items-center justify-end gap-2 border-t border-[var(--border-subtle)] pt-4">
              <button type="button" disabled={formSubmitting} onClick={closeForm} className="ui-btn-ghost">
                取消
              </button>
              <button
                type="submit"
                disabled={formSubmitting}
                className="ui-btn-primary disabled:opacity-50"
              >
                {formSubmitting ? "保存中…" : "保存"}
              </button>
            </div>
          </form>
        ) : (
          <div className="relative">
            {listLoading ? (
              <div className="ui-loading-veil min-h-[7.5rem]">列表更新中…</div>
            ) : null}
            <table className="ui-table">
              <thead>
                <tr>
                  <th>IP 地址</th>
                  <th className="w-28 text-right">操作</th>
                </tr>
              </thead>
              <tbody>
                {ips.length === 0 ? (
                  <tr>
                    <td
                      colSpan={2}
                      className="py-10 text-center"
                      style={{ color: "var(--fg-muted)" }}
                    >
                      {listLoading
                        ? "加载中…"
                        : `暂无 IP，点击「${cfg.addLabel}」`}
                    </td>
                  </tr>
                ) : (
                  ips.map((ip) => (
                    <tr
                      key={ip}
                    >
                      <td className="ui-mono-data">{ip}</td>
                      <td className="text-right">
                        <div className="ui-action-group inline-flex">
                          <button
                            type="button"
                            disabled={listLoading}
                            className="ui-action-danger"
                            onClick={() => void onRemove(ip)}
                          >
                            移除
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}
    </div>
  );
}
