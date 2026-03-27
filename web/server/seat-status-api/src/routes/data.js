import { readFile } from 'node:fs/promises';
import { existsSync, statSync } from 'node:fs';
import { resolve } from 'node:path';

export function registerDataRoutes(app, context) {
  const {
    config,
    seatMapCache,
    seatStatusSubscribers,
    coursePrerequisitesCache,
    calendarCache,
    ramadanCache,
    allSectionsCache,
    sectionDetailsCache,
    staffByInitialCache,
    currentServiceStatus,
    getSeatMap,
    replyFromSnapshot,
    startSeatStreamLoop,
    sendSse,
    sanitizeInitial,
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
  } = context;
  const scraperFiles = new Map([
    ['announcements', ['announcements.json']],
    ['academic-dates', ['academic_dates.json']],
    ['news', ['news.json']],
    ['people', ['people.json']],
    ['transport', ['transport.json']],
    ['students', ['students.json']],
  ]);

  function resolveScraperJsonPath(slug) {
    const safeSlug = `${slug || ''}`.trim().replace(/^\/+|\/+$/g, '');
    const fileNames = scraperFiles.get(safeSlug);
    if (!fileNames) return null;
    const baseDir = resolve(config.scraperDataDir);
    const localScraperDir = resolve(process.cwd(), 'scraper');

    const candidates = [];
    for (const fileName of fileNames) {
      candidates.push(resolve(baseDir, fileName));
      candidates.push(resolve(localScraperDir, 'data', fileName));
    }

    if (safeSlug === 'students') {
      candidates.push(resolve(baseDir, '..', 'pdf', 'FYAT', 'students.json'));
      candidates.push(resolve(localScraperDir, 'pdf', 'FYAT', 'students.json'));
    }

    for (const filePath of candidates) {
      if (existsSync(filePath)) return filePath;
    }

    return candidates[0] || null;
  }

  async function replyWithJsonFile(reply, filePath) {
    if (!existsSync(filePath)) {
      return reply.code(404).send({ error: 'File not found' });
    }
    const body = await readFile(filePath, 'utf8');
    const mtime = statSync(filePath).mtime.toUTCString();
    const etag = `W/"${Buffer.from(`${filePath}:${mtime}:${body.length}`).toString('base64')}"`;
    const ifNoneMatch = `${reply.request.headers['if-none-match'] || ''}`.trim();
    const ifModifiedSince = `${reply.request.headers['if-modified-since'] || ''}`.trim();

    if (ifNoneMatch && ifNoneMatch === etag) {
      reply.header('ETag', etag);
      reply.header('Last-Modified', mtime);
      reply.header(
        'Cache-Control',
        'public, max-age=300, s-maxage=86400, stale-while-revalidate=604800, stale-if-error=604800',
      );
      reply.header('Vary', 'Origin');
      return reply.code(304).send();
    }

    if (ifModifiedSince && ifModifiedSince === mtime) {
      reply.header('ETag', etag);
      reply.header('Last-Modified', mtime);
      reply.header(
        'Cache-Control',
        'public, max-age=300, s-maxage=86400, stale-while-revalidate=604800, stale-if-error=604800',
      );
      reply.header('Vary', 'Origin');
      return reply.code(304).send();
    }

    reply.header('Content-Type', 'application/json; charset=utf-8');
    reply.header(
      'Cache-Control',
      'public, max-age=300, s-maxage=86400, stale-while-revalidate=604800, stale-if-error=604800',
    );
    reply.header('Last-Modified', mtime);
    reply.header('ETag', etag);
    reply.header('Vary', 'Origin');
    return reply.send(body);
  }

  app.get('/', async () => ({
    ok: true,
    ts: new Date().toISOString(),
    status: currentServiceStatus(),
    sseConnections: seatStatusSubscribers.size,
    endpoints: [
      '/data/announcements',
      '/data/academic-dates',
      '/data/news',
      '/data/people',
      '/data/transport',
      '/data/students',
      '/seat-status',
      '/seat-status/stream',
      '/push/device/register',
      '/push/device/unregister',
      '/push/seat-alerts',
      '/push/seat-alerts/:sectionId',
      '/web-login/session',
      '/web-login/session/:id',
      '/web-login/session/:id/approve',
      '/web-login/session/:id/consume',
      '/web-login/active/:id',
      '/web-login/sessions/list',
      '/web-login/sessions/revoke',
      '/web-login/sessions/revoke-all',
      '/sections/:sectionId/details',
      '/sections/details/',
      '/staff/:initial',
      '/course-prerequisites',
      '/holiday',
      '/ramadan',
    ],
  }));

  app.get('/health', async () => ({
    ok: true,
    ts: new Date().toISOString(),
    status: currentServiceStatus(),
  }));

  app.get('/seat-status', async (req, reply) => {
    try {
      if (!seatMapCache.value) await getSeatMap();
      return replyFromSnapshot(
        req,
        reply,
        Math.floor(config.seatMapTtlMs / 1000),
        seatMapCache,
      );
    } catch (error) {
      req.log.error({ error }, 'seat status fetch failed');
      return reply.code(502).send({ error: 'Upstream seat status failed' });
    }
  });

  app.get('/data/:slug', async (req, reply) => {
    const filePath = resolveScraperJsonPath(req.params.slug);
    if (!filePath) {
      return reply.code(404).send({ error: 'File not found' });
    }
    return replyWithJsonFile(reply, filePath);
  });


  app.get('/seat-status/stream', async (req, reply) => {
    reply.hijack();
    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    reply.raw.write(': connected\n\n');

    seatStatusSubscribers.add(reply);
    startSeatStreamLoop();

    const heartbeat = setInterval(() => {
      if (reply.raw.destroyed || reply.raw.writableEnded) {
        clearInterval(heartbeat);
        return;
      }
      reply.raw.write(': ping\n\n');
    }, 25_000);

    try {
      const seatMap = await getSeatMap({ maxAgeMs: config.seatStreamPollMs });
      context.setSeatStreamLastHash(seatMapCache.serialized);
      sendSse(reply, 'seat-status', seatMap);
    } catch (error) {
      app.log.error({ error }, 'initial seat stream push failed');
    }

    req.raw.on('close', () => {
      clearInterval(heartbeat);
      seatStatusSubscribers.delete(reply);
    });
  });

  app.get('/connect/*', async (req, reply) => {
    const rawPath = `${req.params['*'] || ''}`.trim().replace(/^\/+/, '');
    if (!rawPath) {
      return reply.code(400).send({ error: 'Missing upstream path' });
    }

    const authHeader = `${req.headers.authorization || ''}`.trim();
    if (!authHeader.toLowerCase().startsWith('bearer ')) {
      return reply.code(401).send({ error: 'Missing bearer token' });
    }

    const upstreamUrl = new URL(`${config.connectApiBase}/${rawPath}`);
    for (const [key, value] of Object.entries(req.query || {})) {
      if (value === undefined || value === null) continue;
      if (Array.isArray(value)) {
        for (const item of value) {
          upstreamUrl.searchParams.append(key, `${item}`);
        }
      } else {
        upstreamUrl.searchParams.append(key, `${value}`);
      }
    }

    const upstreamHeaders = {
      Authorization: authHeader,
      'X-REALM': `${req.headers['x-realm'] || config.realm}`.trim() || config.realm,
      Accept: `${req.headers.accept || 'application/json'}`.trim() || 'application/json',
    };

    const ifNoneMatch = `${req.headers['if-none-match'] || ''}`.trim();
    if (ifNoneMatch) upstreamHeaders['If-None-Match'] = ifNoneMatch;

    const sourceHeader = `${req.headers['x-source'] || ''}`.trim();
    if (sourceHeader) upstreamHeaders['X-SOURCE'] = sourceHeader;

    try {
      const upstream = await fetch(upstreamUrl, {
        method: 'GET',
        headers: upstreamHeaders,
      });

      const bytes = Buffer.from(await upstream.arrayBuffer());
      reply.code(upstream.status);

      const passthroughHeaders = [
        'content-type',
        'content-length',
        'content-disposition',
        'etag',
        'last-modified',
        'cache-control',
      ];
      for (const headerName of passthroughHeaders) {
        const value = upstream.headers.get(headerName);
        if (value) {
          reply.header(headerName, value);
        }
      }
      reply.header('Vary', 'Origin');
      return reply.send(bytes);
    } catch (error) {
      req.log.error({ error, path: rawPath }, 'connect proxy failed');
      return reply.code(502).send({ error: 'Upstream connect proxy failed' });
    }
  });

  app.get('/course-prerequisites', async (req, reply) => {
    const payload = await getCoursePrerequisites(req.query);
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(req.query || {})) {
      if (value === undefined || value === null) continue;
      const text = `${value}`.trim();
      if (!text) continue;
      params.set(key, text);
    }
    if (!params.has('offset')) params.set('offset', '0');
    if (!params.has('limit')) params.set('limit', '10000');

    const cached = coursePrerequisitesCache.get(params.toString());
    if (!cached) return payload;
    return replyFromSnapshot(
      req,
      reply,
      Math.floor(config.prerequisitesTtlMs / 1000),
      cached,
    );
  });

  app.get('/holiday', async (req, reply) => {
    const query = req.query || {};
    const rawYear = Number(query.year);
    const year = Number.isInteger(rawYear) && rawYear > 2000 ? rawYear : currentUtcYear();
    const startDate = `${query.startDate || ''}`.trim();
    const endDate = `${query.endDate || ''}`.trim();
    const weekOf =
      `${query.weekOf || query.date || ''}`.trim() || formatIsoDateUtc(new Date());

    let range;
    let mode = 'year';

    if (startDate || endDate) {
      if (!isIsoDateString(startDate) || !isIsoDateString(endDate)) {
        return reply
          .code(400)
          .send({ error: 'startDate and endDate must be YYYY-MM-DD' });
      }
      if (startDate > endDate) {
        return reply.code(400).send({ error: 'startDate must be before endDate' });
      }
      range = { startDate, endDate };
      mode = 'range';
    } else if (`${query.week || ''}`.trim() || `${query.weekly || ''}`.trim() || query.weekOf || query.date) {
      range = weekDateRange(weekOf);
      if (!range) {
        return reply.code(400).send({ error: 'weekOf/date must be YYYY-MM-DD' });
      }
      mode = 'week';
    } else {
      range = yearDateRange(year);
    }

    try {
      const payload = await getCalendarRange(range);
      const cached = calendarCache.get(`${range.startDate}|${range.endDate}`);
      if (!cached) return payload;
      return replyFromSnapshot(
        req,
        reply,
        Math.floor(config.calendarTtlMs / 1000),
        cached,
      );
    } catch (error) {
      req.log.error({ error, range, mode }, 'calendar fetch failed');
      return reply.code(502).send({ error: 'Upstream calendar fetch failed' });
    }
  });

  app.get('/ramadan', async (req, reply) => {
    try {
      const payload = await getRamadanStatus();
      if (!ramadanCache.value) return payload;
      return replyFromSnapshot(
        req,
        reply,
        Math.floor(config.ramadanTtlMs / 1000),
        ramadanCache,
      );
    } catch (error) {
      req.log.error({ error }, 'ramadan fetch failed');
      return reply.code(502).send({ error: 'Upstream ramadan fetch failed' });
    }
  });

  app.get('/sections/:sectionId/details', async (req, reply) => {
    const sectionId = Number(req.params.sectionId);
    if (!Number.isFinite(sectionId) || sectionId <= 0) {
      return reply.code(400).send({ error: 'Invalid sectionId' });
    }

    try {
      const payload = await getSectionDetails(sectionId);
      const cached = sectionDetailsCache.get(String(sectionId));
      if (!cached) return payload;
      return replyFromSnapshot(
        req,
        reply,
        Math.floor(config.detailsTtlMs / 1000),
        cached,
      );
    } catch (error) {
      req.log.error({ error, sectionId }, 'section details fetch failed');
      return reply.code(502).send({ error: 'Upstream section details failed' });
    }
  });

  app.get('/sections/details', async (req, reply) => {
    try {
      const payload = await getAllSectionsBundle();
      if (!allSectionsCache.value) return payload;
      return replyFromSnapshot(
        req,
        reply,
        Math.floor(config.seatMapTtlMs / 1000),
        allSectionsCache,
      );
    } catch (error) {
      req.log.error(
        { error: formatErrorForLog(error) },
        'all sections bundle fetch failed',
      );
      return reply.code(502).send({ error: 'Upstream sections bundle failed' });
    }
  });

  app.get('/staff/:initial', async (req, reply) => {
    const initial = sanitizeInitial(req.params.initial);
    if (!initial) return reply.code(400).send({ error: 'Invalid initial' });

    try {
      const staff = await getStaffByInitial(initial);
      if (!staff) return reply.code(404).send({ error: 'Staff not found' });
      const cached = staffByInitialCache.get(initial);
      if (!cached) return staff;
      return replyFromSnapshot(
        req,
        reply,
        Math.floor(config.staffTtlMs / 1000),
        cached,
      );
    } catch (error) {
      req.log.error({ error, initial }, 'staff by initial fetch failed');
      return reply.code(502).send({ error: 'Upstream staff lookup failed' });
    }
  });
}
