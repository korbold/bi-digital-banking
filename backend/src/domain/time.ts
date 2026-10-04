// Ecuador (America/Guayaquil) is UTC-5 all year, no DST, so a fixed offset is
// exact and keeps tests deterministic without depending on the host ICU data.

const OFFSET_MS = -5 * 60 * 60 * 1000;

export interface LocalParts {
  year: number;
  month: number; // 0-11
  day: number;
  hour: number;
}

export function guayaquilParts(date: Date): LocalParts {
  const local = new Date(date.getTime() + OFFSET_MS);
  return {
    year: local.getUTCFullYear(),
    month: local.getUTCMonth(),
    day: local.getUTCDate(),
    hour: local.getUTCHours(),
  };
}

/** UTC instant of local midnight on the 1st of the month `monthsBack` months ago. */
export function startOfLocalMonth(date: Date, monthsBack = 0): Date {
  const { year, month } = guayaquilParts(date);
  return new Date(Date.UTC(year, month - monthsBack, 1) - OFFSET_MS);
}

export function greetingFor(date: Date): string {
  const { hour } = guayaquilParts(date);
  if (hour < 12) return 'Buenos días';
  if (hour < 19) return 'Buenas tardes';
  return 'Buenas noches';
}
