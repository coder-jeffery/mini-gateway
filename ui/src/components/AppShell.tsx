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
        className="flex w-[13.5rem] shrink-0 flex-col border-r"
        style={{
          background: "var(--bg-shell)",
          borderColor: "color-mix(in srgb, var(--border) 30%, transparent)",
        }}
      >
        <div
          className="border-b px-4 py-4"
          style={{ borderColor: "rgb(255 255 255 / 0.08)" }}
        >
          <div className="flex items-center gap-2.5">
            <span
              className="flex h-9 w-9 shrink-0 items-center justify-center text-xs font-bold tracking-tighter"
              style={{
                borderRadius: "var(--radius)",
                border: "1px solid color-mix(in srgb, var(--accent-bright) 50%, transparent)",
                background: "var(--bg-shell-elevated)",
                color: "var(--accent-bright)",
                fontFamily: "var(--font-geist-mono), monospace",
              }}
            >
              GW
            </span>
            <div className="min-w-0">
              <p
                className="text-[10px] font-semibold uppercase tracking-[0.22em]"
                style={{ color: "var(--fg-on-shell-muted)" }}
              >
                Control
              </p>
              <p
                className="truncate text-sm font-semibold"
                style={{ color: "var(--fg-on-shell)" }}
              >
                mini-gateway
              </p>
            </div>
          </div>
        </div>

        <nav className="flex flex-col gap-0.5 p-2" aria-label="Main">
          {nav.map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={item.onSelect}
              data-active={item.active}
              className="ui-nav-item"
              style={{
                color: item.active
                  ? "var(--fg-on-shell)"
                  : "var(--fg-on-shell-muted)",
              }}
            >
              <span className="block text-sm font-semibold leading-tight">
                {item.label}
              </span>
              <span
                className="mt-1 block font-mono text-[10px] leading-snug opacity-85"
                style={{ fontFamily: "var(--font-geist-mono), monospace" }}
              >
                {item.hint}
              </span>
            </button>
          ))}
        </nav>

        <div
          className="mt-auto border-t p-3 text-[10px]"
          style={{
            borderColor: "rgb(255 255 255 / 0.08)",
            color: "var(--fg-on-shell-muted)",
          }}
        >
          <div className="flex items-center gap-2">
            <span
              className={connected ? "ui-status-led" : ""}
              style={
                connected
                  ? undefined
                  : {
                      width: 7,
                      height: 7,
                      borderRadius: "50%",
                      background: "var(--fg-on-shell-muted)",
                    }
              }
              aria-hidden
            />
            <span className="font-mono" style={{ color: "var(--fg-on-shell)" }}>
              POST /admin/gw/v1
            </span>
          </div>
          <p className="mt-1.5 pl-[15px] font-mono uppercase tracking-wider opacity-80">
            HMAC · v1
          </p>
        </div>
      </aside>

      <div className="flex min-h-screen min-w-0 flex-1 flex-col bg-industrial-grid">
        <header
          className="shrink-0 border-b"
          style={{
            background: "var(--bg-surface)",
            borderColor: "var(--border)",
          }}
        >
          <div className="flex flex-wrap items-start justify-between gap-4 px-5 py-4 sm:px-6">
            <div className="min-w-0 flex-1">
              <p
                className="text-[10px] font-semibold uppercase tracking-[0.2em]"
                style={{ color: "var(--fg-muted)" }}
              >
                网关管理控制台
              </p>
              <h1 className="ui-section-title mt-1">{pageTitle}</h1>
              <p className="ui-section-desc">{pageDesc}</p>
            </div>
            <div className="flex flex-wrap items-center justify-end gap-2 pt-0.5">
              {probing ? <StatusPill tone="muted" label="探测网关…" /> : null}
              {storage ? (
                <StatusPill tone="ok" label={`STORE · ${storage.toUpperCase()}`} />
              ) : null}
              {gatewayError ? (
                <StatusPill tone="warn" label={gatewayError} />
              ) : null}
              {connected ? (
                <StatusPill tone="ok" label="LINK UP" dot />
              ) : null}
            </div>
          </div>
        </header>

        <main className="flex-1 px-4 py-5 sm:px-6 sm:py-6 lg:px-8">
          <div className="w-full max-w-4xl">{children}</div>
        </main>
      </div>
    </div>
  );
}

function StatusPill({
  tone,
  label,
  dot,
}: {
  tone: "ok" | "warn" | "muted";
  label: string;
  dot?: boolean;
}) {
  const bg =
    tone === "ok"
      ? "var(--success-soft)"
      : tone === "warn"
        ? "var(--warn-soft)"
        : "var(--bg-muted)";
  const fg =
    tone === "ok"
      ? "var(--success)"
      : tone === "warn"
        ? "var(--warn)"
        : "var(--fg-muted)";
  return (
    <span
      className="inline-flex items-center gap-1.5 border px-2 py-1 font-mono text-[10px] font-semibold uppercase tracking-wide"
      style={{
        background: bg,
        color: fg,
        borderColor: "color-mix(in srgb, currentColor 25%, transparent)",
        borderRadius: "var(--radius)",
      }}
    >
      {dot ? (
        <span
          className="h-1.5 w-1.5 shrink-0 rounded-full"
          style={{ background: "var(--success)" }}
        />
      ) : null}
      {label}
    </span>
  );
}