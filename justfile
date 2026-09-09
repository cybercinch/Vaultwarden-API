# Vaultwarden-API (cybercinch fork) — build, test & release recipes.
# Replaces the upstream Makefile. The Vaultwarden stack this backs runs on
# arm64, so published images are multi-arch (linux/amd64 + linux/arm64).

set shell := ["bash", "-uc"]

# Override on the CLI: `just registry=ghcr.io/cybercinch push`
registry  := "hub.cybercinch.nz/cybercinch"
image     := registry + "/vaultwarden-api"
version   := `git describe --tags --always --dirty 2>/dev/null || echo latest`
platforms := "linux/amd64,linux/arm64"
builder   := "cybercinch-multiarch"

# Show the recipe list.
default:
    @just --list

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------

# Tidy and download Go modules.
tidy:
    go mod tidy
    go mod download

# Compile the binary to ./bin.
bin: tidy
    @echo "Building vaultwarden-api..."
    CGO_ENABLED=0 go build -ldflags="-s -w" -o ./bin/vaultwarden-api ./cmd/api
    @echo "Build complete: ./bin/vaultwarden-api"

# go build + go vet, no output artifact.
check:
    go build ./...
    go vet ./...

# Race-enabled tests with an HTML coverage report.
test:
    go test -race -coverprofile=coverage.out ./...
    go tool cover -html=coverage.out -o coverage.html

# Run the app from source (requires .env — copy .env.example).
run-local:
    @[ -f .env ] || { echo "Error: .env not found. Copy .env.example to .env and configure it."; exit 1; }
    set -a && . ./.env && set +a && go run ./cmd/api/main.go

# Run from source with hot reload (installs air on first use).
dev:
    @command -v air >/dev/null || go install github.com/air-verse/air@latest
    @[ -f .env ] || { echo "Error: .env not found. Copy .env.example to .env and configure it."; exit 1; }
    air

# Clean build + coverage artifacts.
clean:
    rm -rf ./bin coverage.out coverage.html
    go clean

# ---------------------------------------------------------------------------
# Docker image
# ---------------------------------------------------------------------------

# One-time: create a buildx builder that can do multi-arch.
buildx-setup:
    @if ! docker buildx inspect {{builder}} >/dev/null 2>&1; then \
        docker buildx create --name {{builder}} --driver docker-container --bootstrap; \
    fi
    docker buildx use {{builder}}

# Build a native-arch image into the local docker engine (for `just docker-run`).
build:
    docker buildx build --load -t {{image}}:local -t vaultwarden-api:local .

# Push the multi-arch image, tagged :<git describe> and :latest (run `just login` first).
push: buildx-setup
    docker buildx build \
        --platform {{platforms}} \
        --push \
        -t {{image}}:{{version}} \
        -t {{image}}:latest \
        .
    @echo "==> pushed {{image}}:{{version}} and :latest ({{platforms}})"

# Push one explicit tag, multi-arch: `just tag=v1.4.0 push-tag`
tag := version
push-tag: buildx-setup
    docker buildx build --platform {{platforms}} --push -t {{image}}:{{tag}} .
    @echo "==> pushed {{image}}:{{tag}}"

# Log in to the fork's registry.
login:
    docker login {{registry}}

# Run the local image with .env.
docker-run: build
    @[ -f .env ] || { echo "Error: .env not found. Copy .env.example to .env and configure it."; exit 1; }
    docker rm -f vaultwarden-api-local 2>/dev/null || true
    docker run -d --name vaultwarden-api-local --env-file .env -p 8080:8080 vaultwarden-api:local
    @echo "==> http://localhost:8080/health"

docker-logs:
    docker logs -f vaultwarden-api-local

docker-stop:
    docker rm -f vaultwarden-api-local 2>/dev/null || true

# ---------------------------------------------------------------------------
# docker compose (uses docker-compose.yml + .env)
# ---------------------------------------------------------------------------

up:
    @[ -f .env ] || { echo "Error: .env not found. Copy .env.example to .env and configure it."; exit 1; }
    docker compose up -d --build

down:
    docker compose down

compose-logs:
    docker compose logs -f

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Generate a random API key.
generate-api-key:
    @echo "Generated API key:"
    @openssl rand -base64 32

# Refresh the embedded Cloudflare ranges (TRUSTED_PROXY_PRESET=cloudflare).
update-cloudflare-ips:
    ./scripts/update-cloudflare-ips.sh

# ---------------------------------------------------------------------------
# Fork upkeep
# ---------------------------------------------------------------------------

# Fast-forward main to upstream (keeps main a clean mirror for PRs).
sync-upstream:
    git fetch upstream
    git checkout main
    git merge --ff-only upstream/main
    git checkout -

# Show what this fork changes on top of main.
fork-diff:
    git diff --stat main...HEAD
