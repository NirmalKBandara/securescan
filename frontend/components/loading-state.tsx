export function LoadingState({ label = "Loading scan data" }: { label?: string }) {
  return (
    <div className="card loading-state" role="status" aria-live="polite">
      <span className="loading-spinner" aria-hidden="true" />
      <div>
        <strong>{label}</strong>
        <span>Please wait a moment.</span>
      </div>
    </div>
  );
}
