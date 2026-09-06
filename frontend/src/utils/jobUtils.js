import { DEMO_LOCATIONS } from "../constants/appConstants";
import { getDisplayName } from "./formatters";

export function getApplicationStatusLabel(status) {
  const statusMap = {
    pending: "Applied",
    hire_requested: "Hire Requested",
    hired: "Hired",
    rejected: "Rejected",
    closed: "Closed",
    completed: "Hired", // Display completed as Hired to avoid confusion with job completion
  };
  return statusMap[status] || status;
}

export function getWorkersNeeded(job) {
  const workersNeeded = Number(job?.workersNeeded || job?.workerSlots || 1);
  return Number.isFinite(workersNeeded) && workersNeeded > 0 ? workersNeeded : 1;
}

export function getHiredWorkerCount(job) {
  if (job?.hiredCount !== undefined && job?.hiredCount !== null) {
    const hiredCount = Number(job.hiredCount);
    return Number.isFinite(hiredCount) && hiredCount >= 0 ? hiredCount : 0;
  }
  return (job?.applications || []).filter((application) => ["Hired", "Completed"].includes(application.status)).length;
}

export function getPendingApplicationCount(job) {
  return (job?.applications || []).filter((application) => application.status === "Pending").length;
}

export function getHiringProgressLabel(job) {
  return `${getHiredWorkerCount(job)}/${getWorkersNeeded(job)}`;
}

export function isJobOpenForApplications(job) {
  if (job?.canApply !== undefined && job?.canApply !== null) {
    return Boolean(job.canApply);
  }
  return job?.status === "Open" && getHiredWorkerCount(job) < getWorkersNeeded(job);
}

export function findJobApplicationForWorker(job, worker) {
  if (!job || !worker) {
    return null;
  }
  return (job.applications || []).find((application) => {
    const matchesWorkerId = application.workerId != null && String(application.workerId) === String(worker.id);
    const matchesWorkerUsername = application.workerUsername && worker.username && application.workerUsername === worker.username;
    return matchesWorkerId || matchesWorkerUsername;
  }) || null;
}

export function getJobStatusBadgeClass(status) {
  if (status === "Cancelled") {
    return "gg-status-badge gg-status-cancelled";
  }
  if (status === "Already found a worker") {
    return "gg-status-badge gg-status-filled";
  }
  if (status === "Waiting for Household Confirmation") {
    return "gg-status-badge gg-status-pending";
  }
  if (status === "Completed") {
    return "gg-status-badge gg-status-completed";
  }
  return "gg-status-badge gg-status-open";
}

export function buildMatchedWorkersForJob(job, workers) {
  const applicantIds = (job.applications || [])
    .filter((application) => ["Hired", "Completed"].includes(application.status))
    .map((application) => application.workerId);
  const matchedWorkerIds = [...new Set([...(job.matchedWorkerIds || []), ...applicantIds])];
  return matchedWorkerIds.map((workerId) => workers.find((worker) => String(worker.id) === String(workerId))).filter(Boolean);
}

