const REVIEW_METRIC_FIELDS = ["quality_of_work", "punctuality", "communication", "professionalism"];

/** The average of the rated metrics on a review form, to one decimal place,
 * or null when none is rated. AGENTS.md II.A: with metrics, the overall
 * rating is their average (the backend stores it that way too). */
export function getReviewMetricAverage(form) {
  const values = REVIEW_METRIC_FIELDS.map((field) => Number(form?.[field])).filter((value) => value >= 1 && value <= 5);
  if (values.length === 0) {
    return null;
  }
  return Math.round((values.reduce((sum, value) => sum + value, 0) / values.length) * 10) / 10;
}

/**
 * The average of ratings to one decimal place, halves rounding up -- the
 * backend's round_rating, so a page's summary matches the profile figure.
 * Each rating has one decimal already; summing them as whole tenths keeps
 * 4.35 from rounding down as the float 4.3499... (mobile worker audit,
 * 2026-11-23). Null without ratings.
 */
export function averageRating(values) {
  const tenths = values
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value))
    .map((value) => Math.round(value * 10));
  if (tenths.length === 0) {
    return null;
  }
  const total = tenths.reduce((sum, value) => sum + value, 0);
  return Math.floor((2 * total + tenths.length) / (2 * tenths.length)) / 10;
}

export function getWorkerReviewSummary(worker) {
  const reviews = worker?.receivedReviews || [];
  const ratedReviews = reviews.filter((review) => review.rating != null);
  return {
    reviews,
    averageRating: averageRating(ratedReviews.map((review) => review.rating)),
    ratingCount: ratedReviews.length,
  };
}

export function getHouseholdReviewSummary(household) {
  return { reviews: household?.receivedFeedback || [] };
}
