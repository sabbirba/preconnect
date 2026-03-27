import Fastify from 'fastify';
import cors from '@fastify/cors';
import { GoogleAuth } from 'google-auth-library';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { createConfig } from './config.js';
import { createServerState } from './state.js';
import {
  addMinutesToTime,
  currentUtcYear,
  etagFor,
  extractCalendarHolidays,
  formatDateForTimeZone,
  formatIsoDateUtc,
  isIsoDateString,
  normalizeTime,
  randomToken,
  replyFromSnapshot,
  sanitizeEmail,
  sanitizeInitial,
  seatPlural,
  snapshotPayload,
  toSeatNumber,
  weekDateRange,
  yearDateRange,
} from './utils/common.js';
import { registerDataRoutes } from './routes/data.js';
import { registerPushRoutes } from './routes/push.js';
import { registerWebLoginRoutes } from './routes/web-login.js';

const app = Fastify({
  logger: { level: 'warn' },
  routerOptions: { ignoreTrailingSlash: true },
});

const config = createConfig();
const serverState = createServerState({ config, etagFor });
const {
  authState,
  seatMapCache,
  sectionDetailsCache,
  staffByInitialCache,
  coursePrerequisitesCache,
  calendarCache,
  ramadanCache,
  allSectionsCache,
  webLoginSessions,
  webActiveSessions,
  pushState,
  seatStatusSubscribers,
} = serverState;
let { seatAlertLastMap } = serverState;
let { seatStreamLastHash, seatStreamTimer } = serverState;

if (!authState.accessToken && !authState.refreshToken) {
  app.log.warn(
    'No token configured: provide ACCESS_TOKEN or REFRESH_TOKEN env vars',
  );
}

await app.register(cors, { origin: true });

const pushStateFilePath = config.pushStateFilePath;

function currentServiceStatus() {
  if (!authState.accessToken && !authState.refreshToken) return 'degraded';
  if (allSectionsCache.refreshPromise || seatMapCache.refreshPromise) return 'warming';
  if (!seatMapCache.value) return 'cold';
  return 'ready';
}

function formatErrorForLog(error) {
  if (!error) return null;
  if (typeof error === 'string') return { message: error };
  if (!(error instanceof Error)) return error;

  return {
    name: error.name,
    message: error.message,
    stack: error.stack,
    cause:
      error.cause instanceof Error
        ? {
            name: error.cause.name,
            message: error.cause.message,
          }
        : error.cause,
  };
}

function cleanupWebLoginSessions() {
  const now = Date.now();
  for (const [sessionId, session] of webLoginSessions.entries()) {
    if (session.expiresAtMs <= now || session.deleteAtMs <= now) {
      webLoginSessions.delete(sessionId);
    }
  }
}

setInterval(cleanupWebLoginSessions, 15_000).unref();

function cleanupWebActiveSessions() {
  const now = Date.now();
  for (const [webSessionId, session] of webActiveSessions.entries()) {
    const expired = Number(session.sessionExpiresAtMs || 0) > 0
      ? Number(session.sessionExpiresAtMs) <= now
      : false;
    if (expired) {
      webActiveSessions.delete(webSessionId);
    }
  }
}

setInterval(cleanupWebActiveSessions, 60_000).unref();

function hasValidAccessToken() {
  if (!authState.accessToken) return false;
  const skewMs = 30_000;
  return Date.now() + skewMs < authState.accessTokenExpiresAtMs;
}

async function refreshAccessToken() {
  if (!authState.refreshToken) {
    throw new Error('Missing refresh token; cannot refresh access token');
  }

  const response = await fetch(config.tokenEndpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: config.clientId,
      refresh_token: authState.refreshToken,
    }),
  });

  const raw = await response.text();
  if (response.status !== 200) {
    throw new Error(`Token refresh failed ${response.status}: ${raw.slice(0, 240)}`);
  }

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch (_) {
    throw new Error('Token refresh returned invalid JSON');
  }

  const nextAccess = `${payload?.access_token || ''}`.trim();
  if (!nextAccess) throw new Error('Token refresh returned empty access_token');

  const nextRefresh = `${payload?.refresh_token || ''}`.trim();
  const expiresInSec = Number(payload?.expires_in || 300);

  authState.accessToken = nextAccess;
  if (nextRefresh) authState.refreshToken = nextRefresh;
  authState.accessTokenExpiresAtMs =
    Date.now() + (Number.isFinite(expiresInSec) ? expiresInSec : 300) * 1000;

  return authState.accessToken;
}

