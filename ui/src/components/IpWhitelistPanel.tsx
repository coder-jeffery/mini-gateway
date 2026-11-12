"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { adminAction } from "@/lib/admin-browser";
import { Alert } from "./Alert";
import { useLocale } from "./LocaleProvider";

type Mode = "business" | "admin";
type PanelMode = "list" | "create";

export function IpWhitelistPanel({ mode }: { mode: Mode }) {
  const { messages: m, f } = useLocale();
  const w = m.whitelist;
  const c = m.common;

  const cfg = useMemo(() => {
    if (mode === "business") {
      return {
        title: w.businessTitle,
        description: w.businessDesc,
        listAction: "whitelist_list" as const,
        addAction: "whitelist_add" as const,
        delAction: "whitelist_del" as const,
        listKey: "whitelist" as const,
        addLabel: w.addIp,
      };
    }
    return {
      title: w.adminTitle,
      description: w.adminDesc,
      listAction: "admin_whitelist_list" as const,
      addAction: "admin_whitelist_add" as const,
      delAction: "admin_whitelist_del" as const,
      listKey: "admin_whitelist" as const,
      addLabel: w.addIp,
    };
  }, [mode, w]);

  const [ips, setIps] = useState<string[]>([]);
  const [panelMode, setPanelMode] = useState<PanelMode>("list");
  const [newIp, setNewIp] = useState("");

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

  const refreshList = useCallback(
    async (silent = false) => {
      setListLoading(true);
      if (!silent) {
        setListStatus(null);
      }
      try {
        const res = await adminAction(cfg.listAction);
        const list =
          cfg.listKey === "whitelist"
            ? "whitelist" in res
              ? (res.whitelist ?? [])
              : []
            : "admin_whitelist" in res
              ? (res.admin_whitelist ?? [])
              : [];
        setIps([...list].sort());
      } catch (err) {
        setListStatus({
          tone: "err",
          msg: err instanceof Error ? err.message : w.loadFailed,
        });
      } finally {
        setListLoading(false);
      }
    },
    [cfg.listAction, cfg.listKey, w.loadFailed],
  );

  useEffect(() => {
    void refreshList();
  }, [refreshList]);

  function closeForm() {
    setPanelMode("list");
    setNewIp("");
    setFormStatus(null);
  }

  function openCreate() {
    setNewIp("");
    setFormStatus(null);
    setPanelMode("create");
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const ip = newIp.trim();
    if (!ip) return;
    setFormSubmitting(true);
    setFormStatus(null);
    try {
      const res = await adminAction(cfg.addAction, { ip });
      closeForm();
      setListStatus({ tone: "ok", msg: res.msg ?? w.added });
      await refreshList(true);
    } catch (err) {
      setFormStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : w.addFailed,
      });
    } finally {
      setFormSubmitting(false);
    }
  }

  async function onRemove(ip: string) {
    if (!confirm(f(w.removeConfirm, { ip }))) return;
    setListLoading(true);
    setListStatus(null);
    try {
      const res = await adminAction(cfg.delAction, { ip });
      setListStatus({ tone: "ok", msg: res.msg ?? w.removed });
      await refreshList(true);
    } catch (err) {
      setListStatus({
        tone: "err",
        msg: err instanceof Error ? err.message : w.removeFailed,
      });
      setListLoading(false);
    }
  }

  const showingForm = panelMode === "create";

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h2 className="gw-panel-title">{cfg.title}</h2>
        <p className="gw-panel-desc">{cfg.description}</p>
      </div>

      <div className="gw-card">
        <div className="gw-card-toolbar">
          <span className="gw-toolbar-label">
            {showingForm ? cfg.addLabel : f(c.totalCount, { count: ips.length })}
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
                  {cfg.addLabel}
                </button>
                <button
                  type="button"
                  disabled={listLoading}
                  onClick={() => void refreshList()}
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
          <form onSubmit={onSubmit} className="gw-form min-h-[220px]">
            {formStatus ? <Alert tone={formStatus.tone} message={formStatus.msg} /> : null}

            <label className="gw-label max-w-md">
              <span>{w.ipAddress}</span>
              <input
                required
                autoFocus
                value={newIp}
                onChange={(e) => setNewIp(e.target.value)}
                placeholder="127.0.0.1"
                className="gw-input gw-input-mono"
              />
            </label>

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
          <div className="gw-table-wrap">
            {listLoading ? (
              <div className="gw-overlay min-h-[120px]">
                <span>{c.listUpdating}</span>
              </div>
            ) : null}
            <table className="gw-table">
              <thead>
                <tr>
                  <th>IP</th>
                  <th className="w-28">{c.actions}</th>
                </tr>
              </thead>
              <tbody>
                {ips.length === 0 ? (
                  <tr>
                    <td colSpan={2} className="gw-empty">
                      {listLoading
                        ? c.loading
                        : f(w.empty, { action: cfg.addLabel })}
                    </td>
                  </tr>
                ) : (
                  ips.map((ip) => (
                    <tr key={ip}>
                      <td className="font-mono text-[0.8125rem]">{ip}</td>
                      <td>
                        <button
                          type="button"
                          disabled={listLoading}
                          onClick={() => void onRemove(ip)}
                          className="gw-btn-link gw-btn-link-danger"
                        >
                          {c.remove}
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
