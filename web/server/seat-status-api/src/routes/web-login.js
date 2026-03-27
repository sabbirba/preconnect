export function registerWebLoginRoutes(app, context) {
  const {
    config,
    webActiveSessions,
    webLoginSessions,
    sanitizeEmail,
    createWebLoginSession,
    getVerifiedWebLoginSession,
    createActiveWebSession,
    verifyActiveWebSession,
    getIdentityForAccessToken,
    cleanupWebActiveSessions,
    sessionPublicDto,
  } = context;

  app.post('/web-login/session', async (req, reply) => {
    const requestedEmail = sanitizeEmail(req.body?.studentEmail);
    const studentEmail = requestedEmail.includes('@') ? requestedEmail : '';

    const session = createWebLoginSession(studentEmail);
    return reply.send({
      sessionId: session.sessionId,
      sessionToken: session.sessionToken,
      studentEmail: session.studentEmail,
      nonce: session.nonce,
      status: session.status,
      expiresAt: session.expiresAtMs,
    });
  });

  app.get('/web-login/session/:sessionId', async (req, reply) => {
    const sessionId = `${req.params.sessionId || ''}`.trim();
    const sessionToken = `${req.query?.sessionToken || ''}`.trim();
    if (!sessionId || !sessionToken) {
      return reply.code(400).send({ error: 'sessionId and sessionToken are required' });
    }

    const verified = getVerifiedWebLoginSession(sessionId, sessionToken);
    if (verified.error) {
      return reply.code(verified.code).send({
        error: verified.error,
        sessionId,
        status: 'expired',
        approved: false,
        expired: verified.code === 410,
      });
    }

    const { session } = verified;
    return reply.send({
      sessionId: session.sessionId,
      status: session.status,
      approved: session.status === 'approved',
      expired: false,
    });
  });

  app.post('/web-login/session/:sessionId/approve', async (req, reply) => {
    const sessionId = `${req.params.sessionId || ''}`.trim();
    const sessionToken = `${req.body?.sessionToken || ''}`.trim();
    const studentEmail = sanitizeEmail(req.body?.studentEmail);
    const studentId = `${req.body?.studentId || ''}`.trim();
    const accessToken = `${req.body?.accessToken || ''}`.trim();
    const refreshToken = `${req.body?.refreshToken || ''}`.trim();
    const sessionExpiresAt = Number(req.body?.sessionExpiresAt || 0);

    const verified = getVerifiedWebLoginSession(sessionId, sessionToken);
    if (verified.error) {
      return reply.code(verified.code).send({ error: verified.error });
    }
    const { session } = verified;

    if (session.status !== 'pending') {
      return reply.code(409).send({ error: 'Session already used' });
    }
    session.studentEmail = studentEmail || session.studentEmail || '';
    if (!accessToken || !refreshToken) {
      return reply.code(400).send({ error: 'App tokens are required' });
    }
    if (!studentId) {
      return reply.code(400).send({ error: 'studentId is required' });
    }

    session.status = 'approved';
    session.approvedPayload = {
      studentEmail,
      studentId,
      accessToken,
      refreshToken,
      sessionExpiresAt,
    };
    session.deleteAtMs = Date.now() + config.webLoginSessionMaxMs;
    webLoginSessions.set(sessionId, session);
    return reply.send({ ok: true, status: session.status });
  });

  app.post('/web-login/session/:sessionId/consume', async (req, reply) => {
    const sessionId = `${req.params.sessionId || ''}`.trim();
    const sessionToken = `${req.body?.sessionToken || ''}`.trim();
    const verified = getVerifiedWebLoginSession(sessionId, sessionToken);
    if (verified.error) {
      return reply.code(verified.code).send({ error: verified.error });
    }
    const { session } = verified;
    if (session.status !== 'approved' || !session.approvedPayload) {
      return reply.code(409).send({ error: 'Session not approved yet' });
    }
    const activeSession = createActiveWebSession({
      approvedPayload: session.approvedPayload,
      userAgent: req.headers['user-agent'],
    });
    const payload = {
      ...session.approvedPayload,
      webSessionId: activeSession.webSessionId,
      webSessionToken: activeSession.webSessionToken,
    };
    webLoginSessions.delete(sessionId);
    return reply.send(payload);
  });

  app.get('/web-login/active/:webSessionId', async (req, reply) => {
    const webSessionId = `${req.params.webSessionId || ''}`.trim();
    const webSessionToken = `${req.query?.sessionToken || ''}`.trim();
    if (!webSessionId || !webSessionToken) {
      return reply.code(400).send({ error: 'webSessionId and sessionToken are required' });
    }
    const verified = verifyActiveWebSession(webSessionId, webSessionToken);
    if (verified.error) {
      return reply.code(verified.code).send({ active: false, error: verified.error });
    }
    const { session } = verified;
    session.lastSeenAtMs = Date.now();
    webActiveSessions.set(webSessionId, session);
    return reply.send({ active: true, sessionExpiresAt: session.sessionExpiresAtMs });
  });

  app.post('/web-login/sessions/list', async (req, reply) => {
    const accessToken = `${req.body?.accessToken || ''}`.trim();
    if (!accessToken) {
      return reply.code(400).send({ error: 'accessToken is required' });
    }
    let identity = null;
    try {
      identity = await getIdentityForAccessToken(accessToken);
    } catch (_) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    if (!identity?.studentId) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    cleanupWebActiveSessions();
    const sessions = [];
    for (const session of webActiveSessions.values()) {
      if (`${session.studentId || ''}` !== identity.studentId) continue;
      sessions.push(sessionPublicDto(session));
    }
    sessions.sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0));
    return reply.send({
      studentId: identity.studentId,
      studentEmail: identity.studentEmail || '',
      sessions,
    });
  });

  app.post('/web-login/sessions/revoke', async (req, reply) => {
    const accessToken = `${req.body?.accessToken || ''}`.trim();
    const webSessionId = `${req.body?.webSessionId || ''}`.trim();
    if (!accessToken || !webSessionId) {
      return reply.code(400).send({ error: 'accessToken and webSessionId are required' });
    }
    let identity = null;
    try {
      identity = await getIdentityForAccessToken(accessToken);
    } catch (_) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    const target = webActiveSessions.get(webSessionId);
    if (!target) {
      return reply.code(404).send({ error: 'Session not found' });
    }
    if (`${target.studentId || ''}` !== `${identity?.studentId || ''}`) {
      return reply.code(403).send({ error: 'Session does not belong to this account' });
    }
    webActiveSessions.delete(webSessionId);
    return reply.send({ ok: true, webSessionId });
  });

  app.post('/web-login/sessions/revoke-all', async (req, reply) => {
    const accessToken = `${req.body?.accessToken || ''}`.trim();
    if (!accessToken) {
      return reply.code(400).send({ error: 'accessToken is required' });
    }
    let identity = null;
    try {
      identity = await getIdentityForAccessToken(accessToken);
    } catch (_) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    const studentId = `${identity?.studentId || ''}`;
    if (!studentId) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    const now = Date.now();
    let revokedCount = 0;
    for (const [webSessionId, session] of webActiveSessions.entries()) {
      if (`${session.studentId || ''}` !== studentId) continue;
      webActiveSessions.delete(webSessionId);
      revokedCount += 1;
    }
    return reply.send({ ok: true, revokedCount, revokedAt: now });
  });
}