async function getAccessToken({ forceRefresh = false } = {}) {
  if (!forceRefresh && hasValidAccessToken()) return authState.accessToken;

  if (!forceRefresh && authState.accessToken && !authState.refreshToken) {
    // Static access-token mode.
    return authState.accessToken;
  }

  if (authState.refreshInFlight) return authState.refreshInFlight;

  authState.refreshInFlight = refreshAccessToken().finally(() => {
    authState.refreshInFlight = null;
  });
  return authState.refreshInFlight;
}

async function authHeaders({ includeSource = false } = {}) {
  const accessToken = await getAccessToken();
  const headers = {
    Authorization: `Bearer ${accessToken}`,
    'X-REALM': config.realm,
    Accept: 'application/json',
  };
  if (includeSource) headers['X-SOURCE'] = config.source;
  return headers;
}

async function upstreamGet(path, { includeSource = false, accepted = [200] } = {}) {
  const doRequest = async () =>
    fetch(`${config.connectApiBase}${path}`, {
      method: 'GET',
      headers: await authHeaders({ includeSource }),
    });

  let response = await doRequest();
  if (response.status === 401 && authState.refreshToken) {
    await getAccessToken({ forceRefresh: true });
    response = await doRequest();
  }

  if (!accepted.includes(response.status)) {
    const body = await response.text();
    throw new Error(`Upstream ${response.status} ${path} ${body.slice(0, 240)}`);
  }
  return response;
}

