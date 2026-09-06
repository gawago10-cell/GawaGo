import { useEffect, useState } from "react";
import { getAuthToken } from "../api/apiClient";
import { fetchDashboardMetrics } from "../services/backendDataService";
import { getWorkersNeeded } from "../utils/jobUtils";
import {
  buildBarangayAnalytics,
  buildBarangayHeatMapData,
  buildMonthlyJobRequests,
  buildRatingDistribution,
  buildServiceAnalytics,
  getWorkerRatingValue,
} from "../utils/analyticsUtils";
import { SKILLS } from "../constants/appConstants";

// Enhanced Analytics Helper Functions
function calculateHiringSuccessRate(postedJobs) {
  let totalApplications = 0;
  let hiredCount = 0;
  postedJobs.forEach((job) => {
    (job.applications || []).forEach((app) => {
      if (!["Pending"].includes(app.status)) {
        totalApplications++;
        if (app.status === "Hired") hiredCount++;
      }
    });
  });
  return totalApplications > 0 ? Math.round((hiredCount / totalApplications) * 100) : 0;
}

function calculateApplicationsByDate(postedJobs) {
  const dateMap = {};
  postedJobs.forEach((job) => {
    (job.applications || []).forEach((app) => {
      const date = new Date(app.created_at || app.createdAt || Date.now());
      const dateStr = date.toISOString().split("T")[0];
      dateMap[dateStr] = (dateMap[dateStr] || 0) + 1;
    });
  });
  return Object.entries(dateMap)
    .map(([date, count]) => ({ date, applications: count }))
    .sort((a, b) => new Date(a.date) - new Date(b.date))
    .slice(-30);
}

function buildApplicationTrends(postedJobs) {
  const monthMap = {};
  postedJobs.forEach((job) => {
    (job.applications || []).forEach((app) => {
      const date = new Date(app.created_at || app.createdAt || Date.now());
      const month = date.toLocaleString("en-US", { month: "short", year: "2-digit" });
      monthMap[month] = (monthMap[month] || 0) + 1;
    });
  });
  return Object.entries(monthMap).map(([month, count]) => ({ month, applications: count }));
}

function calculateWorkerHiringStats(postedJobs, registeredWorkers) {
  const workerHireMap = {};
  postedJobs.forEach((job) => {
    (job.applications || []).forEach((app) => {
      if (app.status === "Hired") {
        const workerId = app.workerId || app.worker_id;
        workerHireMap[workerId] = (workerHireMap[workerId] || 0) + 1;
      }
    });
  });
  const hiredWorkers = Object.keys(workerHireMap).length;
  const repeatHires = Object.values(workerHireMap).filter((count) => count > 1).length;
  return {
    hiredWorkers,
    repeatHires,
    hirePercentage: registeredWorkers.length ? Math.round((hiredWorkers / registeredWorkers.length) * 100) : 0,
  };
}

function calculateJobMatchRate(postedJobs) {
  let jobsWithHires = 0;
  postedJobs.forEach((job) => {
    if ((job.applications || []).some((app) => app.status === "Hired")) {
      jobsWithHires++;
    }
  });
  return postedJobs.length ? Math.round((jobsWithHires / postedJobs.length) * 100) : 0;
}

function buildDefaultAnalytics() {
  return {
    summary: {
      totalUsers: 0,
      totalWorkers: 0,
      households: 0,
      totalJobPostings: 0,
      activeJobs: 0,
      activeApplications: 0,
      completedServices: 0,
      cancelledRequests: 0,
      ongoingMatches: 0,
      verifiedUsers: 0,
      verifiedWorkers: 0,
      pendingVerifications: 0,
      rejectedVerifications: 0,
      rejectedWorkers: 0,
      verifiedPercent: 0,
      averageWorkerRating: "No ratings yet",
      ratedWorkerCount: 0,
    },
    monthlyJobRequests: [],
    serviceAnalytics: [],
    geographicAnalytics: {
      barangayDemand: [],
      workerAvailability: [],
    },
    barangayJobAnalytics: [],
    barangayWorkerAnalytics: [],
    heatMapData: [],
    ratingDistribution: [],
    rateTransparency: {
      averageRatesByCategory: [],
      pricingTrends: [],
    },
    serviceRateSummary: [],
  };
}

