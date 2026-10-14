# Multi-stage Dockerfile for BankOps Flutter Web
# Stage 1: Build Flutter Web application
FROM ghcr.io/cirruslabs/flutter:3.24.5 AS builder

WORKDIR /app
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
ARG API_BASE_URL=""
ARG GOOGLE_CLIENT_ID=""
RUN flutter build web --release \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID} \
    --dart-define=APP_ENV=production

# Stage 2: Serve with lightweight Nginx Alpine
FROM nginx:alpine-slim

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy build artifacts from builder stage
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
