"use client";

import { useMemo, useState } from "react";
import { ApiKeyPanel } from "./ApiKeyPanel";
import { IpWhitelistPanel } from "./IpWhitelistPanel";
import { LanguageSwitch } from "./LanguageSwitch";
import { useLocale } from "./LocaleProvider";
import { ServiceCorsPanel } from "./ServiceCorsPanel";

type Tab = "apikeys" | "business-ip" | "admin-ip" | "services";

export function AdminDashboard() {
  const { messages: m } = useLocale();
  const [tab, setTab] = useState<Tab>("apikeys");

  const tabs: { id: Tab; label: string }[] = useMemo(
    () => [
      { id: "apikeys", label: m.dashboard.tabApiKeys },
      { id: "services", label: m.dashboard.tabServices },
      { id: "business-ip", label: m.dashboard.tabBusinessIp },
      { id: "admin-ip", label: m.dashboard.tabAdminIp },
    ],
    [m],
  );

  return (
    <div className="gw-shell">
      <header className="flex flex-col gap-3">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex min-w-0 flex-col gap-3">
            <p className="gw-eyebrow">{m.dashboard.eyebrow}</p>
            <h1 className="gw-page-title">{m.dashboard.title}</h1>
          </div>
          <LanguageSwitch />
        </div>
        <p className="gw-lead">
          {m.dashboard.leadBefore}{" "}
          <code className="gw-code">/admin/gw/v1</code> {m.dashboard.leadAfter}
        </p>
      </header>

      <nav className="gw-tabs" aria-label={m.dashboard.navAria}>
        {tabs.map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => setTab(t.id)}
            className={`gw-tab ${tab === t.id ? "gw-tab-active" : ""}`}
          >
            {t.label}
          </button>
        ))}
      </nav>

      <section className="min-w-0">
        {tab === "apikeys" ? <ApiKeyPanel /> : null}
        {tab === "business-ip" ? <IpWhitelistPanel mode="business" /> : null}
        {tab === "admin-ip" ? <IpWhitelistPanel mode="admin" /> : null}
        {tab === "services" ? <ServiceCorsPanel /> : null}
      </section>
    </div>
  );
}
