"use client";

import { FormEvent, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import { Alert } from "./Alert";

export function ApiKeyPanel() {
  const [apiKey, setApiKey] = useState("");
  const [limit, setLimit] = useState("100");
  const [windowSec, setWindowSec] = useState("60");
  const [deleteKey, setDeleteKey] = useState("");
  const [status, setStatus] = useState<{ tone: "ok" | "err"; msg: string } | null>(
    null,
  );
  const [busy, setBusy] = useState(false);

  async function onUpsert(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setStatus(null);
    try {
      const res = await adminAction("upsert_apikey", {
        api_key: apiKey.trim(),
        limit: Number(limit),
        window: Number(windowSec),
      });
      setStatus({ tone: "ok", msg: res.msg ?? "API Key 已保存" });
    } catch (err) {
      setStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : "保存失败",
      });
    } finally {
      setBusy(false);
    }
  }

  async function onDelete(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setStatus(null);
    try {
      const res = await adminAction("del_apikey", {
        api_key: deleteKey.trim(),
      });
      setStatus({ tone: "ok", msg: res.msg ?? "API Key 已删除" });
      setDeleteKey("");
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
          通过 <code className="font-mono text-xs">upsert_apikey</code> /{" "}
          <code className="font-mono text-xs">del_apikey</code> 管理配额。v1
          接口不提供列表查询，请记录已创建的 Key。
        </p>
      </div>

      {status ? <Alert tone={status.tone} message={status.msg} /> : null}

      <form
        onSubmit={onUpsert}
        className="grid gap-4 rounded-xl border border-zinc-200 p-5 dark:border-zinc-800"
      >
        <h3 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          创建 / 更新
        </h3>
        <label className="grid gap-1 text-sm">
          <span>API Key</span>
          <input
            required
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            className="rounded-md border border-zinc-300 bg-white px-3 py-2 font-mono text-sm dark:border-zinc-700 dark:bg-zinc-950"
            placeholder="abc123"
          />
        </label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="grid gap-1 text-sm">
            <span>Limit（窗口内最大请求数）</span>
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
        <button
          type="submit"
          disabled={busy}
          className="w-fit rounded-md bg-zinc-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900"
        >
          保存
        </button>
      </form>

      <form
        onSubmit={onDelete}
        className="grid gap-4 rounded-xl border border-zinc-200 p-5 dark:border-zinc-800"
      >
        <h3 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          删除
        </h3>
        <label className="grid gap-1 text-sm">
          <span>API Key</span>
          <input
            required
            value={deleteKey}
            onChange={(e) => setDeleteKey(e.target.value)}
            className="rounded-md border border-zinc-300 bg-white px-3 py-2 font-mono text-sm dark:border-zinc-700 dark:bg-zinc-950"
          />
        </label>
        <button
          type="submit"
          disabled={busy}
          className="w-fit rounded-md border border-red-300 px-4 py-2 text-sm font-medium text-red-700 disabled:opacity-50 dark:border-red-900 dark:text-red-300"
        >
          删除 Key
        </button>
      </form>
    </div>
  );
}
