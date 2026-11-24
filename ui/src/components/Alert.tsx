"use client";

export function Alert({
  tone,
  message,
}: {
  tone: "ok" | "err";
  message: string;
}) {
  const style =
    tone === "ok"
      ? {
          borderColor: "color-mix(in srgb, var(--success) 35%, transparent)",
          background: "var(--success-soft)",
          color: "var(--success)",
        }
      : {
          borderColor: "color-mix(in srgb, var(--danger) 35%, transparent)",
          background: "var(--danger-soft)",
          color: "var(--danger)",
        };

  return (
    <p
      className="rounded-md border px-3 py-2 text-sm"
      style={style}
      role="status"
    >
      {message}
    </p>
  );
}