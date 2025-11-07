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

req_auth() {
  local method="$1" path="$2" token="$3" body="${4:-}" expected="$5"
  local tmp
  tmp="$(mktemp)"
  local code
  if [[ -n "$body" ]]; then
    code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$BASE$path" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $token" \
      --data "$body")
  else
    code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$BASE$path" \
      -H "Authorization: Bearer $token")
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

# =============================================================================
# HEALTH CHECK
# =============================================================================
status "GET /health -> 200"
req GET /health "" 200 >/dev/null

# =============================================================================
# AUTHENTICATION TESTS
# =============================================================================
status "POST /auth/token success (admin) -> 200"
admin_resp=$(req POST /auth/token '{"name":"admin","password":"password"}' 200)
echo "$admin_resp" | jq -e '.access_token and .token_type=="bearer" and .user.name=="admin" and .user.type=="admin"' >/dev/null
ADMIN_TOKEN=$(echo "$admin_resp" | jq -r '.access_token')

status "POST /auth/token success (enduser) -> 200"
enduser_resp=$(req POST /auth/token '{"name":"enduser1","password":"password"}' 200)
echo "$enduser_resp" | jq -e '.access_token and .token_type=="bearer" and .user.name=="enduser1" and .user.type=="enduser"' >/dev/null
ENDUSER_TOKEN=$(echo "$enduser_resp" | jq -r '.access_token')
ENDUSER_ID=$(echo "$enduser_resp" | jq -r '.user.id')

status "POST /auth/token wrong password -> 401"
req POST /auth/token '{"name":"admin","password":"wrong"}' 401 >/dev/null

status "POST /auth/token unknown user -> 401"
req POST /auth/token '{"name":"nouser","password":"password"}' 401 >/dev/null

status "POST /auth/token empty body -> 400"
req POST /auth/token '' 400 >/dev/null

status "POST /auth/token invalid json -> 400"
req POST /auth/token 'not-json' 400 >/dev/null

status "POST /auth/token missing name -> 400"
req POST /auth/token '{"password":"password"}' 400 >/dev/null

status "POST /auth/token missing password -> 400"
req POST /auth/token '{"name":"admin"}' 400 >/dev/null

# =============================================================================
# ORDER CREATION TESTS - AUTHENTICATION & AUTHORIZATION
# =============================================================================
status "POST /orders without auth -> 401"
req POST /orders '{"pickup_lat":31.9454,"pickup_lng":35.9284,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 401 >/dev/null

status "POST /orders with invalid token -> 401"
req_auth POST /orders "invalid.token.here" '{"pickup_lat":31.9454,"pickup_lng":35.9284,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 401 >/dev/null

status "POST /orders with admin token -> 403"
req_auth POST /orders "$ADMIN_TOKEN" '{"pickup_lat":31.9454,"pickup_lng":35.9284,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 403 >/dev/null

# =============================================================================
# ORDER CREATION TESTS - VALID REQUESTS
# =============================================================================
status "POST /orders with enduser token (valid request) -> 201"
order1_resp=$(req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":31.9454,"pickup_lng":35.9284,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 201)
echo "$order1_resp" | jq -e '.order_id and .status=="pending" and .pickup.lat==31.9454 and .pickup.lng==35.9284 and .dropoff.lat==31.9632 and .dropoff.lng==35.9106' >/dev/null
ORDER1_ID=$(echo "$order1_resp" | jq -r '.order_id')

status "POST /orders with decimal coordinates -> 201"
order2_resp=$(req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":31.945678,"pickup_lng":35.928456,"dropoff_lat":31.963234,"dropoff_lng":35.910678}' 201)
echo "$order2_resp" | jq -e '.order_id and .status=="pending"' >/dev/null

status "POST /orders with boundary coordinates (min) -> 201"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":-90,"pickup_lng":-180,"dropoff_lat":-90,"dropoff_lng":-180}' 201 >/dev/null

status "POST /orders with boundary coordinates (max) -> 201"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":90,"pickup_lng":180,"dropoff_lat":90,"dropoff_lng":180}' 201 >/dev/null

status "POST /orders with zero coordinates -> 201"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":0,"pickup_lng":0,"dropoff_lat":0,"dropoff_lng":0}' 201 >/dev/null

# =============================================================================
# ORDER CREATION TESTS - VALIDATION ERRORS
# =============================================================================
status "POST /orders missing pickup_lat -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lng":35.9284,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 400 >/dev/null

status "POST /orders missing pickup_lng -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":31.9454,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 400 >/dev/null

status "POST /orders missing dropoff_lat -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":31.9454,"pickup_lng":35.9284,"dropoff_lng":35.9106}' 400 >/dev/null

status "POST /orders missing dropoff_lng -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":31.9454,"pickup_lng":35.9284,"dropoff_lat":31.9632}' 400 >/dev/null

