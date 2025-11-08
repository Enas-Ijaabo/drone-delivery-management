#!/usr/bin/env bash
# Test suite for POST /orders/:id/deliver endpoint
set -euo pipefail
source "$(dirname "$0")/test_common.sh"
set +e
set +u
set +o pipefail

# Get tokens
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")
DRONE1_TOKEN=$(get_token "drone1" "password")
DRONE2_TOKEN=$(get_token "drone2" "password")

# =============================================================================
# AUTH & AUTHORIZATION
# =============================================================================
test_section "Deliver Order - Auth & Authorization"

ORDER_ID=$(create_order "$ENDUSER_TOKEN" 31.9 35.9 32.0 36.0)
req_auth POST /orders/$ORDER_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER_ID/pickup "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/deliver without auth -> 401" \
  "req POST /orders/$ORDER_ID/deliver '' 401"

run_test "POST /orders/:id/deliver with invalid token -> 401" \
  "req_auth POST /orders/$ORDER_ID/deliver 'invalid.token' '' 401"

run_test "POST /orders/:id/deliver with enduser token -> 403" \
  "req_auth POST /orders/$ORDER_ID/deliver '$ENDUSER_TOKEN' '' 403"

run_test "POST /orders/:id/deliver with admin token -> 403" \
  "req_auth POST /orders/$ORDER_ID/deliver '$ADMIN_TOKEN' '' 403"

# =============================================================================
# INVALID ORDER IDS
# =============================================================================
test_section "Deliver Order - Invalid Order IDs"

run_test "POST /orders/:id/deliver (invalid format) -> 400" \
  "req_auth POST /orders/abc/deliver $DRONE1_TOKEN '' 400"

run_test "POST /orders/:id/deliver (zero) -> 400" \
  "req_auth POST /orders/0/deliver $DRONE1_TOKEN '' 400"

run_test "POST /orders/:id/deliver (negative) -> 400" \
  "req_auth POST /orders/-1/deliver $DRONE1_TOKEN '' 400"

run_test "POST /orders/:id/deliver (non-existent) -> 404" \
  "req_auth POST /orders/99999/deliver $DRONE1_TOKEN '' 404"

# =============================================================================
# ASSIGNMENT VALIDATION
# =============================================================================
test_section "Deliver Order - Assignment Validation"

run_test "POST /orders/:id/deliver (not assigned to drone) -> 404" \
  "req_auth POST /orders/$ORDER_ID/deliver $DRONE2_TOKEN '' 404"

# =============================================================================
# VALID DELIVERY
# =============================================================================
test_section "Deliver Order - Valid Requests"

run_test "POST /orders/:id/deliver (picked_up order) -> 200" \
  "req_auth POST /orders/$ORDER_ID/deliver $DRONE1_TOKEN '' 200"

run_test "delivery sets status delivered" "verify_json_field '.status' 'delivered'"

run_test "POST /orders/:id/deliver (already delivered) -> 409" \
  "req_auth POST /orders/$ORDER_ID/deliver $DRONE1_TOKEN '' 409"

# Cleanup: ORDER_ID is delivered, drone is now idle

# =============================================================================
# STATUS TRANSITION TESTS
# =============================================================================
test_section "Deliver Order - Invalid Status Transitions"

# Deliver pending order
ORDER2_ID=$(create_order "$ENDUSER_TOKEN" 32.0 36.0 32.1 36.1)

run_test "POST /orders/:id/deliver (pending order) -> 404" \
  "req_auth POST /orders/$ORDER2_ID/deliver $DRONE1_TOKEN '' 404"

# Deliver reserved order (not picked up yet)
req_auth POST /orders/$ORDER2_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/deliver (reserved order) -> 409" \
  "req_auth POST /orders/$ORDER2_ID/deliver $DRONE1_TOKEN '' 409"

# Cleanup: ORDER2_ID is reserved, fail it to free drone
req_auth POST /orders/$ORDER2_ID/fail "$DRONE1_TOKEN" '' 200 >/dev/null

# Deliver canceled order
ORDER3_ID=$(create_order "$ENDUSER_TOKEN" 33.0 37.0 33.1 37.1)
req_auth POST /orders/$ORDER3_ID/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/deliver (canceled order) -> 404" \
  "req_auth POST /orders/$ORDER3_ID/deliver $DRONE1_TOKEN '' 404"

# Deliver failed order
ORDER4_ID=$(create_order "$ENDUSER_TOKEN" 34.0 38.0 34.1 38.1)
req_auth POST /orders/$ORDER4_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER4_ID/pickup "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER4_ID/fail "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/deliver (failed order) -> 409" \
  "req_auth POST /orders/$ORDER4_ID/deliver $DRONE1_TOKEN '' 409"

# TODO: Test deliver with wrong drone status (idle, reserved, broken)
# TODO: Test database consistency (drone freed, order status updated)
# TODO: Test concurrent deliver requests

print_summary "POST /orders/:id/deliver"
