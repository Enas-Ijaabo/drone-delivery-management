#!/usr/bin/env bash
# Common test utilities and helper functions
set -euo pipefail

BASE="${BASE:-http://localhost:8080}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Last response storage
LAST_RESPONSE=""
LAST_STATUS=""

# =============================================================================
# HTTP REQUEST HELPERS
# =============================================================================

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
  
  LAST_RESPONSE=$(cat "$tmp")
  LAST_STATUS="$code"
  
  if [[ "$code" != "$expected" ]]; then
    echo "Response: $LAST_RESPONSE"
    rm -f "$tmp"
    return 1
  fi
  
  echo "$LAST_RESPONSE"
  rm -f "$tmp"
  return 0
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
  
  LAST_RESPONSE=$(cat "$tmp")
  LAST_STATUS="$code"
  
  if [[ "$code" != "$expected" ]]; then
    echo "Response: $LAST_RESPONSE"
    rm -f "$tmp"
    return 1
  fi
  
  echo "$LAST_RESPONSE"
  rm -f "$tmp"
  return 0
}

req_auth_raw() {
  local method="$1" path="$2" token="$3" body="$4" expected="$5"
  local tmp
  tmp="$(mktemp)"
  local code
  
  code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$BASE$path" \
    -H "Authorization: Bearer $token" \
    --data-raw "$body")
  
  LAST_RESPONSE=$(cat "$tmp")
  LAST_STATUS="$code"
  
  if [[ "$code" != "$expected" ]]; then
    rm -f "$tmp"
    return 1
  fi
  
  rm -f "$tmp"
  return 0
}

# =============================================================================
# QUICK HELPER FUNCTIONS
# =============================================================================

get_token() {
  local username="$1"
  local password="$2"
  local resp
  resp=$(req POST /auth/token "{\"name\":\"$username\",\"password\":\"$password\"}" 200 2>/dev/null)
  echo "$resp" | jq -r '.access_token'
}

create_order() {
  local token="$1"
  local pickup_lat="$2"
  local pickup_lng="$3"
  local dropoff_lat="$4"
  local dropoff_lng="$5"
  
  local resp
  resp=$(req_auth POST /orders "$token" \
    "{\"pickup_lat\":$pickup_lat,\"pickup_lng\":$pickup_lng,\"dropoff_lat\":$dropoff_lat,\"dropoff_lng\":$dropoff_lng}" 201 2>/dev/null)
  echo "$resp" | jq -r '.order_id'
}

# =============================================================================
# DATABASE HELPERS
# =============================================================================

get_db_value() {
  local query="$1"
  docker-compose exec -T db mysql -u root -pexample drone -Nse "$query" 2>/dev/null
}

verify_db_value() {
  local query="$1"
  local expected="$2"
  local actual
  actual=$(get_db_value "$query")
  
  if [[ "$actual" == "$expected" ]]; then
    return 0
  else
    echo "Expected: $expected, Got: $actual"
    return 1
  fi
}

verify_db_timestamp_updated() {
  local table="$1"
  local id="$2"
  local id_col="${3:-id}"
  
  local query="SELECT updated_at FROM $table WHERE $id_col=$id"
  local timestamp
  timestamp=$(get_db_value "$query")
  
  if [[ -n "$timestamp" ]]; then
    return 0
  else
    return 1
  fi
}

reset_drones() {
  docker-compose exec -T db mysql -u root -pexample drone \
    -e "UPDATE drone_status SET status='idle', current_order_id=NULL WHERE drone_id IN (4, 5);" 2>/dev/null || true
}

# =============================================================================
# TEST SETUP HELPERS
# =============================================================================

setup_test_users() {
  # Get tokens for all test users
  local admin_resp
  admin_resp=$(req POST /auth/token '{"name":"admin","password":"password"}' 200)
  export ADMIN_TOKEN=$(echo "$admin_resp" | jq -r '.access_token')
  
  local enduser_resp
  enduser_resp=$(req POST /auth/token '{"name":"enduser1","password":"password"}' 200)
  export ENDUSER_TOKEN=$(echo "$enduser_resp" | jq -r '.access_token')
  export ENDUSER_ID=$(echo "$enduser_resp" | jq -r '.user.id')
  
  local enduser2_resp
  enduser2_resp=$(req POST /auth/token '{"name":"enduser2","password":"password"}' 200)
  export ENDUSER2_TOKEN=$(echo "$enduser2_resp" | jq -r '.access_token')
  
  local drone1_resp
  drone1_resp=$(req POST /auth/token '{"name":"drone1","password":"password"}' 200)
  export DRONE1_TOKEN=$(echo "$drone1_resp" | jq -r '.access_token')
  export DRONE1_ID=$(echo "$drone1_resp" | jq -r '.user.id')
  
  local drone2_resp
  drone2_resp=$(req POST /auth/token '{"name":"drone2","password":"password"}' 200)
  export DRONE2_TOKEN=$(echo "$drone2_resp" | jq -r '.access_token')
  export DRONE2_ID=$(echo "$drone2_resp" | jq -r '.user.id')
}

