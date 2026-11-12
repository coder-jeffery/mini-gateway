"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import type { ServiceListResponse, ServiceRecord } from "@/lib/admin-types";
import { Alert } from "./Alert";
import { useLocale } from "./LocaleProvider";

const EMPTY_FORM = {
  name: "",
  path_prefix: "",
  upstream_url: "",
  cors_enabled: false,
  cors_allow_origins: "",
  cors_allow_methods: "GET,POST,OPTIONS",
  cors_allow_headers: "Content-Type,Authorization,X-Api-Key",
  cors_expose_headers: "X-Request-Id",
  cors_max_age: "600",
  cors_allow_credentials: false,
};

function recordToForm(row: ServiceRecord) {
  return {
    name: row.name,
    path_prefix: row.path_prefix,
    upstream_url: row.upstream_url,
    cors_enabled: row.cors_enabled,
    cors_allow_origins: row.cors_allow_origins,
    cors_allow_methods: row.cors_allow_methods,
    cors_allow_headers: row.cors_allow_headers,
    cors_expose_headers: row.cors_expose_headers,
    cors_max_age: String(row.cors_max_age),
    cors_allow_credentials: row.cors_allow_credentials,
  };
}

function formPayload(form: typeof EMPTY_FORM, id?: string) {
  const body: Record<string, string | number> = {
    name: form.name.trim(),
    path_prefix: form.path_prefix.trim(),
    upstream_url: form.upstream_url.trim(),
    cors_enabled: form.cors_enabled ? 1 : 0,
    cors_allow_origins: form.cors_allow_origins.trim(),
    cors_allow_methods: form.cors_allow_methods.trim(),
    cors_allow_headers: form.cors_allow_headers.trim(),
    cors_expose_headers: form.cors_expose_headers.trim(),
    cors_max_age: Number(form.cors_max_age) || 0,
    cors_allow_credentials: form.cors_allow_credentials ? 1 : 0,
  };
  if (id) {
    body.id = id;
  }
  return body;
}

