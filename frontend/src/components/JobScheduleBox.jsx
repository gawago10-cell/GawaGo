import React from "react";
import { formatJobDay } from "../utils/formatters";

function localIsoDate() {
  const now = new Date();
  return new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

/**
 * A job's start and end, each with the day of the week, and its working days
 * (panel review: both sides should see which day work starts and the date it
 * ends). The words follow the dates: Starts / Started, Ends / Ended. A
 * one-day job with no end date ends the day it starts.
 */
export default function JobScheduleBox({ startDate, endDate, workingDays, finished = false }) {
  if (!startDate && !endDate) {
    return null;
  }
  const days = Number(workingDays) || null;
  const end = endDate || (days === 1 ? startDate : "");
  const today = localIsoDate();
  const startWord = !startDate ? "Start" : startDate > today ? "Starts" : "Started";
  const endWord = !end ? "End" : finished || end < today ? "Ended" : "Ends";
  return (
    <div className="job-schedule-box">
      <div className={startDate ? "" : "is-unset"}>
        <span>{startWord}</span>
        <strong>{formatJobDay(startDate) || "Not set"}</strong>
      </div>
      <div className={end ? "" : "is-unset"}>
        <span>{endWord}</span>
        <strong>{formatJobDay(end) || "Not set"}</strong>
      </div>
      {days ? (
        <div className="job-schedule-days">
          {days} working day{days === 1 ? "" : "s"}
        </div>
      ) : null}
    </div>
  );
}
