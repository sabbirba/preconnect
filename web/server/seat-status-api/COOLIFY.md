# Coolify Deployment

This repository is set up to run on a VPS through Coolify without GitHub-based
scraper scheduling.

## Services

- `api` runs the Node.js seat-status API.
- `scraper` runs the Python refresh loop that used to be triggered by GitHub
  every 6 hours.

## Build

Use `docker-compose.yml` from the repo root.

## Persistent Volumes

- `/app/data`
- `/app/scraper/data`
- `/app/scraper/pdf`

## Environment Variables

Required for the API:

- `ACCESS_TOKEN` or `REFRESH_TOKEN`
- `FCM_PROJECT_ID`
- `FCM_SERVICE_ACCOUNT_JSON` or `FCM_SERVICE_ACCOUNT_FILE`

Optional:

- `PORT` default `8080`
- `PUSH_ALERTS_ENABLED` default `true`
- `SCRAPER_INTERVAL_SECONDS` default `21600`

## Notes

- The GitHub workflow at `.github/workflows/refresh-scraper-data.yml` has been
  removed.
- The scraper now refreshes on the VPS through the `scraper` container.
- If you use a custom domain, point it at the Coolify service and update the
  app client if the API host changes.
