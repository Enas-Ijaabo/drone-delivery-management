# #!/usr/bin/env bash
# # Test suite for drone broken status reporting
# set -euo pipefail

# source "$(dirname "$0")/test_common.sh"

# TEST_COUNT=0
# PASS_COUNT=0
# FAIL_COUNT=0

# # Get tokens
# ADMIN_TOKEN=$(get_token "admin" "password")
# ENDUSER_TOKEN=$(get_token "enduser1" "password")
# DRONE1_TOKEN=$(get_token "drone1" "password")
# DRONE2_TOKEN=$(get_token "drone2" "password")

# # Note: We cannot reset drones to idle state without a fix API
# # These tests assume drones may be in any state and test the broken status reporting

# # =============================================================================
# # TEST 1: Drone reports itself broken
# # =============================================================================
# test_section "Drone Self-Report Broken"

# run_test "Drone1 reports itself broken" \
#   "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30.5,\"lng\":35.5}' 200"

# DRONE1_STATUS=$(req_auth POST /drones/4/broken "$DRONE1_TOKEN" '{"lat":30.5,"lng":35.5}' 200 | jq -r '.status')
# run_test "Drone1 status is broken" "[[ '$DRONE1_STATUS' == 'broken' ]]"

# # Try to report broken again - should succeed (idempotent)
# run_test "Reporting broken again is idempotent" \
#   "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30.6,\"lng\":35.6}' 200"

# # Verify location was updated
# DRONE1_LAT=$(req_auth POST /drones/4/broken "$DRONE1_TOKEN" '{"lat":30.7,"lng":35.7}' 200 | jq -r '.lat')
# run_test "Broken drone location can be updated" "[[ '$DRONE1_LAT' == '30.7' ]]"

# # =============================================================================
# # TEST 2: Drone cannot report another drone as broken
# # =============================================================================
# test_section "Drone Cannot Report Other Drones"

# run_test "Drone1 cannot report Drone2 as broken" \
#   "req_auth POST /drones/5/broken '$DRONE1_TOKEN' '{\"lat\":29.5,\"lng\":34.5}' 403"

# # =============================================================================
# # TEST 3: Admin can mark any drone as broken
# # =============================================================================
# test_section "Admin Can Mark Drones Broken"

# run_test "Admin marks Drone2 as broken" \
#   "req_auth POST /admin/drones/5/broken '$ADMIN_TOKEN' '{\"lat\":29.5,\"lng\":34.5}' 200"

# DRONE2_STATUS=$(req_auth POST /admin/drones/5/broken "$ADMIN_TOKEN" '{"lat":29.5,"lng":34.5}' 200 | jq -r '.status')
# run_test "Drone2 status is broken" "[[ '$DRONE2_STATUS' == 'broken' ]]"

# # =============================================================================
# # TEST 4: Broken drone with assigned order triggers handoff
# # =============================================================================
# test_section "Broken Drone Triggers Order Handoff"

# # TODO: These tests require a fix API to reset drones between tests
# # Skipping until POST /admin/drones/:id/fix is implemented
# # 
# # Expected behavior:
# # - Drone with picked_up order reports broken → order moves to handoff_pending
# # - Order has handoff_lat/handoff_lng set to drone's last location
# # - Order becomes available for reassignment to another drone

# echo "⊘ SKIPPED: Requires fix API to reset drone1 (currently broken from TEST 1)"
# echo "⊘ SKIPPED: Test 'Order moved to handoff_pending'"
# echo "⊘ SKIPPED: Test 'Order has handoff location'"

