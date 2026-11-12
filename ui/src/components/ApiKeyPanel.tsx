"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import type { ApiKeyRecord, ApiKeyListResponse } from "@/lib/admin-types";
import { Alert } from "./Alert";
import { useLocale } from "./LocaleProvider";

const PAGE_SIZE = 10;

type PanelMode = "list" | "create" | "edit";

export function ApiKeyPanel() {
  const { messages: m, f } = useLocale();
  const t = m.apiKey;
  const c = m.common;

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
        msg: err instanceof Error ? err.message : t.loadFailed,
      });
    } finally {
      setListLoading(false);
    }
  }, [t.loadFailed]);

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
        msg: res.msg ?? (isCreate ? t.created : t.updated),
      });
      const targetPage = isCreate ? 1 : page;
      await refreshList(targetPage, true);
    } catch (err) {
      setFormStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : t.saveFailed,
      });
    } finally {
      setFormSubmitting(false);
    }
  }

  async function onDelete(key: string) {
    if (!confirm(f(t.deleteConfirm, { key }))) return;
    setListLoading(true);
    setListStatus(null);
    try {
      const res = await adminAction("del_apikey", { api_key: key });
      if (mode === "edit" && editingKey === key) {
        closeForm();
      }
      setListStatus({ tone: "ok", msg: res.msg ?? t.deleted });
      const nextPage = rows.length === 1 && page > 1 ? page - 1 : page;
      await refreshList(nextPage, true);
    } catch (err) {
      setListStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : t.deleteFailed,
      });
      setListLoading(false);
    }
  }

  const showingForm = mode === "create" || mode === "edit";

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h2 className="gw-panel-title">{t.title}</h2>
        <p className="gw-panel-desc">{t.desc}</p>
      </div>

      <div className="gw-card">
        <div className="gw-card-toolbar">
          <span className="gw-toolbar-label">
            {showingForm
              ? mode === "create"
                ? t.createTitle
                : t.editTitle
              : f(c.totalCount, { count: total })}
          </span>
          <div className="gw-toolbar-actions">
            {showingForm ? (
              <button
                type="button"
                disabled={formSubmitting}
                onClick={closeForm}
                className="gw-btn gw-btn-secondary"
              >
                {c.backToList}
              </button>
            ) : (
              <>
                <button
                  type="button"
                  disabled={listLoading}
                  onClick={openCreate}
                  className="gw-btn gw-btn-primary"
                >
                  {c.add}
                </button>
                <button
                  type="button"
                  disabled={listLoading}
                  onClick={() => void refreshList(page)}
                  className="gw-btn gw-btn-secondary"
                >
                  {c.refresh}
                </button>
              </>
            )}
          </div>
        </div>

        {listStatus && !showingForm ? (
          <div className="gw-alert-bar">
            <Alert tone={listStatus.tone} message={listStatus.msg} />
          </div>
        ) : null}

        {showingForm ? (
          <form onSubmit={onSubmit} className="gw-form min-h-[320px]">
            {formStatus ? <Alert tone={formStatus.tone} message={formStatus.msg} /> : null}

            <div className="grid flex-1 gap-4 content-start">
              <label className="gw-label">
                <span>{t.labelKey}</span>
                <input
                  required
                  autoFocus
                  readOnly={mode === "edit"}
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  className="gw-input gw-input-mono read-only:opacity-60"
                  placeholder="abc123"
                />
              </label>
              <div className="grid gap-4 sm:grid-cols-2">
                <label className="gw-label">
                  <span>{t.labelLimit}</span>
                  <input
                    required
                    type="number"
                    min={1}
                    value={limit}
                    onChange={(e) => setLimit(e.target.value)}
                    className="gw-input"
                  />
                </label>
                <label className="gw-label">
                  <span>{t.labelWindow}</span>
                  <input
                    required
                    type="number"
                    min={1}
                    value={windowSec}
                    onChange={(e) => setWindowSec(e.target.value)}
                    className="gw-input"
                  />
                </label>
              </div>
            </div>

            <div className="gw-form-footer">
              <button
                type="button"
                disabled={formSubmitting}
                onClick={closeForm}
                className="gw-btn gw-btn-secondary"
              >
                {c.cancel}
              </button>
              <button
                type="submit"
                disabled={formSubmitting}
                className="gw-btn gw-btn-primary"
              >
                {formSubmitting ? c.saving : c.save}
              </button>
            </div>
          </form>
        ) : (
          <>
            <div className="gw-table-wrap">
              {listLoading ? (
                <div className="gw-overlay gw-empty">
                  <span>{c.listUpdating}</span>
                </div>
              ) : null}
              <table className="gw-table">
                <thead>
                  <tr>
                    <th>{t.labelKey}</th>
                    <th>{t.labelLimit}</th>
                    <th>{t.labelWindow}</th>
                    <th className="w-36">{c.actions}</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.length === 0 ? (
                    <tr>
                      <td colSpan={4} className="gw-empty">
                        {listLoading ? c.loading : t.empty}
                      </td>
                    </tr>
                  ) : (
                    rows.map((row) => (
                      <tr key={row.api_key}>
                        <td className="font-mono text-[0.8125rem]">{row.api_key}</td>
                        <td>{row.limit}</td>
                        <td>{row.window}s</td>
                        <td>
                          <div className="flex gap-4">
                            <button
                              type="button"
                              disabled={listLoading}
                              onClick={() => openEdit(row)}
                              className="gw-btn-link"
                            >
                              {c.edit}
                            </button>
                            <button
                              type="button"
                              disabled={listLoading}
                              onClick={() => void onDelete(row.api_key)}
                              className="gw-btn-link gw-btn-link-danger"
                            >
                              {c.delete}
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
              <div className="gw-pagination">
                <span>{f(c.pageOf, { page, total: totalPages })}</span>
                <div className="gw-toolbar-actions">
                  <button
                    type="button"
                    disabled={listLoading || page <= 1}
                    onClick={() => void refreshList(page - 1)}
                    className="gw-btn gw-btn-secondary"
                  >
                    {c.prevPage}
                  </button>
                  <button
                    type="button"
                    disabled={listLoading || page >= totalPages}
                    onClick={() => void refreshList(page + 1)}
                    className="gw-btn gw-btn-secondary"
                  >
                    {c.nextPage}
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