async function publicJsonGet(url, { accepted = [200], timeoutMs = 10_000 } = {}) {
  const response = await fetch(url, {
    method: 'GET',
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!accepted.includes(response.status)) {
    const body = await response.text();
    throw new Error(`Public upstream ${response.status} ${url} ${body.slice(0, 240)}`);
  }
  return response;
}

async function upstreamGetWithBearer(
  path,
  bearerToken,
  { includeSource = false, accepted = [200] } = {},
) {
  const token = `${bearerToken || ''}`.trim();
  if (!token) {
    throw new Error('Missing bearer token');
  }
  const headers = {
    Authorization: `Bearer ${token}`,
    'X-REALM': config.realm,
    Accept: 'application/json',
  };
  if (includeSource) headers['X-SOURCE'] = config.source;
  const response = await fetch(`${config.connectApiBase}${path}`, {
    method: 'GET',
    headers,
  });
  if (!accepted.includes(response.status)) {
    const body = await response.text();
    throw new Error(`Upstream ${response.status} ${path} ${body.slice(0, 240)}`);
  }
  return response;
}

function pickStudentIdentityFromProfile(raw) {
  const first = Array.isArray(raw) && raw.length > 0 && raw[0] && typeof raw[0] === 'object'
    ? raw[0]
    : null;
  if (!first) return null;
  const studentId = `${first.studentId || ''}`.trim();
  const studentEmail = sanitizeEmail(first.studentEmail || first.email || '');
  const fullName = `${first.fullName || ''}`.trim();
  if (!studentId) return null;
  return { studentId, studentEmail, fullName };
}

async function getIdentityForAccessToken(accessToken) {
  const response = await upstreamGetWithBearer('/mds/v1/portfolios', accessToken, {
    accepted: [200],
  });
  const raw = await response.json();
  return pickStudentIdentityFromProfile(raw);
}

async function getSeatMap({ force = false, maxAgeMs = config.seatMapTtlMs } = {}) {
  const ageMs = Date.now() - seatMapCache.lastFetchedAt;
  if (!force && seatMapCache.value && ageMs < maxAgeMs) {
    return seatMapCache.value;
  }
  if (seatMapCache.refreshPromise) return seatMapCache.refreshPromise;

  seatMapCache.refreshPromise = (async () => {
    const response = await upstreamGet('/adv/v1/advising/sections/seat-status');
    const raw = await response.json();
    const map = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
    const snapshot = snapshotPayload(map);
    seatMapCache.value = snapshot.value;
    seatMapCache.serialized = snapshot.serialized;
    seatMapCache.etag = snapshot.etag;
    seatMapCache.expiresAt = Date.now() + config.seatMapTtlMs;
    seatMapCache.lastFetchedAt = Date.now();
    return map;
  })().finally(() => {
    seatMapCache.refreshPromise = null;
  });

  return seatMapCache.refreshPromise;
}

async function getSectionDetails(sectionId, { force = false } = {}) {
  const key = String(sectionId);
  const now = Date.now();
  const cached = sectionDetailsCache.get(key);

  if (!force && cached && now < cached.expiresAt && cached.value) {
    return cached.value;
  }
  if (cached?.refreshPromise) return cached.refreshPromise;

  const refreshPromise = (async () => {
    const response = await upstreamGet(
      `/adv/v1/advising/sections/${sectionId}/details`,
    );
    const raw = await response.json();
    const details = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
    const snapshot = snapshotPayload(details);
    sectionDetailsCache.set(key, {
      value: snapshot.value,
      serialized: snapshot.serialized,
      etag: snapshot.etag,
      expiresAt: Date.now() + config.detailsTtlMs,
      refreshPromise: null,
    });
    return snapshot.value;
  })().finally(() => {
    const next = sectionDetailsCache.get(key);
    if (next) next.refreshPromise = null;
  });

  sectionDetailsCache.set(key, {
    value: cached?.value || null,
    serialized: cached?.serialized || 'null',
    etag: cached?.etag || etagFor(null),
    expiresAt: cached?.expiresAt || 0,
    refreshPromise,
  });

  return refreshPromise;
}

async function autocompleteStaff(initial) {
  const q = encodeURIComponent(initial.toLowerCase());
  const response = await upstreamGet(
    `/data/autocomplete?q=${q}&page=1&field_name=staffId&type=staff`,
    { includeSource: true, accepted: [200, 404] },
  );
  if (response.status !== 200) return null;

  const body = await response.json();
  const results = Array.isArray(body?.results) ? body.results : [];
  let fallback = null;

  for (const row of results) {
    const id = Number(row?.id);
    const text = `${row?.text || ''}`.trim();
    if (!Number.isFinite(id) || !text) continue;

    if (!fallback) fallback = { staffId: id };
    const prefix = text.split(' - ')[0]?.trim().toUpperCase() || '';
    if (prefix === initial) return { staffId: id };
  }
  return fallback;
}

async function fetchStaffById(staffId) {
  const response = await upstreamGet(`/adp/v1/staffs/${staffId}`, {
    includeSource: true,
    accepted: [200, 404],
  });
  if (response.status !== 200) return null;

  const body = await response.json();
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  return body;
}

async function getStaffByInitial(initial, { force = false } = {}) {
  const key = sanitizeInitial(initial);
  if (!key) return null;

  const now = Date.now();
  const cached = staffByInitialCache.get(key);
  if (!force && cached && now < cached.expiresAt && cached.value) {
    return cached.value;
  }
  if (cached?.refreshPromise) return cached.refreshPromise;

  const refreshPromise = (async () => {
    const match = await autocompleteStaff(key);
    if (!match?.staffId) return null;

    const staff = await fetchStaffById(match.staffId);
    if (!staff) return null;
    const snapshot = snapshotPayload(staff);
    staffByInitialCache.set(key, {
      value: snapshot.value,
      serialized: snapshot.serialized,
      etag: snapshot.etag,
      expiresAt: Date.now() + config.staffTtlMs,
      refreshPromise: null,
    });
    return snapshot.value;
  })().finally(() => {
    const next = staffByInitialCache.get(key);
    if (next) next.refreshPromise = null;
  });

  staffByInitialCache.set(key, {
    value: cached?.value || null,
    serialized: cached?.serialized || 'null',
    etag: cached?.etag || etagFor(null),
    expiresAt: cached?.expiresAt || 0,
    refreshPromise,
  });

  return refreshPromise;
}

async function getCoursePrerequisites(query = {}, { force = false } = {}) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query || {})) {
    if (value === undefined || value === null) continue;
    const text = `${value}`.trim();
    if (!text) continue;
    params.set(key, text);
  }
  if (!params.has('offset')) params.set('offset', '0');
  if (!params.has('limit')) params.set('limit', '10000');

  const cacheKey = params.toString();
  const now = Date.now();
  const cached = coursePrerequisitesCache.get(cacheKey);
  if (!force && cached && now < cached.expiresAt && cached.value) {
    return cached.value;
  }
  if (cached?.refreshPromise) return cached.refreshPromise;

  const path = `/data/grid/course-prerequisite?${cacheKey}`;
  const refreshPromise = (async () => {
    const response = await upstreamGet(path);
    const raw = await response.json();
    const snapshot = snapshotPayload(raw);
    coursePrerequisitesCache.set(cacheKey, {
      value: snapshot.value,
      serialized: snapshot.serialized,
      etag: snapshot.etag,
      expiresAt: Date.now() + config.prerequisitesTtlMs,
      refreshPromise: null,
    });
    return snapshot.value;
  })().finally(() => {
    const next = coursePrerequisitesCache.get(cacheKey);
    if (next) next.refreshPromise = null;
  });

  coursePrerequisitesCache.set(cacheKey, {
    value: cached?.value || null,
    serialized: cached?.serialized || 'null',
    etag: cached?.etag || etagFor(null),
    expiresAt: cached?.expiresAt || 0,
    refreshPromise,
  });

  return refreshPromise;
}

