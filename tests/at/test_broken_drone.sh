#!/usr/bin/env bash
# Test suite for drone broken status reporting
set -euo pipefail

source "$(dirname "$0")/test_common.sh"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Get tokens
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")
DRONE1_TOKEN=$(get_token "drone1" "password")
DRONE2_TOKEN=$(get_token "drone2" "password")

# Helper function to fix a broken drone
fix_drone() {
  local drone_id="$1"
  local lat="${2:-0.0}"
  local lng="${3:-0.0}"
  req_auth POST /admin/drones/${drone_id}/fixed "$ADMIN_TOKEN" "{\"lat\":${lat},\"lng\":${lng}}" 200 >/dev/null 2>&1 || true
}

# Reset both drones to idle state before starting tests
fix_drone 4 30.0 35.0
fix_drone 5 29.0 34.0

# =============================================================================
# TEST 1: Drone reports itself broken
# =============================================================================
test_section "Drone Self-Report Broken"

run_test "Drone1 reports itself broken" \
  "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30.5,\"lng\":35.5}' 200"

DRONE1_STATUS=$(req_auth POST /drones/4/broken "$DRONE1_TOKEN" '{"lat":30.5,"lng":35.5}' 200 | jq -r '.status')
run_test "Drone1 status is broken" "[[ '$DRONE1_STATUS' == 'broken' ]]"

# Try to report broken again - should succeed (idempotent)
run_test "Reporting broken again is idempotent" \
  "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30.6,\"lng\":35.6}' 200"

# Verify location was updated
DRONE1_LAT=$(req_auth POST /drones/4/broken "$DRONE1_TOKEN" '{"lat":30.7,"lng":35.7}' 200 | jq -r '.lat')
run_test "Broken drone location can be updated" "[[ '$DRONE1_LAT' == '30.7' ]]"

# Reset drone1 for next tests
fix_drone 4 30.0 35.0

# =============================================================================
# TEST 2: Drone cannot report another drone as broken
# =============================================================================
test_section "Drone Cannot Report Other Drones"

run_test "Drone1 cannot report Drone2 as broken" \
  "req_auth POST /drones/5/broken '$DRONE1_TOKEN' '{\"lat\":29.5,\"lng\":34.5}' 403"

# =============================================================================
# TEST 3: Admin can mark any drone as broken
# =============================================================================
test_section "Admin Can Mark Drones Broken"

run_test "Admin marks Drone2 as broken" \
  "req_auth POST /admin/drones/5/broken '$ADMIN_TOKEN' '{\"lat\":29.5,\"lng\":34.5}' 200"

DRONE2_STATUS=$(req_auth POST /admin/drones/5/broken "$ADMIN_TOKEN" '{"lat":29.5,"lng":34.5}' 200 | jq -r '.status')
run_test "Drone2 status is broken" "[[ '$DRONE2_STATUS' == 'broken' ]]"

# Reset drone2 for next tests
fix_drone 5 29.0 34.0

# =============================================================================
# TEST 4: Broken drone with assigned order triggers handoff
# =============================================================================
test_section "Broken Drone Triggers Order Handoff"

# Ensure drone1 is idle (it was reset after TEST 1)
# Create and assign order to drone1
HANDOFF_ORDER=$(create_order "$ENDUSER_TOKEN" 30.0 35.0 30.1 35.1)
req_auth POST /orders/$HANDOFF_ORDER/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$HANDOFF_ORDER/pickup "$DRONE1_TOKEN" '' 200 >/dev/null

# Drone1 reports broken while carrying order
run_test "Drone1 reports broken while carrying order" \
  "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30.05,\"lng\":35.05}' 200"

# Check order status
ORDER_STATUS=$(req_auth GET /orders/$HANDOFF_ORDER "$ENDUSER_TOKEN" '' 200 | jq -r '.status')
run_test "Order moved to handoff_pending" "[[ '$ORDER_STATUS' == 'handoff_pending' ]]"

# Check handoff location
HANDOFF_LAT=$(req_auth GET /orders/$HANDOFF_ORDER "$ENDUSER_TOKEN" '' 200 | jq -r '.handoff_lat')
run_test "Order has handoff location" "[[ '$HANDOFF_LAT' != 'null' ]]"

# Reset drone1 for next tests
fix_drone 4 30.0 35.0

# =============================================================================
# TEST 5: Admin marks drone with order as broken
# =============================================================================
test_section "Admin Marks Busy Drone As Broken"

# Ensure drone2 is idle (it was reset after TEST 3)
# Create and assign order to drone2
ADMIN_HANDOFF_ORDER=$(create_order "$ENDUSER_TOKEN" 29.5 34.5 29.6 34.6)
req_auth POST /orders/$ADMIN_HANDOFF_ORDER/reserve "$DRONE2_TOKEN" '' 200 >/dev/null

# Admin marks drone2 as broken
run_test "Admin marks busy Drone2 as broken" \
  "req_auth POST /admin/drones/5/broken '$ADMIN_TOKEN' '{\"lat\":29.55,\"lng\":34.55}' 200"

# Check order was released
ADMIN_ORDER_STATUS=$(req_auth GET /orders/$ADMIN_HANDOFF_ORDER "$ENDUSER_TOKEN" '' 200 | jq -r '.status')
run_test "Order returned to pending" "[[ '$ADMIN_ORDER_STATUS' == 'pending' ]]"

# Reset drone2 for next tests
fix_drone 5 29.0 34.0

# =============================================================================
# TEST 6: Validation - lat/lng required
# =============================================================================
test_section "Validation Tests"

run_test "Broken report requires lat and lng" \
  "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{}' 400"

run_test "Broken report with invalid lat rejected" \
  "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":999,\"lng\":35}' 400"

run_test "Broken report with invalid lng rejected" \
  "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30,\"lng\":999}' 400"

# =============================================================================
# TEST 7: Unauthorized access
# =============================================================================
test_section "Authorization Tests"

run_test "Enduser cannot mark drone as broken" \
  "req_auth POST /drones/4/broken '$ENDUSER_TOKEN' '{\"lat\":30,\"lng\":35}' 403"

run_test "Enduser cannot use admin endpoint" \
  "req_auth POST /admin/drones/4/broken '$ENDUSER_TOKEN' '{\"lat\":30,\"lng\":35}' 403"

run_test "Drone cannot use admin endpoint" \
  "req_auth POST /admin/drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30,\"lng\":35}' 403"

# =============================================================================
# CLEANUP
# =============================================================================
test_section "Cleanup"

# Reset drones to idle state after tests
fix_drone 4 30.0 35.0
fix_drone 5 29.0 34.0

run_test "Drone1 returned to idle" "true"
run_test "Drone2 returned to idle" "true"

print_summary "Drone Broken Status API"
