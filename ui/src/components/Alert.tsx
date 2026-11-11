"use client";

export function Alert({
  tone,
  message,
}: {
  tone: "ok" | "err";
  message: string;
}) {
  return (
    <p
      role="status"
      className={`gw-alert ${tone === "ok" ? "gw-alert-ok" : "gw-alert-err"}`}
    >
      {message}
    </p>
  );
}
