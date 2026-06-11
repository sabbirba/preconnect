# Stage 1: Build Flutter Web application
FROM debian:bookworm-slim AS build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    unzip \
    ca-certificates \
    xz-utils \
    zip \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone stable Flutter channel
RUN git clone https://github.com/flutter/flutter.git -b stable --depth 1 /flutter
ENV PATH="/flutter/bin:$PATH"

# Pre-cache binaries and run doctor
RUN flutter doctor -v

# Copy files
COPY . .

# Run pub get and build the web application
RUN flutter pub get
RUN flutter build web --release

# Stage 2: Run phase using Nginx
FROM nginx:alpine

# Copy built static assets and Nginx configuration
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