async function getCalendarRange({ startDate, endDate }, { force = false } = {}) {
  const cacheKey = `${startDate}|${endDate}`;
  const now = Date.now();
  const cached = calendarCache.get(cacheKey);
  if (!force && cached && now < cached.expiresAt && cached.value) {
    return cached.value;
  }
  if (cached?.refreshPromise) return cached.refreshPromise;

  const path =
    `/reg/v1/calendar/0?startDate=${encodeURIComponent(startDate)}` +
    `&endDate=${encodeURIComponent(endDate)}`;

  const refreshPromise = (async () => {
    const response = await upstreamGet(path);
    const raw = await response.json();
    const payload = extractCalendarHolidays(raw);
    const snapshot = snapshotPayload(payload);
    calendarCache.set(cacheKey, {
      value: snapshot.value,
      serialized: snapshot.serialized,
      etag: snapshot.etag,
      expiresAt: Date.now() + config.calendarTtlMs,
      refreshPromise: null,
    });
    return snapshot.value;
  })().finally(() => {
    const next = calendarCache.get(cacheKey);
    if (next) next.refreshPromise = null;
  });

  calendarCache.set(cacheKey, {
    value: cached?.value || null,
    serialized: cached?.serialized || 'null',
    etag: cached?.etag || etagFor(null),
    expiresAt: cached?.expiresAt || 0,
    refreshPromise,
  });

  return refreshPromise;
}

async function getRamadanStatus({ force = false } = {}) {
  const now = Date.now();
  const cached = ramadanCache;
  if (!force && cached.value && now < cached.expiresAt) {
    return cached.value;
  }
  if (cached.refreshPromise) return cached.refreshPromise;

  ramadanCache.refreshPromise = (async () => {
    const params = new URLSearchParams({
      city: config.ramadanCity,
      country: config.ramadanCountry,
      method: config.ramadanMethod,
      school: config.ramadanSchool,
    });
    if (config.ramadanState) params.set('state', config.ramadanState);

    const date = formatDateForTimeZone(new Date(), config.ramadanTimeZone);
    const response = await publicJsonGet(
      `https://api.aladhan.com/v1/timingsByCity/${date}?${params.toString()}`,
    );
    const raw = await response.json();
    const data = raw?.data && typeof raw.data === 'object' && !Array.isArray(raw.data)
      ? raw.data
      : null;
    const timings = data?.timings && typeof data.timings === 'object' && !Array.isArray(data.timings)
      ? data.timings
      : {};
    const hijri = data?.date?.hijri && typeof data.date.hijri === 'object'
      ? data.date.hijri
      : {};
    const hijriMonthNumber = Number(hijri?.month?.number);
    const ramadanDayRaw = Number(hijri?.day);
    const adjustedMaghrib = addMinutesToTime(timings.Maghrib, 2);
    const payload = {
      isRamadan: hijriMonthNumber === 9,
      ramadanDay:
        hijriMonthNumber === 9 && Number.isFinite(ramadanDayRaw) ? ramadanDayRaw : null,
      sehriEndsAt: normalizeTime(timings.Imsak) || normalizeTime(timings.Fajr),
      iftarAt: adjustedMaghrib,
    };
    const snapshot = snapshotPayload(payload);
    ramadanCache.value = snapshot.value;
    ramadanCache.serialized = snapshot.serialized;
    ramadanCache.etag = snapshot.etag;
    ramadanCache.expiresAt = Date.now() + config.ramadanTtlMs;
    return snapshot.value;
  })().catch((error) => {
    if (cached?.value) {
      app.log.warn({ error }, 'ramadan upstream failed, serving stale cache');
      return cached.value;
    }
    throw error;
  }).finally(() => {
    ramadanCache.refreshPromise = null;
  });

  return ramadanCache.refreshPromise;
}

