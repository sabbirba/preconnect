FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release --pwa-strategy=none

FROM node:20-alpine

WORKDIR /app

COPY server.js /app/server.js
COPY --from=build /app/build/web /app/web

ENV PORT=80

EXPOSE 80

CMD ["node", "/app/server.js"]
