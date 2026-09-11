# Build stage
FROM golang:1.27-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .

ARG TARGETOS
ARG TARGETARCH

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
    -ldflags="-s -w" \
    -o /build/vaultwarden-api \
    ./cmd/api

# Runtime stage — pure Alpine, no Node.js
FROM alpine:20260805

RUN apk update && \
    apk upgrade && \
    apk add --no-cache ca-certificates wget && \
    adduser -D -H appuser

WORKDIR /app
COPY --from=builder /build/vaultwarden-api .

USER appuser
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/vaultwarden-api"]
