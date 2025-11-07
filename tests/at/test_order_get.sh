#!/usr/bin/env bash
# Test suite for GET /orders/:id endpoint
set -euo pipefail

source "$(dirname "$0")/test_common.sh"

# Get tokens
ENDUSER_TOKEN=$(get_token "enduser1" "password")
ENDUSER2_TOKEN=$(get_token "enduser2" "password")

# =============================================================================
# AUTH & AUTHORIZATION
# =============================================================================
test_section "GET Order - Auth & Authorization"

ORDER_ID=$(create_order "$ENDUSER_TOKEN" 10.0 20.0 20.0 30.0)

run_test "GET /orders/:id with invalid token -> 401" \
  "req_auth GET /orders/$ORDER_ID 'invalid.token' '' 401"

ORDER2_ID=$(create_order "$ENDUSER2_TOKEN" 11.0 21.0 21.0 31.0)

run_test "GET /orders/:id (not owned by user) -> 403" \
  "req_auth GET /orders/$ORDER2_ID '$ENDUSER_TOKEN' '' 403"

# =============================================================================
# INVALID ORDER IDS
# =============================================================================
test_section "GET Order - Invalid Order IDs"

run_test "GET /orders/:id (invalid format) -> 400" \
  "req_auth GET /orders/abc '$ENDUSER_TOKEN' '' 400"

run_test "GET /orders/:id (zero) -> 400" \
  "req_auth GET /orders/0 '$ENDUSER_TOKEN' '' 400"

run_test "GET /orders/:id (negative) -> 400" \
  "req_auth GET /orders/-1 '$ENDUSER_TOKEN' '' 400"

run_test "GET /orders/:id (non-existent) -> 404" \
  "req_auth GET /orders/99999 '$ENDUSER_TOKEN' '' 404"

# =============================================================================
# SUCCESSFUL GET - WITHOUT DRONE
# =============================================================================
test_section "GET Order - Without Drone"

run_test "GET /orders/:id (pending order) -> 200" \
  "req_auth GET /orders/$ORDER_ID '$ENDUSER_TOKEN' '' 200 && \
   verify_json_field '.status' 'pending' && \
   verify_json_has_field '.order_id' && \
   verify_json_has_field '.pickup' && \
   verify_json_has_field '.dropoff' && \
   verify_json_field_absent '.assigned_drone_id' && \
   verify_json_field_absent '.drone_location' && \
   verify_json_field_absent '.eta_minutes'"

# =============================================================================
# SUCCESSFUL GET - WITH DRONE
# =============================================================================
test_section "GET Order - With Drone"

reset_drones  # Ensure drones are in idle state
DRONE_TOKEN=$(get_token "drone1" "password")
ORDER3_ID=$(create_order "$ENDUSER_TOKEN" 31.9 35.9 32.0 36.0)

# Reserve order with drone
req_auth POST /orders/$ORDER3_ID/reserve "$DRONE_TOKEN" '' 200 >/dev/null

run_test "GET /orders/:id (reserved order with drone) -> 200" \
  "req_auth GET /orders/$ORDER3_ID '$ENDUSER_TOKEN' '' 200 && \
   verify_json_field '.status' 'reserved' && \
   verify_json_has_field '.assigned_drone_id' && \
   verify_json_has_field '.drone_location' && \
   verify_json_has_field '.eta_minutes'"

# Pickup order
req_auth POST /orders/$ORDER3_ID/pickup "$DRONE_TOKEN" '' 200 >/dev/null

run_test "GET /orders/:id (picked_up order with drone) -> 200" \
  "req_auth GET /orders/$ORDER3_ID '$ENDUSER_TOKEN' '' 200 && \
   verify_json_field '.status' 'picked_up' && \
   verify_json_has_field '.drone_location' && \
   verify_json_has_field '.eta_minutes'"

# Deliver order
req_auth POST /orders/$ORDER3_ID/deliver "$DRONE_TOKEN" '' 200 >/dev/null

run_test "GET /orders/:id (delivered order) -> 200" \
  "req_auth GET /orders/$ORDER3_ID '$ENDUSER_TOKEN' '' 200 && \
   verify_json_field '.status' 'delivered'"

print_summary "GET /orders/:id"
