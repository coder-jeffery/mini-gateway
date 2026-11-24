"use client";

import { useEffect, useState } from "react";
import { ApiKeyPanel } from "./ApiKeyPanel";
import { IpWhitelistPanel } from "./IpWhitelistPanel";
import { GovernancePanel } from "./GovernancePanel";
import { AppShell } from "./AppShell";
import type { GatewayStorageBackend } from "@/lib/admin-types";

type Tab = "apikeys" | "business-ip" | "admin-ip" | "governance";

const TAB_META: Record<
  Tab,
  { label: string; hint: string; pageTitle: string; pageDesc: string }
> = {
  apikeys: {
    label: "凭证",
    hint: "API Key · 配额",
    pageTitle: "API Key",
    pageDesc: "数据面凭证与速率配额。新增或编辑在列表面板内完成，变更经 HMAC 写入 store。",
  },
  "business-ip": {
    label: "业务网",
    hint: "数据面 IP 放行",
    pageTitle: "业务 IP 白名单",
    pageDesc: "access 阶段 whitelist:ip。仅允许列表中的来源访问数据面。",
  },
  "admin-ip": {
    label: "管理网",
    hint: "HMAC 调用源",
    pageTitle: "管理 IP 白名单",
    pageDesc: "admin_api_v1 校验的 admin:whitelist:ip。控制面调用必须来自已登记地址。",
  },
  governance: {
    label: "治理",
    hint: "审计 · RBAC · 策略",
    pageTitle: "治理与策略",
    pageDesc: "审计事件、RBAC 角色、URI 封禁与路由配额。",
  },
};

const STORAGE_LABEL: Record<GatewayStorageBackend, string> = {
  memory: "memory",
  redis: "redis",
  sqlite: "sqlite",
};

export function AdminDashboard() {
  const [tab, setTab] = useState<Tab>("apikeys");
  const [storage, setStorage] = useState<GatewayStorageBackend | null>(null);
  const [gatewayError, setGatewayError] = useState<string | null>(null);
  const [probing, setProbing] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setProbing(true);
      try {
        const res = await fetch("/api/admin", { cache: "no-store" });
        const data = (await res.json()) as {
          ok: boolean;
          storage?: GatewayStorageBackend;
          msg?: string;
        };
        if (cancelled) return;
        if (data.ok && data.storage) {
          setStorage(data.storage);
          setGatewayError(null);
        } else {
          setGatewayError(data.msg ?? "无法连接网关");
        }
      } catch (e) {
        if (!cancelled) {
          setGatewayError(e instanceof Error ? e.message : "无法连接网关");
        }
      } finally {
        if (!cancelled) setProbing(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const nav = (Object.keys(TAB_META) as Tab[]).map((id) => ({
    id,
    label: TAB_META[id].label,
    hint: TAB_META[id].hint,
    active: tab === id,
    onSelect: () => setTab(id),
  }));

  const meta = TAB_META[tab];

  return (
    <AppShell
      nav={nav}
      storage={storage ? STORAGE_LABEL[storage] ?? storage : null}
      gatewayError={gatewayError}
      probing={probing}
      pageTitle={meta.pageTitle}
      pageDesc={meta.pageDesc}
    >
      {tab === "apikeys" ? <ApiKeyPanel /> : null}
      {tab === "business-ip" ? <IpWhitelistPanel mode="business" /> : null}
      {tab === "admin-ip" ? <IpWhitelistPanel mode="admin" /> : null}
      {tab === "governance" ? <GovernancePanel /> : null}
    </AppShell>
  );
}