import { STATUS_PRIORITY } from "../constants/appConstants";
import { getDisplayName } from "./formatters";

export function getHouseholdNotifications(jobs, workers) {
  // A worker the household invited never applied, so they get no "applied" notice.
  return jobs.flatMap((job) => (job.applications || []).filter((application) => application.status !== "Hire Request").map((application) => {
    const worker = workers.find((item) => item.id === application.workerId);
    return {
      id: `application-${job.id}-${application.workerId}-${application.appliedAt}`,
      title: "New worker application",
      message: `${getDisplayName(worker?.firstName, worker?.lastName, worker?.username)} applied to "${job.jobTitle || job.serviceType}".`,
      date: application.appliedAt || "Recently",
      workerId: application.workerId,
      jobId: job.id,
    };
  })).sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
}

export function getHouseholdReviewReminderNotifications(jobs, workers, household) {
  return jobs
    .filter((job) => job.status === "Completed")
    .map((job) => {
      const acceptedApplication =
        (job.applications || []).find((application) => ["Completed", "Hired"].includes(application.status)) ||
        (job.applications || []).find((application) => application.status !== "Rejected") ||
        null;
      const worker =
        acceptedApplication &&
        workers.find(
          (item) =>
            String(item.id) === String(acceptedApplication.workerId) ||
            item.username === acceptedApplication.workerUsername ||
            getDisplayName(item.firstName, item.lastName, item.username) === acceptedApplication.workerName,
        );

      if (!worker) {
        return null;
      }

      const workerNames = [
        worker.username,
        worker.workerUsername,
        getDisplayName(worker.firstName, worker.lastName, worker.username),
      ].filter(Boolean);
      const jobTitles = [job.jobTitle, job.serviceType].filter(Boolean);
      const hasReview = (household?.givenFeedback || []).some((review) => {
        const sameWorker =
          workerNames.includes(review.targetUsername) ||
          workerNames.includes(review.targetName) ||
          workerNames.includes(review.target);
        const sameJob = !review.jobTitle || jobTitles.includes(review.jobTitle);
        return sameWorker && sameJob && review.rating != null;
      });

      if (hasReview) {
        return null;
      }

      return {
        id: `review-reminder-${job.id}-${worker.id || worker.username}`,
        title: "Review reminder",
        message: `${job.jobTitle || job.serviceType} service by ${getDisplayName(
          worker.firstName,
          worker.lastName,
          worker.username,
        )} is completed and waiting for your feedback.`,
        date: job.completedAt || job.updatedAt || job.createdAt || "Recently",
        workerId: worker.id,
        jobId: job.id,
        notificationType: "review-reminder",
      };
    })
    .filter(Boolean)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
}

export function getVerificationNotifications(requests, workers) {
  return requests.map((request) => {
    const worker = workers.find((item) => item.id === request.workerId);
    return {
      id: `verification-${request.id}`,
      title: `Verification ${request.status}`,
      message: `${getDisplayName(worker?.firstName, worker?.lastName, worker?.username)}'s documents are ${request.status.toLowerCase()}.`,
      date: request.submittedAt || request.reviewedAt || "Recently",
    };
  }).sort((a, b) => (STATUS_PRIORITY[a.title.split(" ").pop()] || 0) - (STATUS_PRIORITY[b.title.split(" ").pop()] || 0));
}
