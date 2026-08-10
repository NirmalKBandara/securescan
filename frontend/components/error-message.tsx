import type { ReactNode } from "react";

export function ErrorMessage({
  title = "Something went wrong",
  message,
  requestId,
  action,
}: {
  title?: string;
  message: string;
  requestId?: string;
  action?: ReactNode;
}) {
  return (
    <div className="error-message" role="alert">
      <span className="error-icon" aria-hidden="true">!</span>
      <div>
        <h2>{title}</h2>
        <p>{message}</p>
        {requestId && <p className="request-id">Request ID: <code>{requestId}</code></p>}
        {action && <div className="message-action">{action}</div>}
      </div>
    </div>
  );
}
