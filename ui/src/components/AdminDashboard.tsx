"use client";

import { useState } from "react";
import { ApiKeyPanel } from "./ApiKeyPanel";
import { IpWhitelistPanel } from "./IpWhitelistPanel";

type Tab = "apikeys" | "business-ip" | "admin-ip";

const TABS: { id: Tab; label: string }[] = [
  { id: "apikeys", label: "API Key" },
  { id: "business-ip", label: "业务白名单" },
  { id: "admin-ip", label: "管理白名单" },
];

export function AdminDashboard() {
  const [tab, setTab] = useState<Tab>("apikeys");

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 px-4 py-10 sm:px-6">
      <header className="space-y-2">
        <p className="text-xs font-medium uppercase tracking-widest text-zinc-500">
          Mini Gateway
        </p>
        <h1 className="text-2xl font-semibold tracking-tight">管理后台</h1>
        <p className="max-w-xl text-sm text-zinc-500 dark:text-zinc-400">
          各模块采用「列表 + 点击新增切换窗体、保存后局部刷新列表」。接口：{" "}
          <code className="rounded bg-zinc-100 px-1 font-mono text-xs dark:bg-zinc-800">
            /admin/gw/v1
          </code>
          （HMAC）。需 Redis 模式且调用方 IP 在 admin 白名单内。
        </p>
      </header>

      <nav
        className="flex flex-wrap gap-2 border-b border-zinc-200 pb-1 dark:border-zinc-800"
        aria-label="Sections"
      >
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => setTab(t.id)}
            className={`rounded-t-md px-3 py-2 text-sm font-medium transition-colors ${
              tab === t.id
                ? "border-b-2 border-zinc-900 text-zinc-900 dark:border-zinc-100 dark:text-zinc-100"
                : "text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-300"
            }`}
          >
            {t.label}
          </button>
        ))}
      </nav>

      <section>
        {tab === "apikeys" ? <ApiKeyPanel /> : null}
        {tab === "business-ip" ? <IpWhitelistPanel mode="business" /> : null}
        {tab === "admin-ip" ? <IpWhitelistPanel mode="admin" /> : null}
      </section>
    </div>
  );
}
