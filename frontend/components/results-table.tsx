import type { PortResult } from "@/lib/api/types";

export function ResultsTable({ results }: { results: PortResult[] }) {
  if (results.length === 0) {
    return (
      <section className="card empty-state results-empty" aria-labelledby="results-empty-title">
        <span className="radar" aria-hidden="true">✓</span>
        <h2 id="results-empty-title">No port findings</h2>
        <p>The scan completed without returning any port results.</p>
      </section>
    );
  }

  return (
    <section className="card results-card" aria-labelledby="results-title">
      <div className="section-heading">
        <div><p className="eyebrow">Findings</p><h2 id="results-title">Port results</h2></div>
        <span className="result-count">{results.length} {results.length === 1 ? "result" : "results"}</span>
      </div>
      <div className="table-scroll" tabIndex={0} aria-label="Scrollable port results">
        <table>
          <caption className="sr-only">Network ports returned by the authorized scan</caption>
          <thead><tr><th scope="col">Address</th><th scope="col">Port</th><th scope="col">State</th></tr></thead>
          <tbody>{results.map((result) => (
            <tr key={`${result.address}-${result.port}`}>
              <td data-label="Address"><code>{result.address}</code></td>
              <td data-label="Port">{result.port}</td>
              <td data-label="State"><span className={`port-state port-${result.state}`}>{result.state}</span></td>
            </tr>
          ))}</tbody>
        </table>
      </div>
    </section>
  );
}
