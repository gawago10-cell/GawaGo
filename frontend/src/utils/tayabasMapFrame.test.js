import { describe, expect, it } from "vitest";

import { BARANGAY_CENTERS } from "../constants/appConstants";
import { isInsideTayabasCity } from "./tayabasMapFrame";

describe("isInsideTayabasCity", () => {
  it("accepts every barangay centre the app knows", () => {
    const outside = Object.entries(BARANGAY_CENTERS)
      .filter(([, point]) => !isInsideTayabasCity(point.latitude, point.longitude))
      .map(([name]) => name);
    expect(outside).toEqual([]);
  });

  it("rejects the neighbouring towns a rectangle around the city would take in", () => {
    expect(isInsideTayabasCity(13.9373, 121.617)).toBe(false); // Lucena city hall
    expect(isInsideTayabasCity(14.1131, 121.5572)).toBe(false); // Lucban
    expect(isInsideTayabasCity(13.9719, 121.6869)).toBe(false); // Pagbilao
    expect(isInsideTayabasCity(13.9628, 121.5264)).toBe(false); // Sariaya
  });

  it("rejects missing or non-numeric coordinates", () => {
    expect(isInsideTayabasCity(null, null)).toBe(false);
    expect(isInsideTayabasCity("abc", 121.59)).toBe(false);
  });
});
