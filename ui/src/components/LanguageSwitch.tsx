"use client";

import { useLocale } from "./LocaleProvider";

export function LanguageSwitch() {
  const { locale, setLocale, messages: m } = useLocale();

  return (
    <div
      className="flex items-center gap-1 rounded-[var(--gw-radius)] border border-[var(--gw-border)] bg-[var(--gw-surface)] p-0.5 shadow-[var(--gw-shadow-sm)]"
      role="group"
      aria-label={m.common.language}
    >
      <button
        type="button"
        onClick={() => setLocale("zh")}
        className={`gw-btn !px-2.5 !py-1 !text-xs !font-medium ${
          locale === "zh"
            ? "!bg-[var(--gw-surface-muted)] !text-[var(--gw-text)] shadow-[var(--gw-shadow-sm)]"
            : "!bg-transparent !text-[var(--gw-text-secondary)] hover:!text-[var(--gw-text)]"
        }`}
      >
        {m.common.langZh}
      </button>
      <button
        type="button"
        onClick={() => setLocale("en")}
        className={`gw-btn !px-2.5 !py-1 !text-xs !font-medium ${
          locale === "en"
            ? "!bg-[var(--gw-surface-muted)] !text-[var(--gw-text)] shadow-[var(--gw-shadow-sm)]"
            : "!bg-transparent !text-[var(--gw-text-secondary)] hover:!text-[var(--gw-text)]"
        }`}
      >
        {m.common.langEn}
      </button>
    </div>
  );
}
