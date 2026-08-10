export interface ScanFormValues {
  target: string;
  startPort: number;
  endPort: number;
  authorized: boolean;
}

const defaults: ScanFormValues = { target: "", startPort: 1, endPort: 100, authorized: false };

export function ScanForm({ values = defaults, disabled = false }: { values?: ScanFormValues; disabled?: boolean }) {
  return (
    <form className="card form-card" aria-labelledby="scan-form-title">
      <fieldset disabled={disabled}>
        <legend id="scan-form-title">Scan details</legend>
        <div className="field">
          <label htmlFor="target">Target hostname or IP address</label>
          <input id="target" name="target" type="text" autoComplete="off" defaultValue={values.target} placeholder="scanme.example.com" aria-describedby="target-help" required />
          <small id="target-help">Only public targets on the configured allowlist are accepted.</small>
        </div>
        <div className="port-grid">
          <div className="field"><label htmlFor="start-port">Start port</label><input id="start-port" name="startPort" type="number" min="1" max="65535" defaultValue={values.startPort} required /></div>
          <div className="field"><label htmlFor="end-port">End port</label><input id="end-port" name="endPort" type="number" min="1" max="65535" defaultValue={values.endPort} required /></div>
        </div>
        <label className="checkbox"><input name="authorized" type="checkbox" defaultChecked={values.authorized} required /><span>I confirm that I own this target or have explicit permission to scan it.</span></label>
        <button className="button primary" type="submit">Submit scan</button>
      </fieldset>
      {disabled && <p className="notice" role="note">Preview only — API submission will be connected on Day 18.</p>}
    </form>
  );
}
