export function registerPushRoutes(app, context) {
  const {
    pushState,
    getRequestIdentity,
    ensurePushStateLoaded,
    persistPushState,
    startSeatStreamLoop,
    normalizeSeatAlertRules,
    hasSeatAlertRules,
    seatAlertSubscriptionKey,
  } = context;

  app.post('/push/device/register', async (req, reply) => {
    const identity = await getRequestIdentity(req);
    if (!identity?.studentId) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    const token = `${req.body?.token || ''}`.trim();
    const platform = `${req.body?.platform || ''}`.trim().toLowerCase();
    if (!token || !platform) {
      return reply.code(400).send({ error: 'token and platform are required' });
    }
    await ensurePushStateLoaded();
    pushState.devices.set(token, {
      token,
      studentId: identity.studentId,
      studentEmail: identity.studentEmail || '',
      platform,
      locale: `${req.body?.locale || ''}`.trim(),
      appVersion: `${req.body?.appVersion || ''}`.trim(),
      lastSeenAt: Date.now(),
    });
    await persistPushState();
    startSeatStreamLoop();
    return reply.send({ ok: true });
  });

  app.post('/push/device/unregister', async (req, reply) => {
    const identity = await getRequestIdentity(req);
    if (!identity?.studentId) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    const token = `${req.body?.token || ''}`.trim();
    if (!token) {
      return reply.code(400).send({ error: 'token is required' });
    }
    await ensurePushStateLoaded();
    const existing = pushState.devices.get(token);
    if (existing && existing.studentId !== identity.studentId) {
      return reply.code(403).send({ error: 'Device does not belong to this account' });
    }
    pushState.devices.delete(token);
    for (const [key, subscription] of pushState.subscriptions.entries()) {
      if (subscription.token === token && subscription.studentId === identity.studentId) {
        pushState.subscriptions.delete(key);
      }
    }
    await persistPushState();
    startSeatStreamLoop();
    return reply.send({ ok: true });
  });

  app.put('/push/seat-alerts', async (req, reply) => {
    const identity = await getRequestIdentity(req);
    if (!identity?.studentId) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    const token = `${req.body?.token || ''}`.trim();
    const subscriptions = Array.isArray(req.body?.subscriptions)
      ? req.body.subscriptions
      : null;
    if (!token || !subscriptions) {
      return reply.code(400).send({ error: 'token and subscriptions are required' });
    }
    await ensurePushStateLoaded();
    const device = pushState.devices.get(token);
    if (!device || device.studentId !== identity.studentId) {
      return reply.code(404).send({ error: 'Device not registered' });
    }
    for (const [key, subscription] of pushState.subscriptions.entries()) {
      if (subscription.token === token && subscription.studentId === identity.studentId) {
        pushState.subscriptions.delete(key);
      }
    }
    for (const item of subscriptions) {
      const sectionId = Number(item?.sectionId);
      const rules = normalizeSeatAlertRules(item?.rules || {});
      if (!Number.isFinite(sectionId) || sectionId <= 0 || !hasSeatAlertRules(rules)) {
        continue;
      }
      pushState.subscriptions.set(
        seatAlertSubscriptionKey(identity.studentId, token, sectionId),
        {
          token,
          studentId: identity.studentId,
          studentEmail: identity.studentEmail || '',
          sectionId,
          rules,
          lastTriggeredAt: {},
        },
      );
    }
    await persistPushState();
    startSeatStreamLoop();
    return reply.send({ ok: true });
  });

  app.put('/push/seat-alerts/:sectionId', async (req, reply) => {
    const identity = await getRequestIdentity(req);
    if (!identity?.studentId) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    const token = `${req.body?.token || ''}`.trim();
    const sectionId = Number(req.params.sectionId);
    const rules = normalizeSeatAlertRules(req.body?.rules || {});
    if (!token || !Number.isFinite(sectionId) || sectionId <= 0) {
      return reply.code(400).send({ error: 'token and valid sectionId are required' });
    }
    await ensurePushStateLoaded();
    const device = pushState.devices.get(token);
    if (!device || device.studentId !== identity.studentId) {
      return reply.code(404).send({ error: 'Device not registered' });
    }
    const key = seatAlertSubscriptionKey(identity.studentId, token, sectionId);
    if (!hasSeatAlertRules(rules)) {
      pushState.subscriptions.delete(key);
      await persistPushState();
      return reply.send({ ok: true, removed: true });
    }
    const previous = pushState.subscriptions.get(key);
    pushState.subscriptions.set(key, {
      token,
      studentId: identity.studentId,
      studentEmail: identity.studentEmail || '',
      sectionId,
      rules,
      lastTriggeredAt: previous?.lastTriggeredAt || {},
    });
    await persistPushState();
    return reply.send({ ok: true });
  });

  app.delete('/push/seat-alerts/:sectionId', async (req, reply) => {
    const identity = await getRequestIdentity(req);
    if (!identity?.studentId) {
      return reply.code(401).send({ error: 'Unable to verify account session' });
    }
    const token = `${req.body?.token || ''}`.trim();
    const sectionId = Number(req.params.sectionId);
    if (!token || !Number.isFinite(sectionId) || sectionId <= 0) {
      return reply.code(400).send({ error: 'token and valid sectionId are required' });
    }
    await ensurePushStateLoaded();
    pushState.subscriptions.delete(
      seatAlertSubscriptionKey(identity.studentId, token, sectionId),
    );
    await persistPushState();
    return reply.send({ ok: true });
  });
}
