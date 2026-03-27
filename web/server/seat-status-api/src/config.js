import path from 'node:path';

export function createConfig(env = process.env) {
  const dataDir = `${env.DATA_DIR || '/tmp/preconnect/data'}`.trim();
  const scraperDataDir = `${env.SCRAPER_DATA_DIR || '/tmp/preconnect/scraper/data'}`.trim();

  return {
    port: Number(env.PORT || 8080),
    connectApiBase: 'https://connect.bracu.ac.bd/api',
    tokenEndpoint:
      'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/token',
    clientId: 'slm',
    realm: 'bracu',
    source: '3',
    initialAccessToken: `${env.ACCESS_TOKEN || ''}`.trim(),
    initialRefreshToken: `${env.REFRESH_TOKEN || ''}`.trim(),
    ramadanCity: 'Dhaka',
    ramadanCountry: 'Bangladesh',
    ramadanState: '',
    ramadanTimeZone: 'Asia/Dhaka',
    ramadanMethod: '1',
    ramadanSchool: '1',
    seatMapTtlMs: 2_592_000_000,
    detailsTtlMs: 2_592_000_000,
    staffTtlMs: 86_400_000,
    prerequisitesTtlMs: 2_592_000_000,
    calendarTtlMs: 21_600_000,
    ramadanTtlMs: 21_600_000,
    seatStreamPollMs: 5_000,
    webLoginTtlMs: 30_000,
    webLoginSessionMaxMs: 300_000,
    dataDir,
    pushStateFilePath: path.join(dataDir, 'push-seat-alerts.json'),
    scraperDataDir,
    fcmProjectId: `${env.FCM_PROJECT_ID || 'preconnect-bracu'}`.trim(),
    fcmServiceAccountJson: `${env.FCM_SERVICE_ACCOUNT_JSON || ''}`.trim(),
    fcmServiceAccountFile: `${env.FCM_SERVICE_ACCOUNT_FILE || ''}`.trim(),
    pushEnabled: `${env.PUSH_ALERTS_ENABLED || 'true'}`.trim() !== 'false',
  };
}
