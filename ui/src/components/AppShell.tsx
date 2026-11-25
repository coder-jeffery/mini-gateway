"use client";

import type { ReactNode } from "react";

type NavItem = {
  id: string;
  label: string;
  hint: string;
  active: boolean;
  onSelect: () => void;
};

export function AppShell({
  nav,
  storage,
  gatewayError,
  probing,
  pageTitle,
  pageDesc,
  children,
}: {
  nav: NavItem[];
  storage: string | null;
  gatewayError: string | null;
  probing: boolean;
  pageTitle: string;
  pageDesc: string;
  children: ReactNode;
}) {
  const connected = Boolean(storage) && !gatewayError;

  return (
    <div className="ui-shell">
      <aside
        className="flex w-56 shrink-0 flex-col border-r sm:w-60 lg:w-64"
        style={{
          background: "var(--bg-shell)",
          borderColor: "var(--border-subtle)",
        }}
      >
        <div className="px-6 py-8">
          <p
            className="text-xs font-medium tracking-wide"
            style={{ color: "var(--fg-on-shell-muted)" }}
          >
            控制面
          </p>
          <p
            className="mt-1 text-lg font-semibold tracking-tight"
            style={{ color: "var(--fg-on-shell)" }}
          >
            mini-gateway
          </p>
        </div>

        <nav className="flex flex-col gap-0.5 px-3" aria-label="Main">
          {nav.map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={item.onSelect}
              data-active={item.active}
              className="ui-nav-item"
              style={{
                color: item.active
                  ? "var(--accent)"
                  : "var(--fg-on-shell)",
              }}
            >
              <span className="block text-[0.9375rem] font-medium leading-snug">
                {item.label}
              </span>
              <span
                className="mt-0.5 block text-xs leading-snug"
                style={{ color: "var(--fg-on-shell-muted)" }}
              >
                {item.hint}
              </span>
            </button>
          ))}
        </nav>

        <div
          className="mt-auto border-t px-6 py-5 text-xs"
          style={{
            borderColor: "var(--border-subtle)",
            color: "var(--fg-on-shell-muted)",
          }}
        >
          <div className="flex items-center gap-2">
            <span
              className={connected ? "ui-status-dot" : undefined}
              style={
                connected
                  ? undefined
                  : {
                      width: 8,
                      height: 8,
                      borderRadius: "50%",
                      background: "var(--border)",
                    }
              }
              aria-hidden
            />
            <span style={{ color: "var(--fg-secondary)" }}>
              {connected ? "网关已连接" : probing ? "连接中…" : "未连接"}
            </span>
          </div>
          <p
            className="mt-2 font-mono text-[11px]"
            style={{ color: "var(--fg-on-shell-muted)" }}
          >
            POST /admin/gw/v1 · HMAC
          </p>
        </div>
      </aside>

      <div className="flex min-h-screen min-w-0 flex-1 flex-col bg-industrial-grid">
        <header
          className="shrink-0 border-b"
          style={{
            background: "var(--bg-surface)",
            borderColor: "var(--border-subtle)",
          }}
        >
          <div
            className="flex flex-wrap items-start justify-between gap-6"
            style={{
              paddingLeft: "var(--space-page-x)",
              paddingRight: "var(--space-page-x)",
              paddingTop: "var(--space-page-y)",
              paddingBottom: "1.25rem",
            }}
          >
            <div className="min-w-0 flex-1">
              <h1 className="ui-section-title">{pageTitle}</h1>
              <p className="ui-section-desc">{pageDesc}</p>
            </div>
            <div className="flex flex-wrap items-center justify-end gap-2">
              {probing ? <StatusChip tone="muted" label="探测中" /> : null}
              {storage ? (
                <StatusChip tone="neutral" label={`存储 · ${storage}`} />
              ) : null}
              {gatewayError ? (
                <StatusChip tone="warn" label={gatewayError} />
              ) : null}
              {connected ? <StatusChip tone="ok" label="在线" dot /> : null}
            </div>
          </div>
        </header>

        <main
          className="flex-1"
          style={{
            paddingLeft: "var(--space-page-x)",
            paddingRight: "var(--space-page-x)",
            paddingTop: "1.5rem",
            paddingBottom: "var(--space-page-y)",
          }}
        >
          <div className="w-full max-w-5xl">{children}</div>
        </main>
      </div>
    </div>
  );
}

function StatusChip({
  tone,
  label,
  dot,
}: {
  tone: "ok" | "warn" | "muted" | "neutral";
  label: string;
  dot?: boolean;
}) {
  const bg =
    tone === "ok"
      ? "var(--success-soft)"
      : tone === "warn"
        ? "var(--warn-soft)"
        : tone === "neutral"
          ? "var(--bg-muted)"
          : "var(--bg-elevated)";
  const fg =
    tone === "ok"
      ? "var(--success)"
      : tone === "warn"
        ? "var(--warn)"
        : "var(--fg-secondary)";
  return (
    <span
      className="inline-flex max-w-xs items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium"
      style={{ background: bg, color: fg }}
      title={label.length > 24 ? label : undefined}
    >
      {dot ? (
        <span
          className="ui-status-dot h-1.5 w-1.5"
          style={{ background: "var(--success)" }}
        />
      ) : null}
      <span className="truncate">{label}</span>
    </span>
  );
}