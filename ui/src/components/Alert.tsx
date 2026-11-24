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
          background: "var(--success-soft)",
          color: "var(--success)",
        }
      : {
          background: "var(--danger-soft)",
          color: "var(--danger)",
        };

  return (
    <p
      className="rounded-md px-3.5 py-2.5 text-sm font-medium"
      style={style}
      role="status"
    >
      {message}
    </p>
  );
}