async function refreshAllSectionsBundle() {
  if (allSectionsCache.refreshPromise) return allSectionsCache.refreshPromise;

  allSectionsCache.refreshPromise = (async () => {
    const seatMap = await getSeatMap();
    const nextSeatMapHash = seatMapCache.serialized;
    if (allSectionsCache.value && allSectionsCache.seatMapHash === nextSeatMapHash) {
      return allSectionsCache.value;
    }

    const prevSections = allSectionsCache.value || {};
    const prevSeatMap = allSectionsCache.seatMapSnapshot || {};
    const noPrevSections = Object.keys(prevSections).length === 0;

    const nextSectionDetails = { ...prevSections };
    const nextSeatMap = {};

    const changedRows = [];
    for (const [rawSectionId, rawRemaining] of Object.entries(seatMap)) {
      const sectionId = Number(rawSectionId);
      if (!Number.isFinite(sectionId) || sectionId <= 0) continue;

      const remainingSeat = toSeatNumber(rawRemaining);
      nextSeatMap[sectionId] = remainingSeat;
      const prevRemainingSeat = toSeatNumber(prevSeatMap[sectionId]);
      const changed = noPrevSections || prevRemainingSeat !== remainingSeat;
      if (!(changed || !nextSectionDetails[sectionId])) {
        continue;
      }
      changedRows.push({ sectionId, force: changed });
    }

    // Resolve details in bounded parallel batches to avoid long cold responses.
    const detailConcurrency = 12;
    for (let i = 0; i < changedRows.length; i += detailConcurrency) {
      const batch = changedRows.slice(i, i + detailConcurrency);
      await Promise.all(
        batch.map(async ({ sectionId, force: forceDetail }) => {
          const details = await getSectionDetails(sectionId, { force: forceDetail });
          nextSectionDetails[sectionId] = details;
        }),
      );
    }

    for (const rawSectionId of Object.keys(nextSectionDetails)) {
      if (Object.prototype.hasOwnProperty.call(nextSeatMap, rawSectionId)) continue;
      delete nextSectionDetails[rawSectionId];
    }

    const bundle = nextSectionDetails;
    const snapshot = snapshotPayload(bundle);

    allSectionsCache.value = snapshot.value;
    allSectionsCache.serialized = snapshot.serialized;
    allSectionsCache.etag = snapshot.etag;
    allSectionsCache.seatMapHash = nextSeatMapHash;
    allSectionsCache.seatMapSnapshot = nextSeatMap;
    allSectionsCache.builtAtMs = Date.now();
    return snapshot.value;
  })().catch((error) => {
    if (allSectionsCache.value) {
      app.log.warn(
        {
          error: formatErrorForLog(error),
          builtAtMs: allSectionsCache.builtAtMs || null,
        },
        'all sections bundle upstream failed, serving stale cache',
      );
      return allSectionsCache.value;
    }
    throw error;
  }).finally(() => {
    allSectionsCache.refreshPromise = null;
  });

  return allSectionsCache.refreshPromise;
}

function scheduleAllSectionsRefresh() {
  if (allSectionsCache.refreshPromise) return;
  void refreshAllSectionsBundle().catch((error) => {
    app.log.error(
      { error: formatErrorForLog(error) },
      'background all sections refresh failed',
    );
  });
}

async function getAllSectionsBundle() {
  if (!allSectionsCache.value) {
    return refreshAllSectionsBundle();
  }
  return allSectionsCache.value;
}

function sendSse(reply, event, payload) {
  if (reply.raw.destroyed || reply.raw.writableEnded) return;
  reply.raw.write(`event: ${event}\n`);
  reply.raw.write(`data: ${seatMapCache.serialized}\n\n`);
}

function startSeatStreamLoop() {
  if (seatStreamTimer) return;

  seatStreamTimer = setInterval(async () => {
    const shouldKeepRunning =
      seatStatusSubscribers.size > 0 || pushState.subscriptions.size > 0;
    if (!shouldKeepRunning) {
      clearInterval(seatStreamTimer);
      seatStreamTimer = null;
      return;
    }

    try {
      const seatMap = await getSeatMap({ maxAgeMs: config.seatStreamPollMs });
      const nextHash = seatMapCache.serialized;
      if (nextHash === seatStreamLastHash) return;

      const previousSeatMap = seatAlertLastMap;
      seatAlertLastMap = { ...(seatMap || {}) };
      void processSeatAlertTriggers(previousSeatMap, seatMap).catch((error) => {
        app.log.error({ error }, 'seat alert push processing failed');
      });

      seatStreamLastHash = nextHash;
      if (allSectionsCache.seatMapHash !== nextHash) {
        scheduleAllSectionsRefresh();
      }
      for (const reply of seatStatusSubscribers) {
        sendSse(reply, 'seat-status', seatMap);
      }
    } catch (error) {
      app.log.error({ error }, 'seat stream poll failed');
    }
  }, Math.max(1000, config.seatStreamPollMs));
}

function createWebLoginSession(studentEmail) {
  const sessionId = randomToken(18);
  const sessionToken = randomToken(24);
  const nonce = randomToken(18);
  const expiresAtMs = Date.now() + config.webLoginTtlMs;
  const session = {
    sessionId,
    sessionToken,
    studentEmail,
    nonce,
    status: 'pending',
    createdAtMs: Date.now(),
    expiresAtMs,
    deleteAtMs: Date.now() + config.webLoginSessionMaxMs,
    approvedPayload: null,
  };
  webLoginSessions.set(sessionId, session);
  return session;
}

