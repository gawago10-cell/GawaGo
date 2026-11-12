// What the Post a Job form still needs, field by field. Each problem shows
// under its own field; the form used to raise one browser alert naming three
// fields at once ("Please complete the service type, job start date, and
// number of workers needed."). The rules match the backend's.

export const MAX_WORKERS_NEEDED = 50;

export function householdJobFormErrors(form, { pinConfirmed = false, today = "" } = {}) {
  const errors = {};
  if (!form.serviceType) {
    errors.serviceType = "Choose a service type.";
  } else if (form.serviceType === "Other" && !String(form.customServiceType || "").trim()) {
    errors.customServiceType = "Name the service.";
  }

  const workers = Number(form.workersNeeded);
  if (!Number.isInteger(workers) || workers < 1 || workers > MAX_WORKERS_NEEDED) {
    errors.workersNeeded = `Enter how many workers you need, from 1 to ${MAX_WORKERS_NEEDED}.`;
  }

  if (String(form.offeredRate ?? "").trim() === "") {
    errors.offeredRate = "Enter the rate you'll pay.";
  } else if (!(Number(form.offeredRate) >= 1)) {
    errors.offeredRate = "Enter a rate of at least PHP 1.00.";
  }

  if (!form.jobStartDate) {
    errors.jobStartDate = "Choose the day the job starts.";
  } else if (today && form.jobStartDate < today) {
    errors.jobStartDate = "Choose today or a later date.";
  }
  if (form.jobEndDate && form.jobStartDate && form.jobEndDate < form.jobStartDate) {
    errors.jobEndDate = "The end date can't be before the start date.";
  }

  if (!pinConfirmed) {
    errors.pin = "Pin the job site: use your current location, drag the pin on the map, or pin it manually.";
  }
  return errors;
}
