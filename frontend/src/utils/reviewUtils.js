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

export function getWorkerReviewSummary(worker) {
  const reviews = worker?.receivedReviews || [];
  const ratedReviews = reviews.filter((review) => review.rating != null);
  const total = ratedReviews.reduce((sum, review) => sum + Number(review.rating || 0), 0);
  return { reviews, averageRating: ratedReviews.length ? total / ratedReviews.length : null, ratingCount: ratedReviews.length };
}

export function getHouseholdReviewSummary(household) {
  return { reviews: household?.receivedFeedback || [] };
}