function createActiveWebSession({ approvedPayload, userAgent }) {
  const webSessionId = randomToken(18);
  const webSessionToken = randomToken(24);
  const now = Date.now();
  const sessionExpiresAtMs = Number(approvedPayload?.sessionExpiresAt || 0) > now
    ? Number(approvedPayload.sessionExpiresAt)
    : now + 30 * 24 * 60 * 60 * 1000;
  const session = {
    webSessionId,
    webSessionToken,
    studentId: `${approvedPayload?.studentId || ''}`.trim(),
    studentEmail: sanitizeEmail(approvedPayload?.studentEmail || ''),
    accessToken: `${approvedPayload?.accessToken || ''}`.trim(),
    refreshToken: `${approvedPayload?.refreshToken || ''}`.trim(),
    createdAtMs: now,
    lastSeenAtMs: now,
    sessionExpiresAtMs,
    revokedAtMs: 0,
    revokedReason: '',
    userAgent: `${userAgent || ''}`.trim(),
  };
  webActiveSessions.set(webSessionId, session);
  return session;
}

function maskUserAgent(ua) {
  const text = `${ua || ''}`.trim();
  if (!text) return '';
  if (text.length <= 120) return text;
  return `${text.slice(0, 120)}...`;
}

function sessionPublicDto(session) {
  return {
    webSessionId: session.webSessionId,
    studentId: session.studentId,
    studentEmail: session.studentEmail,
    createdAt: session.createdAtMs,
    lastSeenAt: session.lastSeenAtMs,
    sessionExpiresAt: session.sessionExpiresAtMs,
    userAgent: maskUserAgent(session.userAgent),
  };
}

function verifyActiveWebSession(webSessionId, webSessionToken) {
  cleanupWebActiveSessions();
  const session = webActiveSessions.get(webSessionId);
  if (!session) return { error: 'Session not found', code: 404 };
  if (`${session.webSessionToken || ''}` !== `${webSessionToken || ''}`) {
    return { error: 'Invalid session token', code: 403 };
  }
  if (Number(session.sessionExpiresAtMs || 0) <= Date.now()) {
    return { error: 'Session expired', code: 410 };
  }
  return { session };
}

async function ensurePushStateLoaded() {
  if (pushState.loaded) return;
  await mkdir(config.dataDir, { recursive: true });
  try {
    const raw = await readFile(pushStateFilePath, 'utf8');
    const parsed = JSON.parse(raw);
    const devices = Array.isArray(parsed?.devices) ? parsed.devices : [];
    const subscriptions = Array.isArray(parsed?.subscriptions)
      ? parsed.subscriptions
      : [];
    for (const item of devices) {
      const token = `${item?.token || ''}`.trim();
      if (!token) continue;
      pushState.devices.set(token, {
        token,
        studentId: `${item?.studentId || ''}`.trim(),
        studentEmail: sanitizeEmail(item?.studentEmail || ''),
        platform: `${item?.platform || ''}`.trim().toLowerCase(),
        locale: `${item?.locale || ''}`.trim(),
        appVersion: `${item?.appVersion || ''}`.trim(),
        lastSeenAt: Number(item?.lastSeenAt || 0) || Date.now(),
      });
    }
    for (const item of subscriptions) {
      const token = `${item?.token || ''}`.trim();
      const studentId = `${item?.studentId || ''}`.trim();
      const sectionId = Number(item?.sectionId);
      if (!token || !studentId || !Number.isFinite(sectionId) || sectionId <= 0) {
        continue;
      }
      pushState.subscriptions.set(`${studentId}:${token}:${sectionId}`, {
        token,
        studentId,
        studentEmail: sanitizeEmail(item?.studentEmail || ''),
        sectionId,
        rules: item?.rules && typeof item.rules === 'object' ? item.rules : {},
        lastTriggeredAt: item?.lastTriggeredAt && typeof item.lastTriggeredAt === 'object'
          ? item.lastTriggeredAt
          : {},
      });
    }
  } catch (_) {}
  pushState.loaded = true;
}

async function persistPushState() {
  await ensurePushStateLoaded();
  const payload = {
    devices: Array.from(pushState.devices.values()),
    subscriptions: Array.from(pushState.subscriptions.values()),
  };
  const next = async () => {
    const tempPath = `${pushStateFilePath}.tmp`;
    await writeFile(tempPath, JSON.stringify(payload, null, 2), 'utf8');
    await rename(tempPath, pushStateFilePath);
  };
  pushState.persistPromise = (pushState.persistPromise || Promise.resolve())
    .then(next)
    .catch(() => next());
  return pushState.persistPromise;
}