export function buildWorkerFallbackFromJob(job, selectedWorkerId) {
  if (!job || selectedWorkerId == null) {
    return null;
  }
  const selectedWorkerIdentity =
    selectedWorkerId && typeof selectedWorkerId === "object" ? selectedWorkerId : null;
  const selectedWorkerTokens = selectedWorkerIdentity
    ? [
        selectedWorkerIdentity.id,
        selectedWorkerIdentity.workerId,
        selectedWorkerIdentity.userId,
        selectedWorkerIdentity.user_id,
        selectedWorkerIdentity.username,
        selectedWorkerIdentity.workerUsername,
        selectedWorkerIdentity.displayName,
        selectedWorkerIdentity.workerName,
      ]
    : [selectedWorkerId];
  const matchesSelectedWorker = (value) =>
    selectedWorkerTokens
      .filter((token) => token !== null && token !== undefined && token !== "")
      .some((token) => String(token).trim().toLowerCase() === String(value ?? "").trim().toLowerCase());
  const application = (job.applications || []).find(
    (item) =>
      matchesSelectedWorker(item.workerId) ||
      matchesSelectedWorker(item.worker_id) ||
      matchesSelectedWorker(item.workerUsername) ||
      matchesSelectedWorker(item.workerName),
  );
  if (!application) {
    return null;
  }
  const fallbackWorkerId =
    application.workerId ??
    selectedWorkerIdentity?.id ??
    selectedWorkerIdentity?.workerId ??
    selectedWorkerIdentity?.userId ??
    selectedWorkerId;
  const fallbackUsername =
    application.workerUsername ||
    selectedWorkerIdentity?.username ||
    selectedWorkerIdentity?.workerUsername ||
    `worker-${fallbackWorkerId}`;
  return {
    id: fallbackWorkerId,
    username: fallbackUsername,
    firstName: "",
    lastName: "",
    email: "",
    phone: "",
    barangay: "",
    streetAddress: "",
    bio: "",
    hourlyRate: "0.00",
    dailyRate: "0.00",
    yearsExperience: "0",
    skills: [],
    verification: "Not Yet Verified",
    rating: "No ratings yet",
    reviewsDone: 0,
    status: application.status === "Hired" ? "Hired" : "Available",
    distanceKm: null,
    avatar: (application.workerName || application.workerUsername || "W").slice(0, 1).toUpperCase(),
    receivedReviews: [],
    givenFeedback: [],
    verificationNotifications: [],
    applicationNotifications: [],
  };
}

export function getWorkerJobMatches(worker, jobs) {
  if (!worker) {
    return [];
  }
  const normalizeSkill = (value) => String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
  const workerSkills = new Set((worker.skills || []).map(normalizeSkill));
  return jobs.filter(isJobOpenForApplications).map((job) => {
    const matchesSkill = workerSkills.has(normalizeSkill(job.serviceType))
      || workerSkills.has(normalizeSkill(job.requiredSkill));
    return { ...job, matchesSkill };
  }).sort((firstJob, secondJob) => {
    if (firstJob.matchesSkill === secondJob.matchesSkill) {
      return new Date(secondJob.createdAt).getTime() - new Date(firstJob.createdAt).getTime();
    }
    return firstJob.matchesSkill ? -1 : 1;
  });
}

export function createJobRecord(jobForm, currentHousehold, jobId) {
  return {
    id: jobId,
    householdUsername: currentHousehold?.username || "",
    householdName: getDisplayName(currentHousehold?.firstName, currentHousehold?.lastName, currentHousehold?.username),
    jobTitle: jobForm.jobTitle.trim() || jobForm.serviceType,
    serviceType: jobForm.serviceType,
    scheduleType: jobForm.scheduleType,
    preferredDate: jobForm.preferredDate,
    preferredTime: jobForm.preferredTime,
    description: jobForm.description.trim(),
    barangay: jobForm.barangay.trim(),
    streetAddress: jobForm.streetAddress.trim(),
    latitude: jobForm.latitude ?? null,
    longitude: jobForm.longitude ?? null,
    offeredRate: String(jobForm.offeredRate),
    rateType: jobForm.rateType,
    workersNeeded: getWorkersNeeded(jobForm),
    status: "Open",
    matchedWorkerIds: [],
    applications: [],
    createdAt: new Date().toISOString(),
  };
}

function getDemoCreatedAt(monthOffset, day = 8) {
  const date = new Date();
  date.setMonth(date.getMonth() - monthOffset);
  date.setDate(day);
  date.setHours(9, 0, 0, 0);
  return date.toISOString();
}