function buildLocalAnalytics({ postedJobs, registeredHouseholds, registeredWorkers, verificationRequests = [] }) {
  const verifiedWorkers = registeredWorkers.filter((worker) => worker.verification === "Verified").length;
  const workerRatingValues = registeredWorkers.map(getWorkerRatingValue).filter((rating) => rating != null);
  const averageWorkerRating = workerRatingValues.length
    ? (workerRatingValues.reduce((sum, rating) => sum + rating, 0) / workerRatingValues.length).toFixed(2)
    : "No ratings yet";
  const serviceRateSummary = SKILLS.map((skill) => {
    const categoryJobs = postedJobs.filter((job) => job.serviceType === skill);
    const averageRate = categoryJobs.length
      ? categoryJobs.reduce((sum, job) => sum + Number(job.offeredRate || 0), 0) / categoryJobs.length
      : 0;
    return {
      skill,
      count: categoryJobs.length,
      averageRate,
    };
  })
    .filter((item) => item.count)
    .sort((a, b) => b.count - a.count);
  const pricingTrends = buildMonthlyJobRequests(postedJobs).map((item) => {
    const monthJobs = postedJobs.filter((job) => {
      const date = new Date(job?.createdAt || job?.created_at || job?.preferredDate || Date.now());
      return !Number.isNaN(date.getTime()) && date.toLocaleString("en-US", { month: "short" }) === item.month;
    });
    const averageRate = monthJobs.length
      ? monthJobs.reduce((sum, job) => sum + Number(job.offeredRate || 0), 0) / monthJobs.length
      : 0;
    return {
      month: item.month,
      averageRate,
      postings: monthJobs.length,
    };
  });

  const barangayDemand = buildBarangayAnalytics(postedJobs, (job) => job.barangay, "jobs");
  const workerAvailability = buildBarangayAnalytics(registeredWorkers, (worker) => worker.barangay, "workers");

  return {
    summary: {
      totalUsers: registeredWorkers.length + registeredHouseholds.length,
      totalWorkers: registeredWorkers.length,
      households: registeredHouseholds.length,
      totalJobPostings: postedJobs.length,
      activeJobs: postedJobs.filter((job) => job.status === "Open").length,
      activeApplications: postedJobs.reduce(
        (sum, job) =>
          sum +
          (job.applications || []).filter(
            (application) => !["Rejected", "Completed", "Cancelled"].includes(application.status),
          ).length,
        0,
      ),
      completedServices: postedJobs.filter((job) => job.status === "Completed").length,
      cancelledRequests: postedJobs.filter((job) => job.status === "Cancelled").length,
      ongoingMatches: postedJobs.filter((job) =>
        (job.applications || []).some((application) => application.status === "Hired"),
      ).length,
      verifiedUsers: verifiedWorkers,
      verifiedWorkers,
      pendingVerifications: verificationRequests.filter((request) => request.status === "Pending").length,
      rejectedVerifications: verificationRequests.filter((request) => request.status === "Rejected").length,
      rejectedWorkers: registeredWorkers.filter((worker) => worker.verification === "Rejected").length,
      verifiedPercent: registeredWorkers.length ? Math.round((verifiedWorkers / registeredWorkers.length) * 100) : 0,
      averageWorkerRating,
      ratedWorkerCount: workerRatingValues.length,
    },
    monthlyJobRequests: buildMonthlyJobRequests(postedJobs),
    serviceAnalytics: buildServiceAnalytics(postedJobs),
    geographicAnalytics: {
      barangayDemand,
      workerAvailability,
    },
    barangayJobAnalytics: barangayDemand,
    barangayWorkerAnalytics: workerAvailability,
    heatMapData: buildBarangayHeatMapData(postedJobs, registeredWorkers, verificationRequests, "jobs"),
    ratingDistribution: buildRatingDistribution(registeredWorkers),
    rateTransparency: {
      averageRatesByCategory: serviceRateSummary,
      pricingTrends,
    },
    enhancedAnalytics: {
      hiringSuccessRate: calculateHiringSuccessRate(postedJobs),
      applicationsByDate: calculateApplicationsByDate(postedJobs),
      workerHiringStats: calculateWorkerHiringStats(postedJobs, registeredWorkers),
      jobMatchRate: calculateJobMatchRate(postedJobs),
      applicationTrends: buildApplicationTrends(postedJobs),
    },
    serviceRateSummary: serviceRateSummary.slice(0, 5),
  };
}

export function useDashboardMetrics({ currentUser, postedJobs, registeredHouseholds, registeredWorkers, verificationRequests }) {
  const [dashboardMetrics, setDashboardMetrics] = useState({
    openJobs: 0,
    verifiedWorkers: 0,
    completedJobs: 0,
    totalAccounts: 0,
    avgRating: null,
    analytics: buildDefaultAnalytics(),
  });

  useEffect(() => {
    let cancelled = false;

    function buildLocalMetrics() {
      const openJobSlots = postedJobs
        .filter((job) => job.status === "Open")
        .reduce((total, job) => total + getWorkersNeeded(job), 0);

      return {
        openJobs: openJobSlots,
        verifiedWorkers: registeredWorkers.filter((worker) => worker.verification === "Verified").length,
        completedJobs: postedJobs.filter((job) => job.status === "Completed").length,
        totalAccounts: registeredWorkers.length + registeredHouseholds.length,
        avgRating: buildLocalAnalytics({
          postedJobs,
          registeredHouseholds,
          registeredWorkers,
          verificationRequests,
        }).summary.averageWorkerRating,
        analytics: buildLocalAnalytics({ postedJobs, registeredHouseholds, registeredWorkers, verificationRequests }),
      };
    }

    async function loadDashboardMetrics() {
      const authToken = getAuthToken();
      const isPlatformAdmin = currentUser?.role === "admin" || currentUser?.role === "superadmin";
      if (!isPlatformAdmin || !authToken) {
        if (!cancelled) {
          setDashboardMetrics(buildLocalMetrics());
        }
        return;
      }
      try {
        const data = await fetchDashboardMetrics();
        if (!cancelled) {
          setDashboardMetrics({
            openJobs: data.open_jobs ?? 0,
            verifiedWorkers: data.verified_workers ?? 0,
            completedJobs: data.completed_jobs ?? 0,
            totalAccounts: data.total_accounts ?? 0,
            avgRating: data.avg_rating,
            analytics: data.analytics || buildDefaultAnalytics(),
          });
        }
      } catch (error) {
        if (!cancelled) {
          setDashboardMetrics(buildLocalMetrics());
        }
      }
    }

    loadDashboardMetrics();
    return () => {
      cancelled = true;
    };
  }, [currentUser?.role, postedJobs, registeredHouseholds, registeredWorkers, verificationRequests]);

  return dashboardMetrics;
}
