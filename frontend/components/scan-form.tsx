"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { ErrorMessage } from "@/components/error-message";
import { scansApi, SecureScanApiError } from "@/lib/api/client";
import { scanFormSchema, type ScanFormValues } from "@/lib/validation/scan";

interface SubmissionError {
  message: string;
  requestId?: string;
}

const defaults: ScanFormValues = {
  target: "",
  startPort: 1,
  endPort: 100,
  authorized: false,
};

export function ScanForm({
  values = defaults,
  disabled = false,
}: {
  values?: ScanFormValues;
  disabled?: boolean;
}) {
  const router = useRouter();
  const [submissionError, setSubmissionError] = useState<SubmissionError>();
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ScanFormValues>({
    resolver: zodResolver(scanFormSchema),
    defaultValues: values,
    mode: "onBlur",
  });

  async function submit(values: ScanFormValues) {
    setSubmissionError(undefined);
    try {
      const scan = await scansApi.create(values);
      router.push(`/scans/${encodeURIComponent(scan.id)}`);
    } catch (error) {
      if (error instanceof SecureScanApiError) {
        setSubmissionError({ message: error.message, requestId: error.requestId });
        return;
      }
      setSubmissionError({
        message: "The scan could not be submitted. Check your connection and try again.",
      });
    }
  }

  const unavailable = disabled || isSubmitting;

  return (
    <form
      className="card form-card"
      aria-labelledby="scan-form-title"
      noValidate
      onChange={() => setSubmissionError(undefined)}
      onSubmit={handleSubmit(submit)}
    >
      <fieldset disabled={unavailable} aria-busy={isSubmitting}>
        <legend id="scan-form-title">Scan details</legend>
        <div className="field">
          <label htmlFor="target">Target hostname or IP address</label>
          <input
            id="target"
            type="text"
            autoComplete="off"
            autoCapitalize="none"
            spellCheck={false}
            placeholder="scanme.example.com"
            aria-describedby={`target-help${errors.target ? " target-error" : ""}`}
            aria-invalid={Boolean(errors.target)}
            {...register("target")}
          />
          <small id="target-help">Only public targets on the configured allowlist are accepted.</small>
          {errors.target && <p className="field-error" id="target-error">{errors.target.message}</p>}
        </div>
        <div className="port-grid">
          <div className="field">
            <label htmlFor="start-port">Start port</label>
            <input
              id="start-port"
              type="number"
              inputMode="numeric"
              min="1"
              max="65535"
              aria-describedby={errors.startPort ? "start-port-error" : undefined}
              aria-invalid={Boolean(errors.startPort)}
              {...register("startPort", { valueAsNumber: true })}
            />
            {errors.startPort && <p className="field-error" id="start-port-error">{errors.startPort.message}</p>}
          </div>
          <div className="field">
            <label htmlFor="end-port">End port</label>
            <input
              id="end-port"
              type="number"
              inputMode="numeric"
              min="1"
              max="65535"
              aria-describedby={errors.endPort ? "end-port-error" : undefined}
              aria-invalid={Boolean(errors.endPort)}
              {...register("endPort", { valueAsNumber: true })}
            />
            {errors.endPort && <p className="field-error" id="end-port-error">{errors.endPort.message}</p>}
          </div>
        </div>
        <label className="checkbox" htmlFor="authorized">
          <input
            id="authorized"
            type="checkbox"
            aria-describedby={errors.authorized ? "authorized-error" : undefined}
            aria-invalid={Boolean(errors.authorized)}
            {...register("authorized")}
          />
          <span>I confirm that I own this target or have explicit permission to scan it.</span>
        </label>
        {errors.authorized && <p className="field-error" id="authorized-error">{errors.authorized.message}</p>}
        <button className="button primary" type="submit" disabled={unavailable}>
          {isSubmitting ? "Submitting scan…" : "Submit scan"}
        </button>
      </fieldset>
      {disabled && <p className="notice" role="note">Preview only — submission is disabled on this component preview.</p>}
      {submissionError && (
        <div className="form-error">
          <ErrorMessage
            title="Scan submission failed"
            message={submissionError.message}
            requestId={submissionError.requestId}
          />
        </div>
      )}
    </form>
  );
}
