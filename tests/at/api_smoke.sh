#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://localhost:8080}"

status() { echo "== $*"; }
req() {
  local method="$1" path="$2" body="${3:-}" expected="$4"
  local tmp
  tmp="$(mktemp)"
  local code
  if [[ -n "$body" ]]; then
    code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$BASE$path" \
      -H 'Content-Type: application/json' \
      --data "$body")
  else
    code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$BASE$path")
  fi
  if [[ "$code" != "$expected" ]]; then
    echo "FAIL $method $path -> $code (expected $expected)"
    echo "Response:"
    cat "$tmp"
    rm -f "$tmp"
    exit 1
  fi
  cat "$tmp"
  rm -f "$tmp"
}

status "GET /health -> 200"
req GET /health "" 200 >/dev/null

status "POST /auth/token success -> 200"
resp=$(req POST /auth/token '{"name":"admin","password":"password"}' 200)
echo "$resp" | jq -e '.access_token and .token_type=="bearer" and .user.name=="admin"' >/dev/null

status "POST /auth/token wrong password -> 401"
req POST /auth/token '{"name":"admin","password":"wrong"}' 401 >/dev/null

status "POST /auth/token unknown user -> 401"
req POST /auth/token '{"name":"nouser","password":"password"}' 401 >/dev/null

status "POST /auth/token empty body -> 400"
req POST /auth/token '' 400 >/dev/null

status "POST /auth/token invalid json -> 400"
req POST /auth/token 'not-json' 400 >/dev/null

echo "All acceptance checks passed."
