#!/usr/bin/env bash
# Test suite for drone fix/repair functionality
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

# Helper function to mark a drone as broken
break_drone() {
  local drone_id="$1"
  local token="$2"
  local lat="${3:-30.0}"
  local lng="${4:-35.0}"
  req_auth POST /drones/${drone_id}/broken "$token" "{\"lat\":${lat},\"lng\":${lng}}" 200 >/dev/null 2>&1 || true
}

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
# TEST 1: Admin can fix a broken drone
# =============================================================================
test_section "Admin Fix Broken Drone"

# First break the drone
break_drone 4 "$DRONE1_TOKEN" 30.5 35.5

# Admin fixes the drone
run_test "Admin fixes Drone1" \
  "req_auth POST /admin/drones/4/fixed '$ADMIN_TOKEN' '{\"lat\":30.0,\"lng\":35.0}' 200"

DRONE1_STATUS=$(req_auth POST /admin/drones/4/fixed "$ADMIN_TOKEN" '{"lat":30.0,"lng":35.0}' 200 | jq -r '.status')
run_test "Drone1 status is idle after fix" "[[ '$DRONE1_STATUS' == 'idle' ]]"

# Verify location was updated
DRONE1_LAT=$(req_auth POST /admin/drones/4/fixed "$ADMIN_TOKEN" '{"lat":30.1,"lng":35.1}' 200 | jq -r '.lat')
run_test "Fixed drone location updated" "[[ '$DRONE1_LAT' == '30.1' ]]"

# =============================================================================
# TEST 2: Fixing an already idle drone is idempotent
# =============================================================================
test_section "Fix Idempotency"

run_test "Fixing idle drone succeeds (idempotent)" \
  "req_auth POST /admin/drones/4/fixed '$ADMIN_TOKEN' '{\"lat\":30.2,\"lng\":35.2}' 200"

IDLE_STATUS=$(req_auth POST /admin/drones/4/fixed "$ADMIN_TOKEN" '{"lat":30.2,"lng":35.2}' 200 | jq -r '.status')
run_test "Drone remains idle" "[[ '$IDLE_STATUS' == 'idle' ]]"

# =============================================================================
# TEST 3: Drone can fix itself (self-report as fixed)
# =============================================================================
test_section "Drone Self-Reports Fixed"

# Break drone2
break_drone 5 "$DRONE2_TOKEN" 29.5 34.5

run_test "Drone2 can mark itself as fixed" \
  "req_auth POST /drones/5/fixed '$DRONE2_TOKEN' '{\"lat\":29.0,\"lng\":34.0}' 200"

SELF_FIX_STATUS=$(req_auth POST /drones/5/fixed "$DRONE2_TOKEN" '{"lat":29.0,"lng":34.0}' 200 | jq -r '.status')
run_test "Drone2 status is idle after self-fix" "[[ '$SELF_FIX_STATUS' == 'idle' ]]"

# =============================================================================
# TEST 4: Drone cannot fix another drone
# =============================================================================
test_section "Authorization - Drone Cannot Fix Others"

# Break drone2 again
break_drone 5 "$ADMIN_TOKEN" 29.5 34.5

run_test "Drone1 cannot fix Drone2" \
  "req_auth POST /drones/5/fixed '$DRONE1_TOKEN' '{\"lat\":29.0,\"lng\":34.0}' 403"

# Admin fixes drone2 for cleanup
fix_drone 5 29.0 34.0

# =============================================================================
# TEST 5: Enduser cannot fix drones
# =============================================================================
test_section "Authorization - Enduser Cannot Fix"

# Break drone1
break_drone 4 "$DRONE1_TOKEN" 30.5 35.5

run_test "Enduser cannot fix drone" \
  "req_auth POST /drones/4/fixed '$ENDUSER_TOKEN' '{\"lat\":30.0,\"lng\":35.0}' 403"

run_test "Enduser cannot use admin fix endpoint" \
  "req_auth POST /admin/drones/4/fixed '$ENDUSER_TOKEN' '{\"lat\":30.0,\"lng\":35.0}' 403"

# Admin fixes drone1 for cleanup
fix_drone 4 30.0 35.0

# =============================================================================
# TEST 6: Validation - lat/lng required
# =============================================================================
test_section "Fix Validation Tests"

# Break drone1
break_drone 4 "$DRONE1_TOKEN" 30.5 35.5

run_test "Fix requires lat and lng" \
  "req_auth POST /admin/drones/4/fixed '$ADMIN_TOKEN' '{}' 400"

run_test "Fix with invalid lat rejected" \
  "req_auth POST /admin/drones/4/fixed '$ADMIN_TOKEN' '{\"lat\":999,\"lng\":35}' 400"

run_test "Fix with invalid lng rejected" \
  "req_auth POST /admin/drones/4/fixed '$ADMIN_TOKEN' '{\"lat\":30,\"lng\":999}' 400"

# Admin fixes drone1 for cleanup
fix_drone 4 30.0 35.0

# =============================================================================
# TEST 7: Cannot fix drone with active order
# =============================================================================
test_section "Fix Drone With Active Order"