export function createDemoJobPostings() {
  const location = (index) => {
    const [barangay, latitude, longitude] = DEMO_LOCATIONS[index - 1];
    return { barangay, streetAddress: `Demo Street ${index}`, latitude, longitude };
  };
  return [
    { id: "demo-job-1", householdUsername: "Household 1", householdName: "Household One", jobTitle: "House Cleaning Help", serviceType: "House Cleaning", scheduleType: "One-Time", preferredDate: "2026-05-18", preferredTime: "09:00", description: "General house cleaning for a small family home.", ...location(1), offeredRate: "700.00", rateType: "Per Day", workersNeeded: "1", status: "Open", matchedWorkerIds: ["demo-worker-1", "demo-worker-5"], applications: [{ id: "demo-app-1", workerId: "demo-worker-1", workerUsername: "Worker1", workerName: "Worker One", status: "Pending", appliedAt: "Recently" }], createdAt: getDemoCreatedAt(0, 3) },
    { id: "demo-job-2", householdUsername: "Household 2", householdName: "Household Two", jobTitle: "Kitchen Plumbing Repair", serviceType: "Plumbing", scheduleType: "One-Time", preferredDate: "2026-05-20", preferredTime: "13:00", description: "Fix leaking kitchen sink.", ...location(2), offeredRate: "950.00", rateType: "Fixed Rate", workersNeeded: "1", status: "Completed", matchedWorkerIds: ["demo-worker-2"], applications: [{ id: "demo-app-2", workerId: "demo-worker-2", workerUsername: "Worker2", workerName: "Worker Two", status: "Completed", appliedAt: "Recently" }], createdAt: getDemoCreatedAt(1, 5) },
    { id: "demo-job-3", householdUsername: "Household 3", householdName: "Household Three", jobTitle: "Electrical Outlet Check", serviceType: "Electrical Work", scheduleType: "One-Time", preferredDate: "2026-04-12", preferredTime: "10:00", description: "Inspect and repair two electrical outlets.", ...location(3), offeredRate: "1200.00", rateType: "Fixed Rate", workersNeeded: "1", status: "Completed", matchedWorkerIds: ["demo-worker-3"], applications: [{ id: "demo-app-3", workerId: "demo-worker-3", workerUsername: "Worker3", workerName: "Worker Three", status: "Completed", appliedAt: "Recently" }], createdAt: getDemoCreatedAt(2, 9) },
    { id: "demo-job-4", householdUsername: "Household 4", householdName: "Household Four", jobTitle: "Laundry Assistance", serviceType: "Laundry", scheduleType: "Part-Time", preferredDate: "2026-03-22", preferredTime: "08:00", description: "Weekly laundry help.", ...location(4), offeredRate: "500.00", rateType: "Per Day", workersNeeded: "1", status: "Cancelled", matchedWorkerIds: ["demo-worker-5"], applications: [], createdAt: getDemoCreatedAt(3, 12) },
    { id: "demo-job-5", householdUsername: "Household 5", householdName: "Household Five", jobTitle: "Childcare Support", serviceType: "Childcare", scheduleType: "Part-Time", preferredDate: "2026-02-15", preferredTime: "14:00", description: "Afternoon childcare support.", ...location(5), offeredRate: "750.00", rateType: "Per Day", workersNeeded: "1", status: "Open", matchedWorkerIds: ["demo-worker-4"], applications: [{ id: "demo-app-5", workerId: "demo-worker-4", workerUsername: "Worker4", workerName: "Worker Four", status: "Pending", appliedAt: "Recently" }], createdAt: getDemoCreatedAt(4, 15) },
    { id: "demo-job-6", householdUsername: "Household 1", householdName: "Household One", jobTitle: "Cooking Support", serviceType: "Cooking", scheduleType: "One-Time", preferredDate: "2026-01-28", preferredTime: "16:00", description: "Meal preparation for family gathering.", ...location(1), offeredRate: "650.00", rateType: "Per Day", workersNeeded: "1", status: "Completed", matchedWorkerIds: ["demo-worker-5"], applications: [{ id: "demo-app-6", workerId: "demo-worker-5", workerUsername: "Worker5", workerName: "Worker Five", status: "Completed", appliedAt: "Recently" }], createdAt: getDemoCreatedAt(5, 18) },
  ];
}
