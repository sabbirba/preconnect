FROM alpine:3.20 AS downloader

ARG GITHUB_REPO=sabbirba/preconnect
ARG GITHUB_TOKEN=""

ENV GITHUB_REPO=${GITHUB_REPO}
ENV GITHUB_TOKEN=${GITHUB_TOKEN}

RUN apk add --no-cache curl python3 unzip ca-certificates

WORKDIR /tmp

RUN set -eu; \
    API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"; \
    if [ -n "$GITHUB_TOKEN" ]; then \
        RELEASE_JSON=$(curl --fail --silent --show-error --location --retry 3 \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -A "PreConnect-Docker" "$API_URL"); \
    else \
        RELEASE_JSON=$(curl --fail --silent --show-error --location --retry 3 \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -A "PreConnect-Docker" "$API_URL"); \
    fi; \
    DOWNLOAD_URL=$(printf '%s' "$RELEASE_JSON" | python3 -c 'import json, sys; assets = json.load(sys.stdin).get("assets", []); print(next((asset.get("browser_download_url", "") for asset in assets if "web" in asset.get("name", "").lower() and asset.get("name", "").lower().endswith(".zip")), ""))'); \
    if [ -z "$DOWNLOAD_URL" ]; then \
        echo "Error: Could not find web release asset in latest release." >&2; \
        exit 1; \
    fi; \
    echo "Downloading web release asset: $DOWNLOAD_URL"; \
    if [ -n "$GITHUB_TOKEN" ]; then \
        curl --fail --silent --show-error --location --retry 3 -H "Authorization: Bearer $GITHUB_TOKEN" -A "PreConnect-Docker" -o web-release.zip "$DOWNLOAD_URL"; \
    else \
        curl --fail --silent --show-error --location --retry 3 -A "PreConnect-Docker" -o web-release.zip "$DOWNLOAD_URL"; \
    fi; \
    mkdir -p /app; \
    unzip -q web-release.zip -d /app; \
    if [ ! -f /app/index.html ]; then \
        INDEX_FILE=$(find /app -mindepth 2 -type f -name index.html -print -quit); \
        if [ -n "$INDEX_FILE" ]; then \
            WEB_ROOT=$(dirname "$INDEX_FILE"); \
            cp -a "$WEB_ROOT"/. /app/; \
        fi; \
    fi; \
    if [ ! -f /app/index.html ]; then \
        echo "Error: Web release archive does not contain index.html." >&2; \
        exit 1; \
    fi

FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=downloader /app /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
