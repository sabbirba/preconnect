FROM alpine:3.20 AS downloader

ARG GITHUB_REPO=sabbirba/preconnect
ARG GITHUB_TOKEN=""

ENV GITHUB_REPO=${GITHUB_REPO}
ENV GITHUB_TOKEN=${GITHUB_TOKEN}

RUN apk add --no-cache curl python3 unzip ca-certificates

WORKDIR /tmp

RUN set -e; \
    DOWNLOAD_URL=$(python3 -c "
import urllib.request, json, os, sys
repo = os.environ.get('GITHUB_REPO', 'sabbirba/preconnect')
token = os.environ.get('GITHUB_TOKEN', '')
headers = {'User-Agent': 'Mozilla/5.0', 'Accept': 'application/vnd.github+json'}
if token:
    headers['Authorization'] = f'Bearer {token}'
req = urllib.request.Request(f'https://api.github.com/repos/{repo}/releases/latest', headers=headers)
try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        url = None
        for asset in data.get('assets', []):
            name = asset.get('name', '').lower()
            if 'web' in name and name.endswith('.zip'):
                url = asset.get('browser_download_url')
                break
        if url:
            print(url)
        else:
            sys.exit(1)
except Exception as e:
    sys.exit(1)
"); \
    if [ -z "$DOWNLOAD_URL" ]; then \
        echo "Error: Could not find web release asset in latest release." >&2; \
        exit 1; \
    fi; \
    echo "Downloading web release asset: $DOWNLOAD_URL"; \
    if [ -n "$GITHUB_TOKEN" ]; then \
        curl -s -L -H "Authorization: Bearer $GITHUB_TOKEN" -A "Mozilla/5.0" -o web-release.zip "$DOWNLOAD_URL"; \
    else \
        curl -s -L -A "Mozilla/5.0" -o web-release.zip "$DOWNLOAD_URL"; \
    fi; \
    mkdir -p /app; \
    unzip -q web-release.zip -d /app; \
    if [ ! -f /app/index.html ]; then \
        SUBDIR=$(find /app -mindepth 1 -maxdepth 1 -type d | head -n 1); \
        if [ -n "$SUBDIR" ] && [ -f "$SUBDIR/index.html" ]; then \
            mv "$SUBDIR"/* /app/; \
        fi; \
    fi

FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=downloader /app /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
