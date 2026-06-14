# Backend (Go API) — Railway service.
# Railway: set this service's Root Directory to "backend".
#
# Required env vars (Railway → service → Variables):
#   DATABASE_URL          (from the Railway Postgres plugin — usually auto-set)
#   RUN_MIGRATIONS=1      (first deploy: auto-creates the schema on a fresh DB)
#   CORS_ALLOWED_ORIGINS  (your dashboard URL, or "*" — optional, defaults to *)
#   ANTHROPIC_API_KEY     (optional — enables the AI assistant)
# Railway injects PORT automatically; the server binds to it.

FROM golang:1.26-alpine AS build
WORKDIR /src
COPY . .
RUN go mod download && CGO_ENABLED=0 go build -o /out/server ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=build /out/server /app/server
# Migrations travel with the image so RUN_MIGRATIONS=1 can apply them.
COPY migrations /app/migrations
# Seed/mock images + uploads, served at /images/* (referenced by the seed data).
COPY images /app/images
EXPOSE 8080
CMD ["/app/server"]
