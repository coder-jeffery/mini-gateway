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
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold tracking-tight">{cfg.title}</h2>
        <p className="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
          {cfg.description}
        </p>
      </div>

      <div className="overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-zinc-200 bg-zinc-50 px-4 py-3 dark:border-zinc-800 dark:bg-zinc-900/80">
          <span className="text-sm font-medium">
            {showingForm
              ? `${cfg.addLabel} — ${cfg.title}`
              : `列表（共 ${ips.length} 条）`}
          </span>
          <div className="flex flex-wrap gap-2">
            {showingForm ? (
              <button
                type="button"
                disabled={formSubmitting}
                onClick={closeForm}
                className="rounded-md border border-zinc-300 px-3 py-1.5 text-sm disabled:opacity-50 dark:border-zinc-700"
              >
                返回列表
              </button>
            ) : (
              <>
                <button
                  type="button"
                  disabled={listLoading}
                  onClick={openCreate}
                  className="rounded-md bg-zinc-900 px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900"
                >
                  {cfg.addLabel}
                </button>
                <button
                  type="button"
                  disabled={listLoading}
                  onClick={() => void refreshList()}
                  className="rounded-md border border-zinc-300 px-3 py-1.5 text-sm disabled:opacity-50 dark:border-zinc-700"
                >
                  刷新列表
                </button>
              </>
            )}
          </div>
        </div>

        {listStatus && !showingForm ? (
          <div className="border-b border-zinc-200 px-4 py-2 dark:border-zinc-800">
            <Alert tone={listStatus.tone} message={listStatus.msg} />
          </div>
        ) : null}

        {showingForm ? (
          <form
            onSubmit={onSubmit}
            className="flex min-h-[240px] flex-col px-5 py-6"
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
                  className="rounded-md border border-zinc-300 bg-white px-3 py-2 font-mono text-sm dark:border-zinc-700 dark:bg-zinc-950"
                />
              </label>
            </div>

            <div className="mt-6 flex items-center justify-end gap-2 border-t border-zinc-100 pt-4 dark:border-zinc-800">
              <button
                type="button"
                disabled={formSubmitting}
                onClick={closeForm}
                className="rounded-md border border-zinc-300 px-4 py-2 text-sm dark:border-zinc-700"
              >
                取消
              </button>
              <button
                type="submit"
                disabled={formSubmitting}
                className="rounded-md bg-zinc-900 px-5 py-2 text-sm font-medium text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900"
              >
                {formSubmitting ? "保存中…" : "保存"}
              </button>
            </div>
          </form>
        ) : (
          <div className="relative">
            {listLoading ? (
              <div className="absolute inset-0 z-10 flex min-h-[120px] items-center justify-center bg-white/60 dark:bg-zinc-950/60">
                <span className="text-sm text-zinc-600 dark:text-zinc-400">
                  列表更新中…
                </span>
              </div>
            ) : null}
            <table className="w-full text-left text-sm">
              <thead className="border-b border-zinc-200 text-zinc-600 dark:border-zinc-800 dark:text-zinc-400">
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
                      className="px-4 py-10 text-center text-zinc-500 dark:text-zinc-400"
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
                      className="border-t border-zinc-100 dark:border-zinc-800"
                    >
                      <td className="px-4 py-3 font-mono">{ip}</td>
                      <td className="px-4 py-3">
                        <button
                          type="button"
                          disabled={listLoading}
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
        )}
      </div>
    </div>
  );
}