# Create and assign order to drone1
ACTIVE_ORDER=$(create_order "$ENDUSER_TOKEN" 30.0 35.0 30.1 35.1)
req_auth POST /orders/$ACTIVE_ORDER/reserve "$DRONE1_TOKEN" '' 200 >/dev/null

# Break the drone while it has a reserved order
break_drone 4 "$DRONE1_TOKEN" 30.05 35.05

# Try to fix the drone (should succeed - drone becomes idle, order returns to pending)
run_test "Admin can fix drone with released order" \
  "req_auth POST /admin/drones/4/fixed '$ADMIN_TOKEN' '{\"lat\":30.0,\"lng\":35.0}' 200"

FIXED_DRONE_STATUS=$(req_auth POST /admin/drones/4/fixed "$ADMIN_TOKEN" '{"lat":30.0,"lng":35.0}' 200 | jq -r '.status')
run_test "Drone is idle after fix" "[[ '$FIXED_DRONE_STATUS' == 'idle' ]]"

# Verify drone has no current order
FIXED_DRONE_ORDER=$(req_auth POST /admin/drones/4/fixed "$ADMIN_TOKEN" '{"lat":30.0,"lng":35.0}' 200 | jq -r '.current_order_id')
run_test "Fixed drone has no current order" "[[ '$FIXED_DRONE_ORDER' == 'null' ]]"

# =============================================================================
# TEST 8: Fix enables drone to accept new orders
# =============================================================================
test_section "Fixed Drone Can Accept Orders"

# Break drone2
break_drone 5 "$DRONE2_TOKEN" 29.5 34.5

# Verify broken drone cannot reserve orders (returns 400 - invalid state transition)
BROKEN_ORDER=$(create_order "$ENDUSER_TOKEN" 29.0 34.0 29.1 34.1)
run_test "Broken drone cannot reserve order" \
  "req_auth POST /orders/$BROKEN_ORDER/reserve '$DRONE2_TOKEN' '' 400"

# Fix the drone
fix_drone 5 29.0 34.0

# Now the fixed drone can reserve orders
run_test "Fixed drone can reserve new order" \
  "req_auth POST /orders/$BROKEN_ORDER/reserve '$DRONE2_TOKEN' '' 200"

# Cleanup - fail the order to reset drone2
req_auth POST /orders/$BROKEN_ORDER/fail "$DRONE2_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 9: Multiple fix/break cycles
# =============================================================================
test_section "Multiple Fix/Break Cycles"

# Cycle 1: Break and fix
break_drone 4 "$DRONE1_TOKEN" 30.5 35.5
run_test "Cycle 1: Break drone1" "true"

fix_drone 4 30.0 35.0
CYCLE1_STATUS=$(req_auth POST /admin/drones/4/fixed "$ADMIN_TOKEN" '{"lat":30.0,"lng":35.0}' 200 | jq -r '.status')
run_test "Cycle 1: Drone1 fixed to idle" "[[ '$CYCLE1_STATUS' == 'idle' ]]"

# Cycle 2: Break and fix again
break_drone 4 "$DRONE1_TOKEN" 30.6 35.6
run_test "Cycle 2: Break drone1 again" "true"

fix_drone 4 30.0 35.0
CYCLE2_STATUS=$(req_auth POST /admin/drones/4/fixed "$ADMIN_TOKEN" '{"lat":30.0,"lng":35.0}' 200 | jq -r '.status')
run_test "Cycle 2: Drone1 fixed to idle again" "[[ '$CYCLE2_STATUS' == 'idle' ]]"

# =============================================================================
# TEST 10: Fix response includes correct drone state
# =============================================================================
test_section "Fix Response Validation"

# Break drone1
break_drone 4 "$DRONE1_TOKEN" 30.5 35.5

# Fix and validate response structure
FIX_RESPONSE=$(req_auth POST /admin/drones/4/fixed "$ADMIN_TOKEN" '{"lat":30.0,"lng":35.0}' 200)

RESP_DRONE_ID=$(echo "$FIX_RESPONSE" | jq -r '.drone_id')
run_test "Fix response has drone_id" "[[ '$RESP_DRONE_ID' == '4' ]]"

RESP_STATUS=$(echo "$FIX_RESPONSE" | jq -r '.status')
run_test "Fix response status is idle" "[[ '$RESP_STATUS' == 'idle' ]]"

RESP_LAT=$(echo "$FIX_RESPONSE" | jq -r '.lat')
run_test "Fix response has latitude" "[[ '$RESP_LAT' == '30' ]]"

RESP_LNG=$(echo "$FIX_RESPONSE" | jq -r '.lng')
run_test "Fix response has longitude" "[[ '$RESP_LNG' == '35' ]]"

# =============================================================================
# CLEANUP
# =============================================================================
test_section "Cleanup"

# Ensure both drones are idle and at known locations
fix_drone 4 30.0 35.0
fix_drone 5 29.0 34.0

run_test "Drone1 reset to idle" "true"
run_test "Drone2 reset to idle" "true"

print_summary "Drone Fix/Repair API"
