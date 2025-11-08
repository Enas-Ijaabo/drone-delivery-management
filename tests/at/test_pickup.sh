#!/usr/bin/env bash
# Test suite for POST /orders/:id/pickup endpoint
set -euo pipefail

source "$(dirname "$0")/test_common.sh"
set +e
set +u
set +o pipefail

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

reset_drones

# Get tokens
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")
DRONE1_TOKEN=$(get_token "drone1" "password")
DRONE2_TOKEN=$(get_token "drone2" "password")

# =============================================================================
# AUTH & AUTHORIZATION
# =============================================================================
test_section "Pickup Order - Auth & Authorization"

ORDER_ID=$(create_order "$ENDUSER_TOKEN" 31.9 35.9 32.0 36.0)
req_auth POST /orders/$ORDER_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/pickup without auth -> 401" \
  "req POST /orders/$ORDER_ID/pickup '' 401"

run_test "POST /orders/:id/pickup with invalid token -> 401" \
  "req_auth POST /orders/$ORDER_ID/pickup 'invalid.token' '' 401"

run_test "POST /orders/:id/pickup with enduser token -> 403" \
  "req_auth POST /orders/$ORDER_ID/pickup '$ENDUSER_TOKEN' '' 403"

run_test "POST /orders/:id/pickup with admin token -> 403" \
  "req_auth POST /orders/$ORDER_ID/pickup '$ADMIN_TOKEN' '' 403"

# =============================================================================
# INVALID ORDER IDS
# =============================================================================
test_section "Pickup Order - Invalid Order IDs"

run_test "POST /orders/:id/pickup (invalid format) -> 400" \
  "req_auth POST /orders/abc/pickup '$DRONE1_TOKEN' '' 400"

run_test "POST /orders/:id/pickup (zero) -> 400" \
  "req_auth POST /orders/0/pickup '$DRONE1_TOKEN' '' 400"

run_test "POST /orders/:id/pickup (negative) -> 400" \
  "req_auth POST /orders/-1/pickup '$DRONE1_TOKEN' '' 400"

run_test "POST /orders/:id/pickup (non-existent) -> 404" \
  "req_auth POST /orders/99999/pickup '$DRONE1_TOKEN' '' 404"

# =============================================================================
# ASSIGNMENT VALIDATION
# =============================================================================
test_section "Pickup Order - Assignment Validation"

run_test "POST /orders/:id/pickup (not assigned to drone) -> 404" \
  "req_auth POST /orders/$ORDER_ID/pickup '$DRONE2_TOKEN' '' 404"

# =============================================================================
# VALID PICKUP
# =============================================================================
test_section "Pickup Order - Valid Requests"

run_test "POST /orders/:id/pickup (reserved order) -> 200" \
  "req_auth POST /orders/$ORDER_ID/pickup '$DRONE1_TOKEN' '' 200"

run_test "pickup sets status picked_up" "verify_json_field '.status' 'picked_up'"

run_test "POST /orders/:id/pickup (already picked up) -> 409" \
  "req_auth POST /orders/$ORDER_ID/pickup '$DRONE1_TOKEN' '' 409"

# =============================================================================
# STATUS TRANSITION TESTS
# =============================================================================
test_section "Pickup Order - Invalid Status Transitions"

# Pickup pending order (not reserved)
ORDER2_ID=$(create_order "$ENDUSER_TOKEN" 32.0 36.0 32.1 36.1)

run_test "POST /orders/:id/pickup (pending order) -> 404" \
  "req_auth POST /orders/$ORDER2_ID/pickup '$DRONE1_TOKEN' '' 404"

# Pickup delivered order
req_auth POST /orders/$ORDER_ID/deliver "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/pickup (delivered order) -> 409" \
  "req_auth POST /orders/$ORDER_ID/pickup '$DRONE1_TOKEN' '' 409"

# Pickup canceled order
ORDER3_ID=$(create_order "$ENDUSER_TOKEN" 33.0 37.0 33.1 37.1)
req_auth POST /orders/$ORDER3_ID/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/pickup (canceled order) -> 404" \
  "req_auth POST /orders/$ORDER3_ID/pickup '$DRONE1_TOKEN' '' 404"

# Pickup failed order
reset_drones
ORDER4_ID=$(create_order "$ENDUSER_TOKEN" 34.0 38.0 34.1 38.1)
req_auth POST /orders/$ORDER4_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER4_ID/pickup "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER4_ID/fail "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "POST /orders/:id/pickup (failed order) -> 409" \
  "req_auth POST /orders/$ORDER4_ID/pickup '$DRONE1_TOKEN' '' 409"

# TODO: Test pickup with wrong drone status (idle, delivering, broken)
# TODO: Test database consistency (drone status, order status updated)
# TODO: Test concurrent pickup requests

print_summary "POST /orders/:id/pickup"
