"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import type { ApiKeyRecord, ApiKeyListResponse } from "@/lib/admin-types";
import { Alert } from "./Alert";

const PAGE_SIZE = 10;

type PanelMode = "list" | "create" | "edit";

export function ApiKeyPanel() {
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [rows, setRows] = useState<ApiKeyRecord[]>([]);

  const [mode, setMode] = useState<PanelMode>("list");
  const [apiKey, setApiKey] = useState("");
  const [limit, setLimit] = useState("100");
  const [windowSec, setWindowSec] = useState("60");
  const [editingKey, setEditingKey] = useState<string | null>(null);

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

  const refreshList = useCallback(async (p: number, silent = false) => {
    setListLoading(true);
    if (!silent) {
      setListStatus(null);
    }
    try {
      const res = (await adminAction("apikey_list", {
        page: p,
        page_size: PAGE_SIZE,
      })) as ApiKeyListResponse;
      setRows(res.apikeys ?? []);
      setTotal(res.total ?? 0);
      setPage(res.page ?? p);
      setTotalPages(res.total_pages ?? 0);
    } catch (err) {
      setListStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "加载列表失败",
      });
    } finally {
      setListLoading(false);
    }
  }, []);

  useEffect(() => {
    void refreshList(1);
  }, [refreshList]);

  function closeForm() {
    setMode("list");
    setEditingKey(null);
    setApiKey("");
    setLimit("100");
    setWindowSec("60");
    setFormStatus(null);
  }

  function openCreate() {
    setEditingKey(null);
    setApiKey("");
    setLimit("100");
    setWindowSec("60");
    setFormStatus(null);
    setMode("create");
  }

  function openEdit(row: ApiKeyRecord) {
    setEditingKey(row.api_key);
    setApiKey(row.api_key);
    setLimit(String(row.limit));
    setWindowSec(String(row.window));
    setFormStatus(null);
    setMode("edit");
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setFormSubmitting(true);
    setFormStatus(null);
    const isCreate = mode === "create";
    try {
      const res = await adminAction("upsert_apikey", {
        api_key: apiKey.trim(),
        limit: Number(limit),
        window: Number(windowSec),
      });
      closeForm();
      setListStatus({
        tone: "ok",
        msg: res.msg ?? (isCreate ? "已创建" : "已更新"),
      });
      const targetPage = isCreate ? 1 : page;
      await refreshList(targetPage, true);
    } catch (err) {
      setFormStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "保存失败",
      });
    } finally {
      setFormSubmitting(false);
    }
  }

  async function onDelete(key: string) {
    if (!confirm(`删除 API Key「${key}」？`)) return;
    setListLoading(true);
    setListStatus(null);
    try {
      const res = await adminAction("del_apikey", { api_key: key });
      if (mode === "edit" && editingKey === key) {
        closeForm();
      }
      setListStatus({ tone: "ok", msg: res.msg ?? "已删除" });
      const nextPage = rows.length === 1 && page > 1 ? page - 1 : page;
      await refreshList(nextPage, true);
    } catch (err) {
      setListStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "删除失败",
      });
      setListLoading(false);
    }
  }

  const showingForm = mode === "create" || mode === "edit";

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold tracking-tight">API Key</h2>
        <p className="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
          点击「新增 API Key」，列表区域切换为录入窗体；保存后恢复列表并刷新。
        </p>
      </div>

      <div className="overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-zinc-200 bg-zinc-50 px-4 py-3 dark:border-zinc-800 dark:bg-zinc-900/80">
          <span className="text-sm font-medium">
            {showingForm
              ? mode === "create"
                ? "新增 API Key"
                : "编辑 API Key"
              : `列表（共 ${total} 条）`}
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
                  新增 API Key
                </button>
                <button
                  type="button"
                  disabled={listLoading}
                  onClick={() => void refreshList(page)}
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
            className="flex min-h-[320px] flex-col px-5 py-6"
          >
            {formStatus ? (
              <div className="mb-4">
                <Alert tone={formStatus.tone} message={formStatus.msg} />
              </div>
            ) : null}

            <div className="grid flex-1 gap-4 content-start">
              <label className="grid gap-1 text-sm">
                <span>API Key</span>
                <input
                  required
                  autoFocus
                  readOnly={mode === "edit"}
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  className="rounded-md border border-zinc-300 bg-white px-3 py-2 font-mono text-sm read-only:opacity-70 dark:border-zinc-700 dark:bg-zinc-950"
                  placeholder="abc123"
                />
              </label>
              <div className="grid gap-4 sm:grid-cols-2">
                <label className="grid gap-1 text-sm">
                  <span>Limit</span>
                  <input
                    required
                    type="number"
                    min={1}
                    value={limit}
                    onChange={(e) => setLimit(e.target.value)}
                    className="rounded-md border border-zinc-300 bg-white px-3 py-2 dark:border-zinc-700 dark:bg-zinc-950"
                  />
                </label>
                <label className="grid gap-1 text-sm">
                  <span>Window（秒）</span>
                  <input
                    required
                    type="number"
                    min={1}
                    value={windowSec}
                    onChange={(e) => setWindowSec(e.target.value)}
                    className="rounded-md border border-zinc-300 bg-white px-3 py-2 dark:border-zinc-700 dark:bg-zinc-950"
                  />
                </label>
              </div>
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
          <>
            <div className="relative">
              {listLoading ? (
                <div className="absolute inset-0 z-10 flex items-center justify-center bg-white/60 dark:bg-zinc-950/60">
                  <span className="text-sm text-zinc-600 dark:text-zinc-400">
                    列表更新中…
                  </span>
                </div>
              ) : null}
              <table className="w-full text-left text-sm">
                <thead className="border-b border-zinc-200 text-zinc-600 dark:border-zinc-800 dark:text-zinc-400">
                  <tr>
                    <th className="px-4 py-3 font-medium">API Key</th>
                    <th className="px-4 py-3 font-medium">Limit</th>
                    <th className="px-4 py-3 font-medium">Window</th>
                    <th className="px-4 py-3 font-medium w-36">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.length === 0 ? (
                    <tr>
                      <td
                        colSpan={4}
                        className="px-4 py-10 text-center text-zinc-500 dark:text-zinc-400"
                      >
                        {listLoading
                          ? "加载中…"
                          : "暂无 API Key，点击「新增 API Key」"}
                      </td>
                    </tr>
                  ) : (
                    rows.map((row) => (
                      <tr
                        key={row.api_key}
                        className="border-t border-zinc-100 dark:border-zinc-800"
                      >
                        <td className="px-4 py-3 font-mono">{row.api_key}</td>
                        <td className="px-4 py-3">{row.limit}</td>
                        <td className="px-4 py-3">{row.window}s</td>
                        <td className="px-4 py-3">
                          <div className="flex gap-3">
                            <button
                              type="button"
                              disabled={listLoading}
                              onClick={() => openEdit(row)}
                              className="text-sm hover:underline disabled:opacity-50"
                            >
                              编辑
                            </button>
                            <button
                              type="button"
                              disabled={listLoading}
                              onClick={() => void onDelete(row.api_key)}
                              className="text-sm text-red-600 hover:underline disabled:opacity-50 dark:text-red-400"
                            >
                              删除
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
            {totalPages > 1 ? (
              <div className="flex items-center justify-between border-t border-zinc-200 px-4 py-3 dark:border-zinc-800">
                <span className="text-sm text-zinc-500">
                  第 {page} / {totalPages} 页
                </span>
                <div className="flex gap-2">
                  <button
                    type="button"
                    disabled={listLoading || page <= 1}
                    onClick={() => void refreshList(page - 1)}
                    className="rounded-md border border-zinc-300 px-3 py-1 text-sm disabled:opacity-40 dark:border-zinc-700"
                  >
                    上一页
                  </button>
                  <button
                    type="button"
                    disabled={listLoading || page >= totalPages}
                    onClick={() => void refreshList(page + 1)}
                    className="rounded-md border border-zinc-300 px-3 py-1 text-sm disabled:opacity-40 dark:border-zinc-700"
                  >
                    下一页
                  </button>
                </div>
              </div>
            ) : null}
          </>
        )}
      </div>
    </div>
  );
}
