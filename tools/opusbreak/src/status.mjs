import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export const STATUS_URL = "https://status.claude.com/api/v2/summary.json";
export const RELEVANT_COMPONENTS = new Set(["k8w3r06qmzrp", "yyzkbfz2thpt"]);
export const DEFAULT_CACHE = join(homedir(), ".local", "state", "human-plugins", "opusbreak.json");

export function normalizeSummary(body, elapsedMs, polledAt = new Date().toISOString()) {
  if (!body?.status || !Array.isArray(body.components)) {
    throw new TypeError("StatusPage response is missing status or components");
  }
  return {
    polledAt,
    elapsedMs,
    source: STATUS_URL,
    indicator: body.status.indicator,
    description: body.status.description,
    components: body.components
      .filter((component) => RELEVANT_COMPONENTS.has(component.id))
      .map(({ id, name, status, updated_at }) => ({ id, name, status, updated_at })),
    incidents: (body.incidents ?? []).map(
      ({ id, name, status, impact, created_at, updated_at, shortlink }) => ({
        id,
        name,
        status,
        impact,
        created_at,
        updated_at,
        shortlink,
      }),
    ),
    maintenances: (body.scheduled_maintenances ?? []).map(
      ({ id, name, status, scheduled_for, scheduled_until }) => ({
        id,
        name,
        status,
        scheduled_for,
        scheduled_until,
      }),
    ),
  };
}

export function degraded(cache) {
  return cache.indicator !== "none"
    || cache.components.some((component) => component.status !== "operational")
    || cache.incidents.length > 0
    || cache.maintenances.some((maintenance) => maintenance.status === "in_progress");
}

export function renderStatusline(cache, now = Date.now()) {
  const ageMinutes = (now - new Date(cache.polledAt).getTime()) / 60_000;
  const color = {
    red: "\x1b[31m",
    yellow: "\x1b[33m",
    magenta: "\x1b[35m",
    grey: "\x1b[90m",
    reset: "\x1b[0m",
  };
  if (!Number.isFinite(ageMinutes) || ageMinutes > 30) {
    const age = Number.isFinite(ageMinutes) ? ageMinutes.toFixed(0) : "unknown";
    return `${color.grey}⌛ stale ${age}m${color.reset}`;
  }
  if (!degraded(cache)) return "";

  const names = { k8w3r06qmzrp: "API", yyzkbfz2thpt: "Code" };
  const flagged = cache.components
    .filter((component) => component.status !== "operational")
    .map((component) => `${names[component.id] ?? component.name}=${component.status}`);
  const maintenance = cache.maintenances.some((item) => item.status === "in_progress");
  const parts = flagged.length ? [flagged.join(",")] : [cache.indicator];
  if (cache.incidents.length) {
    parts.push(`${cache.incidents.length} incident${cache.incidents.length === 1 ? "" : "s"}`);
  }
  if (maintenance) parts.push("maintenance");
  const major = cache.indicator === "major"
    || flagged.some((item) => item.includes("major_outage"));
  const palette = major ? color.red : maintenance ? color.magenta : color.yellow;
  const icon = major ? "🔴" : maintenance ? "🔧" : "🟡";
  return `${icon} ${palette}${parts.join(" · ")}${color.reset}`;
}

export function renderAdvisory(cache, now = Date.now()) {
  const ageMinutes = (now - new Date(cache.polledAt).getTime()) / 60_000;
  if (!degraded(cache) && ageMinutes <= 30) return "";
  const lines = [];
  if (!Number.isFinite(ageMinutes) || ageMinutes > 30) {
    lines.push(`opusbreak: status cache is ${Number.isFinite(ageMinutes) ? ageMinutes.toFixed(0) : "unknown"} min old`);
  }
  if (cache.indicator !== "none" || cache.components.some((item) => item.status !== "operational")) {
    lines.push(`opusbreak: Anthropic status is ${cache.indicator} (${cache.description})`);
    for (const component of cache.components.filter((item) => item.status !== "operational")) {
      lines.push(`- ${component.name}: ${component.status}`);
    }
  }
  for (const incident of cache.incidents.slice(0, 5)) {
    lines.push(`- [${incident.impact}] ${incident.name}: ${incident.status}`);
  }
  return lines.join("\n");
}

export async function readCache(path = process.env.OPUSBREAK_CACHE || DEFAULT_CACHE) {
  return JSON.parse(await readFile(path, "utf8"));
}

export async function writeCache(cache, path = process.env.OPUSBREAK_CACHE || DEFAULT_CACHE) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.${process.pid}.tmp`;
  await writeFile(temporary, `${JSON.stringify(cache, null, 2)}\n`, { mode: 0o600 });
  await rename(temporary, path);
}

export async function poll(path = process.env.OPUSBREAK_CACHE || DEFAULT_CACHE) {
  const started = Date.now();
  const response = await fetch(STATUS_URL, {
    headers: { "User-Agent": "opusbreak/2 (+github.com/ANcpLua/human-plugins)" },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status} fetching ${STATUS_URL}`);
  const cache = normalizeSummary(await response.json(), Date.now() - started);
  await writeCache(cache, path);
  return cache;
}
