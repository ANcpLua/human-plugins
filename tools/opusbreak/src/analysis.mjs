const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const Z_95 = 1.959964;
const ALPHA = 0.05;

export function poissonInterval(count, exposureHours) {
  if (exposureHours <= 0) throw new RangeError("exposureHours must be positive");
  const rate = count / exposureHours;
  if (count === 0) {
    return {
      rate,
      low: 0,
      high: -Math.log(ALPHA) / exposureHours,
      method: "rule_of_three",
    };
  }
  const error = Math.sqrt(rate / exposureHours);
  return {
    rate,
    low: Math.max(0, rate - Z_95 * error),
    high: rate + Z_95 * error,
    method: count < 5 ? "wald_small_n" : "wald",
  };
}

export function bucketOf(timestamp, timezone) {
  const formatter = new Intl.DateTimeFormat("en-GB", {
    timeZone: timezone,
    weekday: "short",
    hour: "2-digit",
    hour12: false,
  });
  const parts = Object.fromEntries(
    formatter.formatToParts(new Date(timestamp)).map((part) => [part.type, part.value]),
  );
  const weekday = DAY_NAMES.indexOf(parts.weekday);
  let hour = Number.parseInt(parts.hour, 10);
  if (hour === 24) hour = 0;
  if (weekday < 0 || !Number.isInteger(hour)) throw new RangeError("invalid incident timestamp");
  return { weekday, hour };
}

export function analyze(incidents, timezone = "UTC", now = Date.now()) {
  if (!incidents.length) {
    return {
      timezone,
      observedDays: 0,
      incidents: 0,
      buckets: [],
      best: [],
      worst: [],
    };
  }
  const earliest = Math.min(...incidents.map((incident) => new Date(incident.created_at).getTime()));
  if (!Number.isFinite(earliest) || earliest >= now) throw new RangeError("invalid incident archive");
  const observedDays = Math.min((now - earliest) / 86_400_000, 365);
  const exposure = observedDays / 7;
  const counts = new Map(
    Array.from({ length: 7 * 24 }, (_, index) => [
      `${Math.floor(index / 24)}-${index % 24}`,
      0,
    ]),
  );
  for (const incident of incidents) {
    const { weekday, hour } = bucketOf(incident.created_at, timezone);
    const key = `${weekday}-${hour}`;
    counts.set(key, counts.get(key) + 1);
  }
  const buckets = [...counts].map(([key, count]) => {
    const [weekday, hour] = key.split("-").map(Number);
    return { weekday, hour, count, exposureHours: exposure, ...poissonInterval(count, exposure) };
  });
  const ascending = [...buckets].sort((a, b) => a.rate - b.rate || a.high - b.high);
  const descending = [...buckets].sort((a, b) => b.rate - a.rate || b.high - a.high);
  return {
    timezone,
    earliest: new Date(earliest).toISOString(),
    latest: new Date(now).toISOString(),
    observedDays,
    incidents: incidents.length,
    buckets,
    best: ascending,
    worst: descending,
  };
}

function rate(value) {
  return value.toFixed(5);
}

export function markdown(report, top = 10) {
  const rows = (buckets) => buckets.slice(0, top).map((bucket, index) => (
    `| ${index + 1} | ${DAY_NAMES[bucket.weekday]} | ${String(bucket.hour).padStart(2, "0")}:00 | `
    + `${bucket.count} | ${rate(bucket.rate)} | [${rate(bucket.low)}, ${rate(bucket.high)}] | `
    + `${bucket.method} |`
  )).join("\n");
  return `# opusbreak incident analysis

Observation: ${report.earliest} → ${report.latest} (${report.observedDays.toFixed(2)} days), `
    + `${report.incidents} incidents, timezone ${report.timezone}.

## Lowest observed rates

| Rank | Day | Hour | N | rate/hour | 95% interval | method |
|---:|---|---:|---:|---:|---|---|
${rows(report.best)}

## Highest observed rates

| Rank | Day | Hour | N | rate/hour | 95% interval | method |
|---:|---|---:|---:|---:|---|---|
${rows(report.worst)}

The 168 rankings are descriptive. They are not individually significant after
multiple-comparison correction.
`;
}

export async function fetchIncidents() {
  const url = "https://status.claude.com/api/v2/incidents.json";
  const response = await fetch(url, {
    headers: { "User-Agent": "opusbreak/2 (+github.com/ANcpLua/human-plugins)" },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status} fetching ${url}`);
  const body = await response.json();
  if (!Array.isArray(body.incidents)) throw new TypeError("incident response is invalid");
  return body.incidents;
}