async function getRequestIdentity(req) {
  const authHeader = `${req.headers.authorization || ''}`.trim();
  if (!authHeader.toLowerCase().startsWith('bearer ')) {
    return null;
  }
  const accessToken = authHeader.slice(7).trim();
  if (!accessToken) return null;
  try {
    return await getIdentityForAccessToken(accessToken);
  } catch (_) {
    return null;
  }
}

function normalizeSeatAlertRules(input = {}) {
  const output = {};
  if (input.available && typeof input.available === 'object') {
    output.available = {
      oneTime: input.available.oneTime !== false,
    };
  }
  const minSeats = Number(input?.threshold?.minSeats);
  if (Number.isFinite(minSeats) && minSeats > 0) {
    output.threshold = {
      minSeats,
      oneTime: input.threshold.oneTime !== false,
    };
  }
  const cooldownMinutes = Number(input?.changed?.cooldownMinutes);
  if (input.changed && typeof input.changed === 'object') {
    output.changed = {
      cooldownMinutes:
        Number.isFinite(cooldownMinutes) && cooldownMinutes >= 0
          ? cooldownMinutes
          : 0,
    };
  }
  return output;
}

function hasSeatAlertRules(rules = {}) {
  return Boolean(rules.available || rules.threshold || rules.changed);
}

function seatAlertSubscriptionKey(studentId, token, sectionId) {
  return `${studentId}:${token}:${sectionId}`;
}

function deriveCourseLabel(details, sectionId) {
  const courseCode = `${details?.courseCode || ''}`.trim();
  const sectionName = `${details?.sectionName || ''}`.trim();
  if (courseCode && sectionName) return `${courseCode}-${sectionName}`;
  if (courseCode) return courseCode;
  if (sectionName) return `Section ${sectionName}`;
  return `Section ${sectionId}`;
}

async function getFcmAccessToken() {
  if (!config.pushEnabled) return null;
  if (!pushState.auth) {
    let rawCredentials = config.fcmServiceAccountJson;
    if (!rawCredentials && config.fcmServiceAccountFile) {
      rawCredentials = await readFile(config.fcmServiceAccountFile, 'utf8');
    }
    if (!rawCredentials) return null;
    const credentials = JSON.parse(rawCredentials);
    pushState.auth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });
  }
  const client = await pushState.auth.getClient();
  const tokenResponse = await client.getAccessToken();
  return `${tokenResponse?.token || tokenResponse || ''}`.trim() || null;
}

async function sendSeatAlertPush(token, message) {
  const accessToken = await getFcmAccessToken();
  if (!accessToken) return false;
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(config.fcmProjectId)}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: message.title,
            body: message.body,
          },
          data: {
            kind: 'seat_alert',
            sectionId: `${message.sectionId}`,
            title: message.title,
            body: message.body,
            source: 'fcm',
          },
          android: {
            priority: 'high',
            notification: {
              channel_id: 'seat_alerts',
            },
          },
          apns: {
            headers: {
              'apns-priority': '10',
            },
            payload: {
              aps: {
                sound: 'default',
              },
            },
          },
        },
      }),
    },
  );
  return response.ok;
}