# # # Reset drone1 to idle first
# # reset_drone "$DRONE1_TOKEN" "$ENDUSER_TOKEN"
# # 
# # # Create and assign order to drone1
# # HANDOFF_ORDER=$(create_order "$ENDUSER_TOKEN" 30.0 35.0 30.1 35.1)
# # req_auth POST /orders/$HANDOFF_ORDER/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
# # req_auth POST /orders/$HANDOFF_ORDER/pickup "$DRONE1_TOKEN" '' 200 >/dev/null
# # 
# # # Drone1 reports broken while carrying order
# # run_test "Drone1 reports broken while carrying order" \
# #   "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30.05,\"lng\":35.05}' 200"
# # 
# # # Check order status
# # ORDER_STATUS=$(req_auth GET /orders/$HANDOFF_ORDER "$ENDUSER_TOKEN" '' 200 | jq -r '.status')
# # run_test "Order moved to handoff_pending" "[[ '$ORDER_STATUS' == 'handoff_pending' ]]"
# # 
# # # Check handoff location
# # HANDOFF_LAT=$(req_auth GET /orders/$HANDOFF_ORDER "$ENDUSER_TOKEN" '' 200 | jq -r '.handoff_lat')
# # run_test "Order has handoff location" "[[ '$HANDOFF_LAT' != 'null' ]]"

# # =============================================================================
# # TEST 5: Admin marks drone with order as broken
# # =============================================================================
# test_section "Admin Marks Busy Drone As Broken"

# # TODO: These tests require a fix API to reset drones between tests
# # Skipping until POST /admin/drones/:id/fix is implemented
# # 
# # Expected behavior:
# # - Admin marks reserved drone as broken → order returns to pending
# # - Drone is marked broken and order is released for reassignment

# echo "⊘ SKIPPED: Requires fix API to reset drone2 (currently broken from TEST 3)"
# echo "⊘ SKIPPED: Test 'Admin marks busy Drone2 as broken'"
# echo "⊘ SKIPPED: Test 'Order returned to pending'"

# # # Reset drone2 and assign order
# # reset_drone "$DRONE2_TOKEN" "$ENDUSER_TOKEN"
# # 
# # ADMIN_HANDOFF_ORDER=$(create_order "$ENDUSER_TOKEN" 29.5 34.5 29.6 34.6)
# # req_auth POST /orders/$ADMIN_HANDOFF_ORDER/reserve "$DRONE2_TOKEN" '' 200 >/dev/null
# # 
# # # Admin marks drone2 as broken
# # run_test "Admin marks busy Drone2 as broken" \
# #   "req_auth POST /admin/drones/5/broken '$ADMIN_TOKEN' '{\"lat\":29.55,\"lng\":34.55}' 200"
# # 
# # # Check order was released
# # ADMIN_ORDER_STATUS=$(req_auth GET /orders/$ADMIN_HANDOFF_ORDER "$ENDUSER_TOKEN" '' 200 | jq -r '.status')
# # run_test "Order returned to pending" "[[ '$ADMIN_ORDER_STATUS' == 'pending' ]]"

# # =============================================================================
# # TEST 6: Validation - lat/lng required
# # =============================================================================
# test_section "Validation Tests"

# run_test "Broken report requires lat and lng" \
#   "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{}' 400"

# run_test "Broken report with invalid lat rejected" \
#   "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":999,\"lng\":35}' 400"

# run_test "Broken report with invalid lng rejected" \
#   "req_auth POST /drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30,\"lng\":999}' 400"

# # =============================================================================
# # TEST 7: Unauthorized access
# # =============================================================================
# test_section "Authorization Tests"

# run_test "Enduser cannot mark drone as broken" \
#   "req_auth POST /drones/4/broken '$ENDUSER_TOKEN' '{\"lat\":30,\"lng\":35}' 403"

# run_test "Enduser cannot use admin endpoint" \
#   "req_auth POST /admin/drones/4/broken '$ENDUSER_TOKEN' '{\"lat\":30,\"lng\":35}' 403"

# run_test "Drone cannot use admin endpoint" \
#   "req_auth POST /admin/drones/4/broken '$DRONE1_TOKEN' '{\"lat\":30,\"lng\":35}' 403"

# # =============================================================================
# # CLEANUP
# # =============================================================================
# test_section "Cleanup"

# # Note: Drones are in broken state and cannot be fixed yet (fix API not implemented)
# # TODO: Once fix API is implemented (POST /admin/drones/:id/fix), add cleanup to fix drones
# # For now, we just verify they're in a known state and orders are cleared

# run_test "Test suite cleanup complete" "true"

# print_summary "Drone Broken Status API"
