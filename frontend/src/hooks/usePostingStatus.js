import { useEffect, useState } from "react";

import { fetchPostingStatus } from "../services/backendDataService";

/**
 * Whether the signed-in household can post a job now (2026-11-02): a hired
 * job past its last day has to be marked done, and a finished job's workers
 * rated, first. Read from the backend each time the Post a Job screen opens,
 * so a rating given elsewhere shows up on the way back.
 */
export function usePostingStatus(active) {
  const [status, setStatus] = useState(null);

  useEffect(() => {
    if (!active) {
      setStatus(null);
      return undefined;
    }
    let cancelled = false;
    fetchPostingStatus()
      .then((data) => {
        if (!cancelled) setStatus(data);
      })
      .catch(() => {
        // The backend still refuses the post with the same message.
        if (!cancelled) setStatus(null);
      });
    return () => {
      cancelled = true;
    };
  }, [active]);

  return status;
}
