import { useEffect, useMemo, useRef, useState } from "react";
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

// Offline fallback only: the same formulas as apps.analytics.services, so a
// failed request doesn't show the admin different numbers for the same data.
const HIRED_STATUSES = ["Hired", "Completed"];
const LIVE_ASSIGNED_JOB_STATUSES = ["Already found a worker", "Waiting for Household Confirmation"];
const FINISHED_JOB_STATUSES = ["Completed", "Cancelled"];
const DASHBOARD_REFRESH_MS = 30000;

function calculateHiringSuccessRate(postedJobs) {
  let totalApplications = 0;
  let hiredCount = 0;
  postedJobs.forEach((job) => {
    (job.applications || []).forEach((app) => {
      totalApplications++;
      if (HIRED_STATUSES.includes(app.status)) hiredCount++;
    });
  });
  return totalApplications > 0 ? Math.round((hiredCount / totalApplications) * 1000) / 10 : 0;
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
      if (HIRED_STATUSES.includes(app.status)) {
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
    if ((job.applications || []).some((app) => HIRED_STATUSES.includes(app.status))) {
      jobsWithHires++;
    }
  });
  return postedJobs.length ? Math.round((jobsWithHires / postedJobs.length) * 1000) / 10 : 0;
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
  const verifiedUsers =
    verifiedWorkers + registeredHouseholds.filter((household) => household.verification === "Verified").length;
  const totalUsers = registeredWorkers.length + registeredHouseholds.length;
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
      const date = new Date(job?.createdAt || job?.created_at || job?.jobStartDate || Date.now());
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
      totalUsers,
      totalWorkers: registeredWorkers.length,
      households: registeredHouseholds.length,
      totalJobPostings: postedJobs.length,
      activeJobs: postedJobs.filter((job) => job.status === "Open").length,
      activeApplications: postedJobs
        .filter((job) => !FINISHED_JOB_STATUSES.includes(job.status))
        .reduce(
          (sum, job) => sum + (job.applications || []).filter((application) => application.status === "Pending").length,
          0,
        ),
      completedServices: postedJobs.filter((job) => job.status === "Completed").length,
      cancelledRequests: postedJobs.filter((job) => job.status === "Cancelled").length,
      ongoingMatches: postedJobs.filter(
        (job) =>
          LIVE_ASSIGNED_JOB_STATUSES.includes(job.status) &&
          (job.applications || []).some((application) => application.status === "Hired"),
      ).length,
      verifiedUsers,
      verifiedWorkers,
      pendingVerifications: verificationRequests.filter((request) => request.status === "Pending").length,
      rejectedVerifications: verificationRequests.filter((request) => request.status === "Rejected").length,
      rejectedWorkers: registeredWorkers.filter((worker) => worker.verification === "Rejected").length,
      verifiedPercent: totalUsers ? Math.round((verifiedUsers / totalUsers) * 100) : 0,
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

function buildLocalMetrics({ postedJobs, registeredHouseholds, registeredWorkers, verificationRequests }) {
  const openJobSlots = postedJobs
    .filter((job) => job.status === "Open")
    .reduce((total, job) => total + getWorkersNeeded(job), 0);
  const analytics = buildLocalAnalytics({ postedJobs, registeredHouseholds, registeredWorkers, verificationRequests });
  return {
    openJobs: openJobSlots,
    verifiedWorkers: registeredWorkers.filter((worker) => worker.verification === "Verified").length,
    completedJobs: postedJobs.filter((job) => job.status === "Completed").length,
    totalAccounts: registeredWorkers.length + registeredHouseholds.length,
    avgRating: analytics.summary.averageWorkerRating,
    analytics,
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
  const isPlatformAdmin = currentUser?.role === "admin" || currentUser?.role === "superadmin";
  const localInputsRef = useRef({ postedJobs, registeredHouseholds, registeredWorkers, verificationRequests });
  localInputsRef.current = { postedJobs, registeredHouseholds, registeredWorkers, verificationRequests };
  // The background poll hands back new arrays every few seconds even when
  // nothing changed; keying the fetch on what actually changed stops the
  // dashboard from re-requesting the whole analytics payload on every poll.
  const dataSignature = useMemo(
    () =>
      [
        postedJobs
          .map((job) => `${job.id}:${job.status}:${(job.applications || []).map((app) => app.status).join(",")}`)
          .join("|"),
        verificationRequests.map((request) => `${request.id}:${request.status}`).join("|"),
        registeredWorkers.length,
        registeredHouseholds.length,
      ].join("#"),
    [postedJobs, verificationRequests, registeredWorkers.length, registeredHouseholds.length],
  );

  useEffect(() => {
    let cancelled = false;
    const useBackend = isPlatformAdmin && Boolean(getAuthToken());
    if (!useBackend) {
      setDashboardMetrics(buildLocalMetrics(localInputsRef.current));
      return undefined;
    }

    async function loadDashboardMetrics() {
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
          setDashboardMetrics(buildLocalMetrics(localInputsRef.current));
        }
      }
    }

    loadDashboardMetrics();
    // Changes made elsewhere (another admin, a household) still show up.
    const timer = window.setInterval(loadDashboardMetrics, DASHBOARD_REFRESH_MS);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [isPlatformAdmin, dataSignature]);

  return dashboardMetrics;
}