export function ServiceCorsPanel() {
  const { messages: m, f } = useLocale();
  const s = m.service;
  const c = m.common;

  const [rows, setRows] = useState<ServiceRecord[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [mode, setMode] = useState<"list" | "create">("list");
  const [form, setForm] = useState(EMPTY_FORM);
  const [listLoading, setListLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [listStatus, setListStatus] = useState<{
    tone: "ok" | "err";
    msg: string;
  } | null>(null);
  const [formStatus, setFormStatus] = useState<{
    tone: "ok" | "err";
    msg: string;
  } | null>(null);

  const refreshList = useCallback(async (keepId?: string | null) => {
    setListLoading(true);
    setListStatus(null);
    try {
      const res = (await adminAction("service_list")) as ServiceListResponse;
      const list = [...(res.services ?? [])].sort((a, b) =>
        a.path_prefix.localeCompare(b.path_prefix),
      );
      setRows(list);
      const nextId =
        keepId && list.some((item) => item.id === keepId)
          ? keepId
          : list[0]?.id ?? null;
      setSelectedId(nextId);
      if (nextId) {
        const row = list.find((item) => item.id === nextId);
        if (row) {
          setForm(recordToForm(row));
          setMode("list");
        }
      } else {
        setForm(EMPTY_FORM);
        setMode("list");
      }
    } catch (err) {
      setListStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : s.loadFailed,
      });
    } finally {
      setListLoading(false);
    }
  }, [s.loadFailed]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- initial list load
    void refreshList();
  }, [refreshList]);

  function selectService(row: ServiceRecord) {
    setSelectedId(row.id);
    setForm(recordToForm(row));
    setMode("list");
    setFormStatus(null);
  }

  function openCreate() {
    setSelectedId(null);
    setForm(EMPTY_FORM);
    setMode("create");
    setFormStatus(null);
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setFormStatus(null);
    const isCreate = mode === "create";
    try {
      const action = isCreate ? "service_create" : "service_update";
      const payload = formPayload(form, isCreate ? undefined : selectedId ?? undefined);
      const res = await adminAction(action, payload);
      const saved = "service" in res ? res.service : undefined;
      setListStatus({
        tone: "ok",
        msg: res.msg ?? (isCreate ? s.created : s.updated),
      });
      await refreshList(saved?.id ?? selectedId);
    } catch (err) {
      setFormStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : s.saveFailed,
      });
    } finally {
      setSaving(false);
    }
  }

  async function onDelete() {
    if (!selectedId) return;
    const row = rows.find((item) => item.id === selectedId);
    if (!row || !confirm(f(s.deleteConfirm, { name: row.name }))) return;
    setSaving(true);
    setFormStatus(null);
    try {
      await adminAction("service_delete", { id: selectedId });
      setListStatus({ tone: "ok", msg: s.deleted });
      await refreshList(null);
    } catch (err) {
      setFormStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : s.deleteFailed,
      });
    } finally {
      setSaving(false);
    }
  }

  const corsDisabled = !form.cors_enabled;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h2 className="gw-panel-title">{s.title}</h2>
        <p className="gw-panel-desc">{s.desc}</p>
      </div>

      {listStatus ? <Alert tone={listStatus.tone} message={listStatus.msg} /> : null}

      <div className="gw-split">
        <aside className="gw-split-pane flex flex-col gap-4 min-w-0">
          <div className="flex items-center justify-between gap-2">
            <span className="gw-toolbar-label">{s.listTitle}</span>
            <button
              type="button"
              onClick={() => void refreshList(selectedId)}
              disabled={listLoading}
              className="gw-btn-link"
            >
              {c.refresh}
            </button>
          </div>
          <button type="button" onClick={openCreate} className="gw-btn gw-btn-primary w-full">
            {s.createService}
          </button>
          {listLoading && rows.length === 0 ? (
            <p className="text-[0.8125rem] text-[var(--gw-text-secondary)]">{c.loading}</p>
          ) : null}
          {!listLoading && rows.length === 0 ? (
            <p className="text-[0.8125rem] text-[var(--gw-text-secondary)]">{s.empty}</p>
          ) : null}
          <ul className="flex flex-col gap-2 max-h-[min(60vh,28rem)] overflow-y-auto">
            {rows.map((row) => {
              const active = row.id === selectedId && mode === "list";
              return (
                <li key={row.id}>
                  <button
                    type="button"
                    onClick={() => selectService(row)}
                    className={`gw-list-item ${active ? "gw-list-item-active" : ""}`}
                  >
                    <div className="text-[0.8125rem] font-medium">{row.name}</div>
                    <div className="mt-1 font-mono text-[0.6875rem] leading-relaxed text-[var(--gw-text-secondary)] break-all">
                      {row.path_prefix}
                      <span className="text-[var(--gw-text-tertiary)]"> → </span>
                      {row.upstream_url}
                    </div>
                  </button>
                </li>
              );
            })}
          </ul>
        </aside>

        <form onSubmit={onSubmit} className="gw-split-pane flex flex-col gap-5 min-w-0">
          <h3 className="gw-toolbar-label">
            {mode === "create" ? s.createTitle : s.editTitle}
          </h3>
          {formStatus ? <Alert tone={formStatus.tone} message={formStatus.msg} /> : null}

          <fieldset className="gw-fieldset">
            <legend className="gw-legend">{s.routeSection}</legend>
            <label className="gw-label">
              <span>{s.name}</span>
              <input
                required
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                className="gw-input"
              />
            </label>
            <label className="gw-label">
              <span>{s.pathPrefix}</span>
              <input
                required
                value={form.path_prefix}
                onChange={(e) => setForm({ ...form, path_prefix: e.target.value })}
                placeholder="/api/orders"
                className="gw-input gw-input-mono"
              />
            </label>
            <label className="gw-label">
              <span>{s.upstreamUrl}</span>
              <input
                required
                value={form.upstream_url}
                onChange={(e) => setForm({ ...form, upstream_url: e.target.value })}
                placeholder="https://backend.example.com"
                className="gw-input gw-input-mono"
              />
            </label>
          </fieldset>

          <fieldset className="gw-fieldset" disabled={corsDisabled}>
            <legend className="gw-legend flex flex-wrap items-center gap-3">
              <span>{s.corsSection}</span>
              <label className="gw-checkbox-row normal-case tracking-normal font-medium">
                <input
                  type="checkbox"
                  checked={form.cors_enabled}
                  onChange={(e) => setForm({ ...form, cors_enabled: e.target.checked })}
                />
                {s.corsEnable}
              </label>
            </legend>
            <label className="gw-checkbox-row">
              <input
                type="checkbox"
                checked={form.cors_allow_credentials}
                disabled={corsDisabled}
                onChange={(e) =>
                  setForm({ ...form, cors_allow_credentials: e.target.checked })
                }
              />
              {s.corsCredentials}
            </label>
            <label className="gw-label">
              <span>{s.corsOrigins}</span>
              <input
                value={form.cors_allow_origins}
                disabled={corsDisabled}
                onChange={(e) => setForm({ ...form, cors_allow_origins: e.target.value })}
                className="gw-input"
                placeholder={s.originsPlaceholder}
              />
            </label>
            <label className="gw-label">
              <span>{s.corsMethods}</span>
              <input
                value={form.cors_allow_methods}
                disabled={corsDisabled}
                onChange={(e) => setForm({ ...form, cors_allow_methods: e.target.value })}
                className="gw-input"
              />
            </label>
            <label className="gw-label">
              <span>{s.corsAllowHeaders}</span>
              <input
                value={form.cors_allow_headers}
                disabled={corsDisabled}
                onChange={(e) => setForm({ ...form, cors_allow_headers: e.target.value })}
                className="gw-input"
              />
            </label>
            <label className="gw-label">
              <span>{s.corsExposeHeaders}</span>
              <input
                value={form.cors_expose_headers}
                disabled={corsDisabled}
                onChange={(e) => setForm({ ...form, cors_expose_headers: e.target.value })}
                className="gw-input"
              />
            </label>
            <label className="gw-label">
              <span>{s.maxAge}</span>
              <input
                type="number"
                min={0}
                value={form.cors_max_age}
                disabled={corsDisabled}
                onChange={(e) => setForm({ ...form, cors_max_age: e.target.value })}
                className="gw-input"
              />
            </label>
          </fieldset>

          <div className="flex flex-wrap gap-2 pt-1">
            <button
              type="submit"
              disabled={saving || (mode === "list" && !selectedId)}
              className="gw-btn gw-btn-primary"
            >
              {saving ? c.saving : c.save}
            </button>
            {mode === "list" && selectedId ? (
              <button
                type="button"
                onClick={() => void onDelete()}
                disabled={saving}
                className="gw-btn gw-btn-danger"
              >
                {c.delete}
              </button>
            ) : null}
          </div>
        </form>
      </div>
    </div>
  );
}
