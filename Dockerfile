# Stage 1: Build the frontend
FROM node:18-alpine AS frontend

WORKDIR /app

# Build email builder first
COPY frontend/email-builder/package.json frontend/email-builder/yarn.lock* frontend/email-builder/
RUN cd frontend/email-builder && yarn install --frozen-lockfile || cd frontend/email-builder && yarn install

COPY frontend/email-builder/ frontend/email-builder/
RUN cd frontend/email-builder && yarn build

# Build main frontend
COPY frontend/package.json frontend/yarn.lock* frontend/
RUN cd frontend && yarn install --frozen-lockfile || cd frontend && yarn install

COPY frontend/ frontend/

# Copy email builder dist into frontend public
RUN mkdir -p frontend/public/static/email-builder && \
    cp -r frontend/email-builder/dist/* frontend/public/static/email-builder/

RUN cd frontend && yarn build


# Stage 2: Build the Go binary
FROM golang:1.24-alpine AS builder

RUN apk --no-cache add make git

WORKDIR /app

# Install stuffbin
RUN go install github.com/knadh/stuffbin/...@latest

# Copy go module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Copy frontend dist from stage 1
COPY --from=frontend /app/frontend/dist frontend/dist

# Build the Go binary
ARG VERSION=v0.0.0
RUN CGO_ENABLED=0 go build -o listmonk \
    -ldflags="-s -w -X 'main.buildString=${VERSION} (#$(date -u +%Y-%m-%dT%H:%M:%S%z))' -X 'main.versionString=${VERSION}'" \
    cmd/*.go

# Pack static assets into the binary
RUN stuffbin -a stuff -in listmonk -out listmonk \
    config.toml.sample \
    schema.sql \
    queries:/queries \
    permissions.json \
    static/public:/public \
    static/email-templates \
    frontend/dist:/admin \
    i18n:/i18n


# Stage 3: Final image
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata shadow su-exec

WORKDIR /listmonk

COPY --from=builder /app/listmonk .
COPY config.toml.sample config.toml
COPY docker-entrypoint.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["./listmonk"]
