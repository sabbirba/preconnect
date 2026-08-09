FROM alpine:3.20 AS downloader

ARG GITHUB_REPO

RUN apk add --no-cache curl python3 unzip ca-certificates

WORKDIR /tmp

RUN --mount=type=secret,id=github_token,required=true set -eu; \
    GITHUB_TOKEN=$(cat /run/secrets/github_token); \
    API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"; \
    RELEASE_JSON=$(curl --fail --silent --show-error --location --retry 3 \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -A "PreConnect-Docker" "$API_URL"); \
    DOWNLOAD_URL=$(printf '%s' "$RELEASE_JSON" | python3 -c 'import json, sys; assets = json.load(sys.stdin).get("assets", []); print(next((asset.get("browser_download_url", "") for asset in assets if "web" in asset.get("name", "").lower() and asset.get("name", "").lower().endswith(".zip")), ""))'); \
    if [ -z "$DOWNLOAD_URL" ]; then \
        echo "Error: Could not find web release asset in latest release." >&2; \
        exit 1; \
    fi; \
    echo "Downloading web release asset: $DOWNLOAD_URL"; \
    curl --fail --silent --show-error --location --retry 3 -H "Authorization: Bearer $GITHUB_TOKEN" -A "PreConnect-Docker" -o web-release.zip "$DOWNLOAD_URL"; \
    mkdir -p /app; \
    unzip -q web-release.zip -d /app; \
    if [ ! -f /app/index.html ]; then \
        echo "Error: Web release archive does not contain index.html." >&2; \
        exit 1; \
    fi

FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=downloader /app /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
