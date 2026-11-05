"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import type { ApiKeyRecord, ApiKeyListResponse } from "@/lib/admin-types";
import { Alert } from "./Alert";

const PAGE_SIZE = 10;

export function ApiKeyPanel() {
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [rows, setRows] = useState<ApiKeyRecord[]>([]);

  const [apiKey, setApiKey] = useState("");
  const [limit, setLimit] = useState("100");
  const [windowSec, setWindowSec] = useState("60");
  const [editingKey, setEditingKey] = useState<string | null>(null);

  const [status, setStatus] = useState<{ tone: "ok" | "err"; msg: string } | null>(
    null,
  );
  const [busy, setBusy] = useState(false);

  const loadPage = useCallback(async (p: number) => {
    setBusy(true);
    setStatus(null);
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
      setStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "加载列表失败",
      });
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void loadPage(1);
  }, [loadPage]);

  function resetForm() {
    setEditingKey(null);
    setApiKey("");
    setLimit("100");
    setWindowSec("60");
  }

  function startEdit(row: ApiKeyRecord) {
    setEditingKey(row.api_key);
    setApiKey(row.api_key);
    setLimit(String(row.limit));
    setWindowSec(String(row.window));
    setStatus(null);
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setStatus(null);
    try {
      const res = await adminAction("upsert_apikey", {
        api_key: apiKey.trim(),
        limit: Number(limit),
        window: Number(windowSec),
      });
      setStatus({
        tone: "ok",
        msg: res.msg ?? (editingKey ? "已更新" : "已创建"),
      });
      resetForm();
      await loadPage(page);
    } catch (err) {
      setStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "保存失败",
      });
    } finally {
      setBusy(false);
    }
  }

  async function onDelete(key: string) {
    if (!confirm(`删除 API Key「${key}」？`)) return;
    setBusy(true);
    setStatus(null);
    try {
      const res = await adminAction("del_apikey", { api_key: key });
      setStatus({ tone: "ok", msg: res.msg ?? "已删除" });
      if (editingKey === key) resetForm();
      const nextPage =
        rows.length === 1 && page > 1 ? page - 1 : page;
      await loadPage(nextPage);
    } catch (err) {
      setStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "删除失败",
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-8">
      <div>
        <h2 className="text-lg font-semibold tracking-tight">API Key</h2>
        <p className="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
          增删改查与分页列表（<code className="font-mono text-xs">apikey_list</code>
          、<code className="font-mono text-xs">upsert_apikey</code>、
          <code className="font-mono text-xs">del_apikey</code>）。
        </p>
      </div>

      {status ? <Alert tone={status.tone} message={status.msg} /> : null}

      <form
        onSubmit={onSubmit}
        className="grid gap-4 rounded-xl border border-zinc-200 p-5 dark:border-zinc-800"
      >
        <h3 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          {editingKey ? "编辑 API Key" : "新建 API Key"}
        </h3>
        <label className="grid gap-1 text-sm">
          <span>API Key</span>
          <input
            required
            readOnly={!!editingKey}
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
        <div className="flex flex-wrap gap-2">
          <button
            type="submit"
            disabled={busy}
            className="rounded-md bg-zinc-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900"
          >
            {editingKey ? "保存修改" : "创建"}
          </button>
          {editingKey ? (
            <button
              type="button"
              disabled={busy}
              onClick={resetForm}
              className="rounded-md border border-zinc-300 px-4 py-2 text-sm dark:border-zinc-700"
            >
              取消编辑
            </button>
          ) : null}
        </div>
      </form>

      <div className="overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
        <div className="flex items-center justify-between border-b border-zinc-200 bg-zinc-50 px-4 py-3 dark:border-zinc-800 dark:bg-zinc-900/80">
          <span className="text-sm font-medium">列表（共 {total} 条）</span>
          <button
            type="button"
            disabled={busy}
            onClick={() => void loadPage(page)}
            className="text-sm text-zinc-600 hover:underline disabled:opacity-50 dark:text-zinc-400"
          >
            刷新
          </button>
        </div>
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
                  {busy ? "加载中…" : "暂无 API Key"}
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
                        disabled={busy}
                        onClick={() => startEdit(row)}
                        className="text-sm hover:underline disabled:opacity-50"
                      >
                        编辑
                      </button>
                      <button
                        type="button"
                        disabled={busy}
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
        {totalPages > 1 ? (
          <div className="flex items-center justify-between border-t border-zinc-200 px-4 py-3 dark:border-zinc-800">
            <span className="text-sm text-zinc-500">
              第 {page} / {totalPages} 页
            </span>
            <div className="flex gap-2">
              <button
                type="button"
                disabled={busy || page <= 1}
                onClick={() => void loadPage(page - 1)}
                className="rounded-md border border-zinc-300 px-3 py-1 text-sm disabled:opacity-40 dark:border-zinc-700"
              >
                上一页
              </button>
              <button
                type="button"
                disabled={busy || page >= totalPages}
                onClick={() => void loadPage(page + 1)}
                className="rounded-md border border-zinc-300 px-3 py-1 text-sm disabled:opacity-40 dark:border-zinc-700"
              >
                下一页
              </button>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
