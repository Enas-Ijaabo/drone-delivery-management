#!/usr/bin/env bash
# Test suite for POST /orders endpoint
set -euo pipefail

source "$(dirname "$0")/test_common.sh"
set +e

# Get tokens
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")

# =============================================================================
# AUTH & AUTHORIZATION TESTS
# =============================================================================
test_section "Order Creation - Auth & Authorization"

run_test "POST /orders without auth -> 401" \
  "req POST /orders '{\"pickup_lat\":31.9,\"pickup_lng\":35.9,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 401"

run_test "POST /orders with invalid token -> 401" \
  "req_auth POST /orders 'invalid.token' '{\"pickup_lat\":31.9,\"pickup_lng\":35.9,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 401"

run_test "POST /orders with admin token -> 403" \
  "req_auth POST /orders '$ADMIN_TOKEN' '{\"pickup_lat\":31.9,\"pickup_lng\":35.9,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 403"

# =============================================================================
# VALID REQUESTS
# =============================================================================
test_section "Order Creation - Valid Requests"

run_test "POST /orders (standard coordinates) -> 201" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":31.9454,\"pickup_lng\":35.9284,\"dropoff_lat\":31.9632,\"dropoff_lng\":35.9106}' 201"

verify_json_field ".status" "pending" "$LAST_RESPONSE"
verify_json_has_field ".order_id" "$LAST_RESPONSE"

run_test "POST /orders (decimal coordinates) -> 201" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":31.945678,\"pickup_lng\":35.928456,\"dropoff_lat\":31.963234,\"dropoff_lng\":35.910678}' 201"

run_test "POST /orders (boundary min) -> 201" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":-90,\"pickup_lng\":-180,\"dropoff_lat\":-90,\"dropoff_lng\":-180}' 201"

run_test "POST /orders (boundary max) -> 201" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":90,\"pickup_lng\":180,\"dropoff_lat\":90,\"dropoff_lng\":180}' 201"

run_test "POST /orders (zero coordinates) -> 201" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":0,\"pickup_lng\":0,\"dropoff_lat\":0,\"dropoff_lng\":0}' 201"

# =============================================================================
# VALIDATION ERRORS - MISSING FIELDS
# =============================================================================
test_section "Order Creation - Missing Fields"

run_test "POST /orders (missing pickup_lat) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lng\":35.9,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 400"

run_test "POST /orders (missing pickup_lng) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":31.9,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 400"

run_test "POST /orders (missing dropoff_lat) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":31.9,\"pickup_lng\":35.9,\"dropoff_lng\":36.0}' 400"

run_test "POST /orders (missing dropoff_lng) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":31.9,\"pickup_lng\":35.9,\"dropoff_lat\":32.0}' 400"

# =============================================================================
# VALIDATION ERRORS - INVALID FORMAT
# =============================================================================
test_section "Order Creation - Invalid Format"

run_test "POST /orders (empty body) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '' 400"

run_test "POST /orders (invalid json) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' 'not-json' 400"

# =============================================================================
# VALIDATION ERRORS - OUT OF RANGE
# =============================================================================
test_section "Order Creation - Out of Range Coordinates"

run_test "POST /orders (lat > 90) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":91,\"pickup_lng\":35.9,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 400"

run_test "POST /orders (lat < -90) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":-91,\"pickup_lng\":35.9,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 400"

run_test "POST /orders (lng > 180) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":31.9,\"pickup_lng\":181,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 400"

run_test "POST /orders (lng < -180) -> 400" \
  "req_auth POST /orders '$ENDUSER_TOKEN' '{\"pickup_lat\":31.9,\"pickup_lng\":-181,\"dropoff_lat\":32.0,\"dropoff_lng\":36.0}' 400"

print_summary "POST /orders"
