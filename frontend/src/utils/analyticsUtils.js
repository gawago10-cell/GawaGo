import { ANALYTICS_SERVICE_CATEGORIES, BARANGAYS } from "../constants/appConstants";
import { getBarangayCenter, normalizeBarangayName } from "./locationUtils";

function formatAnalyticsMonth(date) {
  return date.toLocaleString("en-US", { month: "short" });
}

function getAnalyticsJobDate(job) {
  const parsedDate = new Date(job?.createdAt || job?.created_at || job?.jobStartDate || Date.now());
  return Number.isNaN(parsedDate.getTime()) ? new Date() : parsedDate;
}

export function buildMonthlyJobRequests(jobs) {
  const now = new Date();
  return Array.from({ length: 6 }, (_, index) => {
    const date = new Date(now.getFullYear(), now.getMonth() - (5 - index), 1);
    const month = formatAnalyticsMonth(date);
    const year = date.getFullYear();
    return {
      month,
      requests: jobs.filter((job) => {
        const jobDate = getAnalyticsJobDate(job);
        return jobDate.getMonth() === date.getMonth() && jobDate.getFullYear() === year;
      }).length,
    };
  });
}

export function buildServiceAnalytics(jobs) {
  const categories = Array.from(new Set([...ANALYTICS_SERVICE_CATEGORIES, ...jobs.map((job) => job.serviceType).filter(Boolean)]));
  return categories.map((service) => ({
    service: service.replace("House ", ""),
    requests: jobs.filter((job) => job.serviceType === service).length,
  })).filter((item) => item.requests > 0 || ANALYTICS_SERVICE_CATEGORIES.some((service) => service.replace("House ", "") === item.service));
}

export function buildBarangayAnalytics(records, accessor, valueKey) {
  return BARANGAYS.map((barangay) => ({
    barangay,
    [valueKey]: records.filter((record) => normalizeBarangayName(accessor(record)) === barangay).length,
  })).filter((item) => item[valueKey] > 0).sort((a, b) => b[valueKey] - a[valueKey]).slice(0, 8);
}

export function buildBarangayHeatMapData(jobs, workers, verificationRequests, metric) {
  return BARANGAYS.map((barangay) => {
    const normalizedBarangay = normalizeBarangayName(barangay);
    const barangayJobs = jobs.filter((job) => normalizeBarangayName(job.barangay) === normalizedBarangay);
    const barangayWorkers = workers.filter((worker) => normalizeBarangayName(worker.barangay) === normalizedBarangay);
    const value = metric === "workers"
      ? barangayWorkers.length
      : metric === "completed"
        ? barangayJobs.filter((job) => job.status === "Completed").length
        : metric === "verification"
          ? verificationRequests.filter((request) => {
              const worker = workers.find((item) => item.username === request.workerUsername || String(item.id) === String(request.workerId));
              return ["Pending", "Under Review"].includes(request.status) && normalizeBarangayName(worker?.barangay) === normalizedBarangay;
            }).length
          : barangayJobs.length;
    return {
      barangay,
      value,
      jobs: barangayJobs.length,
      workers: barangayWorkers.length,
      completed: barangayJobs.filter((job) => job.status === "Completed").length,
      pendingVerifications: verificationRequests.filter((request) => {
        const worker = workers.find((item) => item.username === request.workerUsername || String(item.id) === String(request.workerId));
        return ["Pending", "Under Review"].includes(request.status) && normalizeBarangayName(worker?.barangay) === normalizedBarangay;
      }).length,
      ...getBarangayCenter(barangay),
    };
  }).filter((item) => item.latitude && item.longitude);
}

export function getWorkerRatingValue(worker) {
  const directRating = Number(worker?.averageRating ?? worker?.average_rating);
  if (Number.isFinite(directRating) && directRating > 0) {
    return directRating;
  }
  const ratingText = Number.parseFloat(String(worker?.rating || "").replace(/[^0-9.]/g, ""));
  if (Number.isFinite(ratingText) && ratingText > 0) {
    return ratingText;
  }
  const reviews = worker?.receivedReviews || [];
  const reviewRatings = reviews.map((review) => Number(review.rating)).filter((rating) => Number.isFinite(rating) && rating > 0);
  if (!reviewRatings.length) {
    return null;
  }
  return reviewRatings.reduce((sum, rating) => sum + rating, 0) / reviewRatings.length;
}

export function buildRatingDistribution(workers) {
  const ratings = workers.map(getWorkerRatingValue).filter((rating) => rating != null);
  return [5, 4, 3, 2, 1].map((stars) => ({
    stars: `${stars} star${stars > 1 ? "s" : ""}`,
    count: ratings.filter((rating) => Math.round(rating) === stars).length,
  }));
}
