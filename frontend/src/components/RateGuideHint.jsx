import React, { useEffect, useState } from "react";
import { fetchRateGuide } from "../services/backendDataService";

const RATE_TYPE_KEYS = { "Per Hour": "per_hour", "Fixed Rate": "fixed" };

/**
 * What households usually offer for the chosen service, worded by the
 * backend (jobs/rate-guide/), under the Offered Rate field so a new post
 * starts from a fair figure (spec II.B price transparency).
 */
export default function RateGuideHint({ skill, rateType }) {
  const [label, setLabel] = useState("");

  useEffect(() => {
    const service = (skill || "").trim();
    if (!service || service === "Other") {
      setLabel("");
      return undefined;
    }
    let cancelled = false;
    fetchRateGuide(service, RATE_TYPE_KEYS[rateType] || "per_day")
      .then((guide) => {
        if (!cancelled) setLabel(guide?.label || "");
      })
      .catch(() => {
        if (!cancelled) setLabel("");
      });
    return () => {
      cancelled = true;
    };
  }, [skill, rateType]);

  return label ? <div className="form-text rate-guide-hint">{label}</div> : null;
}