create_order_as_enduser() {
  local lat="${1:-31.9454}"
  local lng="${2:-35.9284}"
  local dlat="${3:-31.9632}"
  local dlng="${4:-35.9106}"
  
  local resp
  resp=$(req_auth POST /orders "$ENDUSER_TOKEN" \
    "{\"pickup_lat\":$lat,\"pickup_lng\":$lng,\"dropoff_lat\":$dlat,\"dropoff_lng\":$dlng}" 201)
  
  export ORDER_ID=$(echo "$resp" | jq -r '.order_id')
  export PENDING_ORDER_ID=$ORDER_ID
}

# =============================================================================
# JSON VERIFICATION HELPERS
# =============================================================================

verify_json_field() {
  local field="$1"
  local expected="$2"
  local json="${3:-$LAST_RESPONSE}"
  
  local actual
  actual=$(echo "$json" | jq -r "$field")
  
  if [[ "$actual" == "$expected" ]]; then
    return 0
  else
    echo "Field $field: Expected $expected, Got $actual"
    return 1
  fi
}

verify_json_has_field() {
  local field="$1"
  local json="${2:-$LAST_RESPONSE}"
  
  echo "$json" | jq -e "$field" >/dev/null 2>&1
}

verify_json_no_field() {
  local field="$1"
  local json="${2:-$LAST_RESPONSE}"
  
  # Try to access the field - if it doesn't exist or is null, jq will fail
  if echo "$json" | jq -e "$field" >/dev/null 2>&1; then
    # Field exists and is not null
    return 1
  else
    # Field doesn't exist or is null
    return 0
  fi
}

# Alias for consistency with test naming
verify_json_field_absent() {
  verify_json_no_field "$@"
}

# =============================================================================
# CONCURRENT TESTING HELPERS
# =============================================================================

test_concurrent_reserve() {
  local order_id="$1"
  
  # Launch two concurrent reserve requests
  req_auth POST /orders/$order_id/reserve $DRONE1_TOKEN '' 200 &
  local pid1=$!
  
  req_auth POST /orders/$order_id/reserve $DRONE2_TOKEN '' 200 &
  local pid2=$!
  
  # Wait for both to complete
  wait $pid1 2>/dev/null
  local result1=$?
  
  wait $pid2 2>/dev/null
  local result2=$?
  
  # Exactly one should succeed (exit 0) and one should fail
  if [[ $result1 -eq 0 && $result2 -ne 0 ]] || [[ $result1 -ne 0 && $result2 -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

test_reserve_vs_cancel() {
  local order_id="$1"
  
  # Launch concurrent reserve and cancel
  req_auth POST /orders/$order_id/reserve $DRONE1_TOKEN '' 200 &
  local pid1=$!
  
  req_auth POST /orders/$order_id/cancel $ENDUSER_TOKEN '' 200 &
  local pid2=$!
  
  # Wait for both
  wait $pid1 2>/dev/null
  local result1=$?
  
  wait $pid2 2>/dev/null
  local result2=$?
  
  # One should succeed
  if [[ $result1 -eq 0 || $result2 -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# =============================================================================
# TEST EXECUTION HELPERS
# =============================================================================

run_test() {
  local test_name="$1"
  local test_command="$2"
  
  ((TEST_COUNT++))
  
  if eval "$test_command" >/dev/null 2>&1; then
    ((PASS_COUNT++))
    echo -e "${GREEN}✓${NC} $test_name"
    return 0
  else
    ((FAIL_COUNT++))
    echo -e "${RED}✗${NC} $test_name"
    return 1
  fi
}

pass_test() {
  local msg="$1"
  ((TEST_COUNT++))
  ((PASS_COUNT++))
  echo -e "${GREEN}✓${NC} $msg"
}

fail_test() {
  local msg="$1"
  ((TEST_COUNT++))
  ((FAIL_COUNT++))
  echo -e "${RED}✗${NC} $msg"
  return 1
}

test_section() {
  local section_name="$1"
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$section_name${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_summary() {
  local endpoint_name="$1"
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}Test Summary: $endpoint_name${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo -e "Total Tests: $TEST_COUNT"
  echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
  echo -e "${RED}Failed: $FAIL_COUNT${NC}"
  
  local percentage=0
  if [[ $TEST_COUNT -gt 0 ]]; then
    percentage=$((PASS_COUNT * 100 / TEST_COUNT))
  fi
  echo -e "Success Rate: $percentage%"
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo ""
  
  if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
  fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# This function should be called at the start of each test file
init_tests() {
  echo "Initializing test environment..."
  
  # Reset drones to idle state
  reset_drones
  
  # Setup all test user tokens
  setup_test_users
  
  # Create a pending order for general use
  create_order_as_enduser
  
  echo "Test environment ready!"
  echo ""
}