status "POST /orders empty body -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '' 400 >/dev/null

status "POST /orders invalid json -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" 'not-json' 400 >/dev/null

status "POST /orders invalid latitude (>90) -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":91,"pickup_lng":35.9284,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 400 >/dev/null

status "POST /orders invalid latitude (<-90) -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":-91,"pickup_lng":35.9284,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 400 >/dev/null

status "POST /orders invalid longitude (>180) -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":31.9454,"pickup_lng":181,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 400 >/dev/null

status "POST /orders invalid longitude (<-180) -> 400"
req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":31.9454,"pickup_lng":-181,"dropoff_lat":31.9632,"dropoff_lng":35.9106}' 400 >/dev/null

# =============================================================================
# ORDER CANCELLATION TESTS - AUTHENTICATION & AUTHORIZATION
# =============================================================================
status "POST /orders/:id/cancel without auth -> 401"
req POST /orders/1/cancel "" 401 >/dev/null

status "POST /orders/:id/cancel with invalid token -> 401"
req_auth POST /orders/1/cancel "invalid.token.here" "" 401 >/dev/null

status "POST /orders/:id/cancel with admin token -> 403"
req_auth POST /orders/1/cancel "$ADMIN_TOKEN" "" 403 >/dev/null

# =============================================================================
# ORDER CANCELLATION TESTS - SETUP & VALID REQUESTS
# =============================================================================
status "Create order for successful cancel test -> 201"
cancel_order_resp=$(req_auth POST /orders "$ENDUSER_TOKEN" '{"pickup_lat":31.9,"pickup_lng":35.9,"dropoff_lat":31.95,"dropoff_lng":35.95}' 201)
CANCEL_ORDER_ID=$(echo "$cancel_order_resp" | jq -r '.order_id')

status "POST /orders/:id/cancel (valid pending order) -> 200"
cancel_resp=$(req_auth POST "/orders/$CANCEL_ORDER_ID/cancel" "$ENDUSER_TOKEN" "" 200)
echo "$cancel_resp" | jq -e '.order_id and .status=="canceled" and .canceled_at' >/dev/null

status "POST /orders/:id/cancel (already canceled) -> 409"
req_auth POST "/orders/$CANCEL_ORDER_ID/cancel" "$ENDUSER_TOKEN" "" 409 >/dev/null

# =============================================================================
# ORDER CANCELLATION TESTS - OWNERSHIP
# =============================================================================
status "Get enduser2 token for ownership test"
enduser2_resp=$(req POST /auth/token '{"name":"enduser2","password":"password"}' 200)
ENDUSER2_TOKEN=$(echo "$enduser2_resp" | jq -r '.access_token')

status "Create order owned by enduser2 -> 201"
enduser2_order_resp=$(req_auth POST /orders "$ENDUSER2_TOKEN" '{"pickup_lat":32.0,"pickup_lng":36.0,"dropoff_lat":32.1,"dropoff_lng":36.1}' 201)
ENDUSER2_ORDER_ID=$(echo "$enduser2_order_resp" | jq -r '.order_id')

status "POST /orders/:id/cancel (not owned by user) -> 403"
req_auth POST "/orders/$ENDUSER2_ORDER_ID/cancel" "$ENDUSER_TOKEN" "" 403 >/dev/null

# =============================================================================
# ORDER CANCELLATION TESTS - NOT FOUND & INVALID ID
# =============================================================================
status "POST /orders/:id/cancel (non-existent order) -> 404"
req_auth POST /orders/99999/cancel "$ENDUSER_TOKEN" "" 404 >/dev/null

status "POST /orders/:id/cancel (invalid ID format) -> 400"
req_auth POST /orders/abc/cancel "$ENDUSER_TOKEN" "" 400 >/dev/null

status "POST /orders/:id/cancel (ID = 0) -> 400"
req_auth POST /orders/0/cancel "$ENDUSER_TOKEN" "" 400 >/dev/null

status "POST /orders/:id/cancel (negative ID) -> 400"
req_auth POST /orders/-1/cancel "$ENDUSER_TOKEN" "" 400 >/dev/null

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "========================================="
echo "All acceptance tests passed! ✓"
echo "========================================="
echo "Tests executed:"
echo "  - Health check: 1"
echo "  - Authentication: 8"
echo "  - Authorization: 3"
echo "  - Order creation (valid): 5"
echo "  - Order validation errors: 12"
echo "  - Order cancellation (auth/authz): 3"
echo "  - Order cancellation (valid): 2"
echo "  - Order cancellation (ownership): 2"
echo "  - Order cancellation (not found): 4"
echo "Total: 40 test cases"
echo "========================================="
