#!/usr/bin/env bash
# Test suite for POST /orders/:id/fail endpoint
set -euo pipefail

source "$(dirname "$0")/test_common.sh"

reset_drones

# Get tokens
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")
DRONE1_TOKEN=$(get_token "drone1" "password")
DRONE2_TOKEN=$(get_token "drone2" "password")

# =============================================================================
# AUTH & AUTHORIZATION
# =============================================================================
test_section "Fail Order - Auth & Authorization"

ORDER_ID=$(create_order "$ENDUSER_TOKEN" 31.9 35.9 32.0 36.0)
req_auth POST /orders/$ORDER_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER_ID/pickup "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/fail without auth -> 401" \
  "req POST /orders/$ORDER_ID/fail '' 401"

run_test "POST /orders/:id/fail with invalid token -> 401" \
  "req_auth POST /orders/$ORDER_ID/fail 'invalid.token' '' 401"

run_test "POST /orders/:id/fail with enduser token -> 403" \
  "req_auth POST /orders/$ORDER_ID/fail '$ENDUSER_TOKEN' '' 403"

run_test "POST /orders/:id/fail with admin token -> 403" \
  "req_auth POST /orders/$ORDER_ID/fail '$ADMIN_TOKEN' '' 403"

# =============================================================================
# INVALID ORDER IDS
# =============================================================================
test_section "Fail Order - Invalid Order IDs"

run_test "POST /orders/:id/fail (invalid format) -> 400" \
  "req_auth POST /orders/abc/fail '$DRONE1_TOKEN' '' 400"

run_test "POST /orders/:id/fail (zero) -> 400" \
  "req_auth POST /orders/0/fail '$DRONE1_TOKEN' '' 400"

run_test "POST /orders/:id/fail (negative) -> 400" \
  "req_auth POST /orders/-1/fail '$DRONE1_TOKEN' '' 400"

run_test "POST /orders/:id/fail (non-existent) -> 404" \
  "req_auth POST /orders/99999/fail '$DRONE1_TOKEN' '' 404"

# =============================================================================
# ASSIGNMENT VALIDATION
# =============================================================================
test_section "Fail Order - Assignment Validation"

run_test "POST /orders/:id/fail (not assigned to drone) -> 404" \
  "req_auth POST /orders/$ORDER_ID/fail '$DRONE2_TOKEN' '' 404"

# =============================================================================
# VALID FAIL FROM PICKED_UP
# =============================================================================
test_section "Fail Order - Valid from picked_up"

run_test "POST /orders/:id/fail (picked_up order) -> 200" \
  "req_auth POST /orders/$ORDER_ID/fail '$DRONE1_TOKEN' '' 200"

verify_json_field ".status" "failed" "$LAST_RESPONSE"

run_test "POST /orders/:id/fail (already failed) -> 409" \
  "req_auth POST /orders/$ORDER_ID/fail '$DRONE1_TOKEN' '' 409"

# =============================================================================
# VALID FAIL FROM RESERVED
# =============================================================================
test_section "Fail Order - Valid from reserved"

reset_drones
ORDER2_ID=$(create_order "$ENDUSER_TOKEN" 32.0 36.0 32.1 36.1)
req_auth POST /orders/$ORDER2_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/fail (reserved order) -> 200" \
  "req_auth POST /orders/$ORDER2_ID/fail '$DRONE1_TOKEN' '' 200"

verify_json_field ".status" "failed" "$LAST_RESPONSE"

# =============================================================================
# STATUS TRANSITION TESTS
# =============================================================================
test_section "Fail Order - Invalid Status Transitions"

# Fail pending order
reset_drones
ORDER3_ID=$(create_order "$ENDUSER_TOKEN" 33.0 37.0 33.1 37.1)

run_test "POST /orders/:id/fail (pending order) -> 404" \
  "req_auth POST /orders/$ORDER3_ID/fail '$DRONE1_TOKEN' '' 404"

# Fail delivered order
ORDER4_ID=$(create_order "$ENDUSER_TOKEN" 34.0 38.0 34.1 38.1)
req_auth POST /orders/$ORDER4_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER4_ID/pickup "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER4_ID/deliver "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/fail (delivered order) -> 409" \
  "req_auth POST /orders/$ORDER4_ID/fail '$DRONE1_TOKEN' '' 409"

# Fail canceled order
reset_drones
ORDER5_ID=$(create_order "$ENDUSER_TOKEN" 35.0 39.0 35.1 39.1)
req_auth POST /orders/$ORDER5_ID/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/fail (canceled order) -> 404" \
  "req_auth POST /orders/$ORDER5_ID/fail '$DRONE1_TOKEN' '' 404"

# TODO: Test database consistency (drone freed, order status updated)
# TODO: Test concurrent fail requests

print_summary "POST /orders/:id/fail"
