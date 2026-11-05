"use client";

export function Alert({
  tone,
  message,
}: {
  tone: "ok" | "err";
  message: string;
}) {
  const styles =
    tone === "ok"
      ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-900 dark:text-emerald-100"
      : "border-red-500/40 bg-red-500/10 text-red-900 dark:text-red-100";

  return (
    <p
      className={`rounded-lg border px-3 py-2 text-sm ${styles}`}
      role="status"
    >
      {message}
    </p>
  );
}
