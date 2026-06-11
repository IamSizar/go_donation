# Repo-root Railway service — builds and runs the Go backend from ./backend.
# Use this when a Railway service points at the repository ROOT (no Root
# Directory set). It produces the exact same backend as backend/Dockerfile, so
# pick ONE service to run the API (root OR the "backend"-rooted service), not
# both.
#
# Required env vars (Railway → service → Variables):
#   DATABASE_URL          (from the Railway Postgres plugin)
#   RUN_MIGRATIONS=1      (first deploy: auto-creates the schema on a fresh DB)
#   CORS_ALLOWED_ORIGINS  (your dashboard URL, or "*" — optional)
#   ANTHROPIC_API_KEY     (optional — enables the AI assistant)
# Railway injects PORT automatically; the server binds to it.

FROM golang:1.26-alpine AS build
WORKDIR /src
COPY backend/ ./
RUN go mod download && CGO_ENABLED=0 go build -o /out/server ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=build /out/server /app/server
COPY backend/migrations /app/migrations
EXPOSE 8080
CMD ["/app/server"]
