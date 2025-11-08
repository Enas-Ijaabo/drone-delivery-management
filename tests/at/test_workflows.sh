#!/usr/bin/env bash
# Test suite for workflow integration tests
set -euo pipefail

source "$(dirname "$0")/test_common.sh"
set +e
set +u
set +o pipefail

reset_drones

ENDUSER_TOKEN=$(get_token "enduser1" "password")
DRONE1_TOKEN=$(get_token "drone1" "password")

# =============================================================================
# HAPPY PATH: RESERVE -> PICKUP -> DELIVER
# =============================================================================
test_section "Workflow - Happy Path"

ORDER_ID=$(create_order "$ENDUSER_TOKEN" 31.9 35.9 32.0 36.0)

run_test "Workflow: Reserve order -> 200" \
  "req_auth POST /orders/$ORDER_ID/reserve '$DRONE1_TOKEN' '' 200"
run_test "workflow reserved status" "verify_json_field '.status' 'reserved'"

run_test "Workflow: Pickup order -> 200" \
  "req_auth POST /orders/$ORDER_ID/pickup '$DRONE1_TOKEN' '' 200"
run_test "workflow picked_up status" "verify_json_field '.status' 'picked_up'"

run_test "Workflow: Deliver order -> 200" \
  "req_auth POST /orders/$ORDER_ID/deliver '$DRONE1_TOKEN' '' 200"
run_test "workflow delivered status" "verify_json_field '.status' 'delivered'"

# =============================================================================
# FAILURE PATH: RESERVE -> PICKUP -> FAIL
# =============================================================================
test_section "Workflow - Failure After Pickup"

ORDER2_ID=$(create_order "$ENDUSER_TOKEN" 32.0 36.0 32.1 36.1)

run_test "Workflow: Reserve order -> 200" \
  "req_auth POST /orders/$ORDER2_ID/reserve '$DRONE1_TOKEN' '' 200"

run_test "Workflow: Pickup order -> 200" \
  "req_auth POST /orders/$ORDER2_ID/pickup '$DRONE1_TOKEN' '' 200"

run_test "Workflow: Fail order -> 200" \
  "req_auth POST /orders/$ORDER2_ID/fail '$DRONE1_TOKEN' '' 200"
run_test "workflow failed status after pickup" "verify_json_field '.status' 'failed'"

# =============================================================================
# FAILURE PATH: RESERVE -> FAIL (WITHOUT PICKUP)
# =============================================================================
test_section "Workflow - Failure After Reserve"

ORDER3_ID=$(create_order "$ENDUSER_TOKEN" 33.0 37.0 33.1 37.1)

run_test "Workflow: Reserve order -> 200" \
  "req_auth POST /orders/$ORDER3_ID/reserve '$DRONE1_TOKEN' '' 200"

run_test "Workflow: Fail order (without pickup) -> 200" \
  "req_auth POST /orders/$ORDER3_ID/fail '$DRONE1_TOKEN' '' 200"
run_test "workflow failed status after reserve" "verify_json_field '.status' 'failed'"

# =============================================================================
# CANCEL BEFORE RESERVE
# =============================================================================
test_section "Workflow - Cancel Before Reserve"

ORDER4_ID=$(create_order "$ENDUSER_TOKEN" 34.0 38.0 34.1 38.1)

run_test "Workflow: Cancel order -> 200" \
  "req_auth POST /orders/$ORDER4_ID/cancel '$ENDUSER_TOKEN' '' 200"

run_test "Workflow: Cannot reserve canceled order -> 409" \
  "req_auth POST /orders/$ORDER4_ID/reserve '$DRONE1_TOKEN' '' 409"

# =============================================================================
# MULTIPLE SEQUENTIAL ORDERS
# =============================================================================
test_section "Workflow - Multiple Sequential Orders"

ORDER5_ID=$(create_order "$ENDUSER_TOKEN" 35.0 39.0 35.1 39.1)
ORDER6_ID=$(create_order "$ENDUSER_TOKEN" 36.0 40.0 36.1 40.1)

run_test "Workflow: Complete first order" \
  "req_auth POST /orders/$ORDER5_ID/reserve '$DRONE1_TOKEN' '' 200 && \
   req_auth POST /orders/$ORDER5_ID/pickup '$DRONE1_TOKEN' '' 200 && \
   req_auth POST /orders/$ORDER5_ID/deliver '$DRONE1_TOKEN' '' 200"

run_test "Workflow: Drone can handle second order" \
  "req_auth POST /orders/$ORDER6_ID/reserve '$DRONE1_TOKEN' '' 200"
run_test "second workflow reserved status" "verify_json_field '.status' 'reserved'"

# TODO: Test concurrent operations (two drones, two orders)
# TODO: Test order reassignment after failure
# TODO: Test handoff scenarios (if implemented)

print_summary "Workflow Integration"
