import React from "react";

/**
 * Tells an admin that a verification request touches a permanently blocked
 * account (AGENTS.md II.D): its ID number belongs to one (the request was
 * rejected on arrival), or the applicant has a banned account's full name
 * (a warning only; two people can share a name). Renders nothing for a
 * clean request or for the applicant's own copy, which carries no banCheck.
 */
export default function VerificationBanFlag({ request, compact = false }) {
  const check = request?.banCheck;
  if (!check || (!check.idNumberMatch && !check.nameMatch)) {
    return null;
  }
  if (check.idNumberMatch) {
    return (
      <div className="verification-ban-flag is-danger" role="note">
        <span>
          <strong>ID number matches banned account @{check.idNumberMatch}.</strong>
          {compact ? "" : " The request was rejected automatically and the applicant was only told the ID couldn't be verified."}
        </span>
      </div>
    );
  }
  return (
    <div className="verification-ban-flag is-warning" role="note">
      <span>
        <strong>Same full name as banned account @{check.nameMatch}.</strong>
        {compact ? "" : " Compare the ID photos before you approve."}
      </span>
    </div>
  );
}