async function processSeatAlertTriggers(previousSeatMap, nextSeatMap) {
  await ensurePushStateLoaded();
  if (!config.pushEnabled || pushState.subscriptions.size === 0) return;
  const now = Date.now();
  const sectionIds = new Set([
    ...Object.keys(previousSeatMap || {}),
    ...Object.keys(nextSeatMap || {}),
  ]);

  for (const rawSectionId of sectionIds) {
    const sectionId = Number(rawSectionId);
    if (!Number.isFinite(sectionId) || sectionId <= 0) continue;
    const oldRemaining = toSeatNumber(previousSeatMap?.[sectionId]);
    const newRemaining = toSeatNumber(nextSeatMap?.[sectionId]);
    if (oldRemaining === newRemaining) continue;

    const matching = Array.from(pushState.subscriptions.values()).filter(
      (subscription) => subscription.sectionId === sectionId,
    );
    if (matching.length === 0) continue;

    let details = null;
    try {
      details = allSectionsCache.value?.[sectionId] || await getSectionDetails(sectionId);
    } catch (_) {}
    const courseLabel = deriveCourseLabel(details, sectionId);

    for (const subscription of matching) {
      let changed = false;
      const rules = subscription.rules || {};
      const messages = [];

      if (rules.available && oldRemaining <= 0 && newRemaining > 0) {
        messages.push({
          title: 'Seat Available',
          body: `${courseLabel} now has ${newRemaining} ${seatPlural(newRemaining)} available`,
        });
        if (rules.available.oneTime !== false) {
          delete rules.available;
          changed = true;
        }
      }

      const threshold = Number(rules?.threshold?.minSeats);
      if (Number.isFinite(threshold) && oldRemaining < threshold && newRemaining >= threshold) {
        messages.push({
          title: 'Seat Threshold Reached',
          body: `${courseLabel} reached ${newRemaining} available ${seatPlural(newRemaining)}`,
        });
        if (rules.threshold.oneTime !== false) {
          delete rules.threshold;
          changed = true;
        }
      }

      if (rules.changed) {
        const cooldownMinutes = Number(rules.changed.cooldownMinutes);
        const lastAt = Number(subscription?.lastTriggeredAt?.changed || 0);
        if (!Number.isFinite(cooldownMinutes) || now - lastAt >= cooldownMinutes * 60 * 1000) {
          messages.push({
            title: 'Seat Count Changed',
            body: `${courseLabel} changed to ${newRemaining} available ${seatPlural(newRemaining)}`,
          });
          subscription.lastTriggeredAt.changed = now;
          changed = true;
        }
      }

      if (messages.length > 0 && pushState.devices.has(subscription.token)) {
        const sent = await sendSeatAlertPush(subscription.token, {
          ...messages[0],
          sectionId,
        });
        if (sent) {
          if (!subscription.lastTriggeredAt) subscription.lastTriggeredAt = {};
          subscription.lastTriggeredAt.sent = now;
        }
      }

      subscription.rules = normalizeSeatAlertRules(rules);
      if (!hasSeatAlertRules(subscription.rules)) {
        pushState.subscriptions.delete(
          seatAlertSubscriptionKey(subscription.studentId, subscription.token, sectionId),
        );
        changed = true;
      } else if (changed) {
        pushState.subscriptions.set(
          seatAlertSubscriptionKey(subscription.studentId, subscription.token, sectionId),
          subscription,
        );
      }
    }
  }

  await persistPushState();
}

function getVerifiedWebLoginSession(sessionId, sessionToken) {
  cleanupWebLoginSessions();
  const session = webLoginSessions.get(sessionId);
  if (!session) return { error: 'Session not found', code: 404 };
  if (session.sessionToken !== sessionToken) {
    return { error: 'Invalid session token', code: 403 };
  }
  if (Date.now() > session.expiresAtMs || session.status === 'expired') {
    session.status = 'expired';
    session.deleteAtMs = Date.now();
    webLoginSessions.set(sessionId, session);
    return { error: 'Session expired', code: 410 };
  }
  return { session };
}

const routeContext = {
  app,
  config,
  seatMapCache,
  seatStatusSubscribers,
  coursePrerequisitesCache,
  calendarCache,
  ramadanCache,
  allSectionsCache,
  sectionDetailsCache,
  staffByInitialCache,
  pushState,
  webLoginSessions,
  webActiveSessions,
  currentServiceStatus,
  getRequestIdentity,
  ensurePushStateLoaded,
  persistPushState,
  startSeatStreamLoop,
  normalizeSeatAlertRules,
  hasSeatAlertRules,
  seatAlertSubscriptionKey,
  sanitizeEmail,
  sanitizeInitial,
  createWebLoginSession,
  getVerifiedWebLoginSession,
  createActiveWebSession,
  verifyActiveWebSession,
  getIdentityForAccessToken,
  cleanupWebActiveSessions,
  sessionPublicDto,
  getSeatMap,
  replyFromSnapshot,
  sendSse,
  setSeatStreamLastHash(value) {
    seatStreamLastHash = value;
  },
  getCoursePrerequisites,
  getCalendarRange,
  currentUtcYear,
  formatIsoDateUtc,
  isIsoDateString,
  weekDateRange,
  yearDateRange,
  getRamadanStatus,
  getSectionDetails,
  getAllSectionsBundle,
  getStaffByInitial,
  formatErrorForLog,
};

registerPushRoutes(app, routeContext);
registerWebLoginRoutes(app, routeContext);
registerDataRoutes(app, routeContext);

app.setErrorHandler((error, req, reply) => {
  req.log.error({ error: formatErrorForLog(error) }, 'request failed');
  reply.code(500).send({ error: 'Internal server error' });
});

ensurePushStateLoaded()
  .then(() => {
    if (pushState.subscriptions.size > 0) {
      startSeatStreamLoop();
    }
  })
  .catch((error) => {
    app.log.error({ error }, 'failed to load push state');
  });

app.listen({ port: config.port, host: '0.0.0.0' }).catch((error) => {
  app.log.error({ error }, 'failed to start');
  process.exit(1);
});
