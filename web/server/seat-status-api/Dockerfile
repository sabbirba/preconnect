FROM node:20-bookworm-slim
WORKDIR /app

ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    DATA_DIR=/app/data \
    SCRAPER_DATA_DIR=/app/scraper/data

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY src ./src
COPY scraper ./scraper

RUN mkdir -p /app/data

EXPOSE 8080
CMD ["npm", "start"]
