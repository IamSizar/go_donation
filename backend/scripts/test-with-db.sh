#!/usr/bin/env bash
#
# Run the WHOLE backend test suite, including the integration tests.
#
# WHY THIS EXISTS
# 171 of the 282 backend tests skip themselves unless TEST_DATABASE_URL points
# at a Postgres they can migrate and write to. On a bare checkout `go test ./...`
# therefore reports success having run 111 tests — 39% of the suite — and says
# nothing about the 171 it quietly stepped over. Those are the tests covering
# delete guards, permission gates, privacy rules and account status: precisely
# the behaviour where a silent regression is most expensive.
#
# The command to run them was written down only inside test-file comments, so
# finding it meant already knowing it existed. This script is that command.
#
# It starts a throwaway Postgres in Docker, hands the tests an EMPTY database
# (they apply the migrations themselves — pre-migrating it makes them fail), and
# removes the container afterwards even if the run fails.
#
# Usage:
#   ./scripts/test-with-db.sh              # whole suite
#   ./scripts/test-with-db.sh ./internal/handlers/ -run SignupDelete
set -euo pipefail

CONTAINER="gd-test-pg-$$"
PORT="${TEST_PG_PORT:-55432}"
DB_URL="postgres://postgres:test@localhost:${PORT}/godonation_test?sslmode=disable"

cd "$(dirname "$0")/.."

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Start Docker, or set TEST_DATABASE_URL yourself" >&2
  echo "and run: go test ./..." >&2
  exit 1
fi

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> starting throwaway Postgres on :${PORT}"
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=godonation_test \
  -p "${PORT}:5432" \
  postgres:16 >/dev/null

for _ in $(seq 1 30); do
  if docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
  echo "Postgres did not become ready within 30s" >&2
  exit 1
fi

echo "==> running tests against a live database"
# The database is left EMPTY on purpose: each test package runs the migrations
# itself, and applying them beforehand makes the run fail with "relation already
# exists".
TEST_DATABASE_URL="$DB_URL" go test "${@:-./...}"
