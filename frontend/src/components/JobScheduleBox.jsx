import React from "react";
import { formatJobDay } from "../utils/formatters";

function localIsoDate() {
  const now = new Date();
  return new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

/**
 * A job's schedule in words, shared by the box (My Jobs, dashboard) and the
 * compact lines (My Applications): Starts / Started, Ends / Ended, each date
 * with its day of the week. A one-day job with no end date ends the day it
 * starts. Null when the job has no dates.
 */
export function describeJobSchedule({ startDate, endDate, workingDays, finished = false }) {
  if (!startDate && !endDate) {
    return null;
  }
  const days = Number(workingDays) || null;
  const end = endDate || (days === 1 ? startDate : "");
  const today = localIsoDate();
  return {
    startWord: !startDate ? "Start" : startDate > today ? "Starts" : "Started",
    startText: formatJobDay(startDate) || "Not set",
    startSet: Boolean(startDate),
    endWord: !end ? "End" : finished || end < today ? "Ended" : "Ends",
    endText: formatJobDay(end) || "Not set",
    endSet: Boolean(end),
    daysText: days ? `${days} working day${days === 1 ? "" : "s"}` : "",
  };
}

/**
 * A job's start and end, each with the day of the week, and its working days
 * (panel review: both sides should see which day work starts and the date it
 * ends).
 */
export default function JobScheduleBox(props) {
  const schedule = describeJobSchedule(props);
  if (!schedule) {
    return null;
  }
  return (
    <div className="job-schedule-box">
      <div className={schedule.startSet ? "" : "is-unset"}>
        <span>{schedule.startWord}</span>
        <strong>{schedule.startText}</strong>
      </div>
      <div className={schedule.endSet ? "" : "is-unset"}>
        <span>{schedule.endWord}</span>
        <strong>{schedule.endText}</strong>
      </div>
      {schedule.daysText ? <div className="job-schedule-days">{schedule.daysText}</div> : null}
    </div>
  );
}

/**
 * The same schedule as three short lines for a table cell (My Applications),
 * with the schedule type ("One-Time") beside the working days. Without dates
 * it shows the schedule wording alone, as before.
 */
export function JobScheduleLines({ startDate, endDate, workingDays, finished = false, scheduleLabel = "" }) {
  const schedule = describeJobSchedule({ startDate, endDate, workingDays, finished });
  if (!schedule) {
    return scheduleLabel || "Not set";
  }
  const extra = [scheduleLabel, schedule.daysText].filter(Boolean).join(" · ");
  return (
    <div className="job-schedule-lines">
      <div className={schedule.startSet ? "" : "is-unset"}>
        <span>{schedule.startWord}</span>
        <strong>{schedule.startText}</strong>
      </div>
      <div className={schedule.endSet ? "" : "is-unset"}>
        <span>{schedule.endWord}</span>
        <strong>{schedule.endText}</strong>
      </div>
      {extra ? <small>{extra}</small> : null}
    </div>
  );
}
