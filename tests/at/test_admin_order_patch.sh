#!/usr/bin/env bash
# Test suite for admin order route update (PATCH /admin/orders/{id})
set -euo pipefail

source "$(dirname "$0")/test_common.sh"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Get tokens
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")
DRONE1_TOKEN=$(get_token "drone1" "password")

# Helper function to create an order
create_test_order() {
  local pickup_lat="${1:-30.0}"
  local pickup_lng="${2:-35.0}"
  local dropoff_lat="${3:-31.0}"
  local dropoff_lng="${4:-36.0}"
  
  local order_id=$(req_auth POST /orders "$ENDUSER_TOKEN" \
    "{\"pickup_lat\":${pickup_lat},\"pickup_lng\":${pickup_lng},\"dropoff_lat\":${dropoff_lat},\"dropoff_lng\":${dropoff_lng}}" \
    201 | jq -r '.order_id')
  
  echo "$order_id"
}

# =============================================================================
# TEST 1: Admin can update pickup location for pending order
# =============================================================================
test_section "Update Pickup Location - Pending Order"

ORDER1=$(create_test_order 30.0 35.0 31.0 36.0)

run_test "Admin updates pickup location" \
  "req_auth PATCH /admin/orders/$ORDER1 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 200"

UPDATED_PICKUP_LAT=$(req_auth PATCH /admin/orders/$ORDER1 "$ADMIN_TOKEN" '{"pickup_lat":30.5,"pickup_lng":35.5}' 200 | jq -r '.pickup.lat')
run_test "Pickup lat updated correctly" "[[ '$UPDATED_PICKUP_LAT' == '30.5' ]]"

UPDATED_PICKUP_LNG=$(req_auth PATCH /admin/orders/$ORDER1 "$ADMIN_TOKEN" '{"pickup_lat":30.5,"pickup_lng":35.5}' 200 | jq -r '.pickup.lng')
run_test "Pickup lng updated correctly" "[[ '$UPDATED_PICKUP_LNG' == '35.5' ]]"

# Verify dropoff unchanged
UNCHANGED_DROPOFF_LAT=$(req_auth GET /orders/$ORDER1 "$ENDUSER_TOKEN" '' 200 | jq -r '.dropoff.lat')
run_test "Dropoff lat unchanged" "[[ '$UNCHANGED_DROPOFF_LAT' == '31' ]]"

# Cleanup
req_auth POST /orders/$ORDER1/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 2: Admin can update dropoff location for pending order
# =============================================================================
test_section "Update Dropoff Location - Pending Order"

ORDER2=$(create_test_order 30.0 35.0 31.0 36.0)

run_test "Admin updates dropoff location" \
  "req_auth PATCH /admin/orders/$ORDER2 '$ADMIN_TOKEN' '{\"dropoff_lat\":31.5,\"dropoff_lng\":36.5}' 200"

UPDATED_DROPOFF_LAT=$(req_auth PATCH /admin/orders/$ORDER2 "$ADMIN_TOKEN" '{"dropoff_lat":31.5,"dropoff_lng":36.5}' 200 | jq -r '.dropoff.lat')
run_test "Dropoff lat updated correctly" "[[ '$UPDATED_DROPOFF_LAT' == '31.5' ]]"

UPDATED_DROPOFF_LNG=$(req_auth PATCH /admin/orders/$ORDER2 "$ADMIN_TOKEN" '{"dropoff_lat":31.5,"dropoff_lng":36.5}' 200 | jq -r '.dropoff.lng')
run_test "Dropoff lng updated correctly" "[[ '$UPDATED_DROPOFF_LNG' == '36.5' ]]"

# Verify pickup unchanged
UNCHANGED_PICKUP_LAT=$(req_auth GET /orders/$ORDER2 "$ENDUSER_TOKEN" '' 200 | jq -r '.pickup.lat')
run_test "Pickup lat unchanged" "[[ '$UNCHANGED_PICKUP_LAT' == '30' ]]"

# Cleanup
req_auth POST /orders/$ORDER2/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 3: Admin can update both pickup and dropoff simultaneously
# =============================================================================
test_section "Update Both Pickup and Dropoff"

ORDER3=$(create_test_order 30.0 35.0 31.0 36.0)

run_test "Admin updates both pickup and dropoff" \
  "req_auth PATCH /admin/orders/$ORDER3 '$ADMIN_TOKEN' '{\"pickup_lat\":30.7,\"pickup_lng\":35.7,\"dropoff_lat\":31.7,\"dropoff_lng\":36.7}' 200"

RESPONSE=$(req_auth PATCH /admin/orders/$ORDER3 "$ADMIN_TOKEN" '{"pickup_lat":30.7,"pickup_lng":35.7,"dropoff_lat":31.7,"dropoff_lng":36.7}' 200)
BOTH_PICKUP_LAT=$(echo "$RESPONSE" | jq -r '.pickup.lat')
BOTH_PICKUP_LNG=$(echo "$RESPONSE" | jq -r '.pickup.lng')
BOTH_DROPOFF_LAT=$(echo "$RESPONSE" | jq -r '.dropoff.lat')
BOTH_DROPOFF_LNG=$(echo "$RESPONSE" | jq -r '.dropoff.lng')

run_test "Both pickup lat updated" "[[ '$BOTH_PICKUP_LAT' == '30.7' ]]"
run_test "Both pickup lng updated" "[[ '$BOTH_PICKUP_LNG' == '35.7' ]]"
run_test "Both dropoff lat updated" "[[ '$BOTH_DROPOFF_LAT' == '31.7' ]]"
run_test "Both dropoff lng updated" "[[ '$BOTH_DROPOFF_LNG' == '36.7' ]]"

# Cleanup
req_auth POST /orders/$ORDER3/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 4: Cannot update reserved order (409 Conflict)
# =============================================================================
test_section "Update Reserved Order - Conflict"

ORDER4=$(create_test_order 30.0 35.0 31.0 36.0)
req_auth POST /orders/$ORDER4/reserve "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "Admin cannot update reserved order pickup" \
  "req_auth PATCH /admin/orders/$ORDER4 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 409"

run_test "Admin cannot update reserved order dropoff" \
  "req_auth PATCH /admin/orders/$ORDER4 '$ADMIN_TOKEN' '{\"dropoff_lat\":31.5,\"dropoff_lng\":36.5}' 409"

# Cleanup - fail order to free drone
req_auth POST /orders/$ORDER4/fail "$DRONE1_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 5: Cannot update picked up order (409 Conflict)
# =============================================================================
test_section "Update Picked Up Order - Conflict"

ORDER5=$(create_test_order 30.0 35.0 31.0 36.0)
req_auth POST /orders/$ORDER5/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER5/pickup "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "Admin cannot update picked up order" \
  "req_auth PATCH /admin/orders/$ORDER5 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 409"

# Cleanup - deliver order to free drone
req_auth POST /orders/$ORDER5/deliver "$DRONE1_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 6: Cannot update delivered order (409 Conflict)
# =============================================================================
test_section "Update Delivered Order - Conflict"

ORDER6=$(create_test_order 30.0 35.0 31.0 36.0)
req_auth POST /orders/$ORDER6/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER6/pickup "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER6/deliver "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "Admin cannot update delivered order" \
  "req_auth PATCH /admin/orders/$ORDER6 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 409"

# =============================================================================
# TEST 7: Cannot update canceled order (409 Conflict)
# =============================================================================
test_section "Update Canceled Order - Conflict"

ORDER7=$(create_test_order 30.0 35.0 31.0 36.0)
req_auth POST /orders/$ORDER7/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null

run_test "Admin cannot update canceled order" \
  "req_auth PATCH /admin/orders/$ORDER7 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 409"

# =============================================================================
# TEST 8: Cannot update failed order (409 Conflict)
# =============================================================================
test_section "Update Failed Order - Conflict"

ORDER8=$(create_test_order 30.0 35.0 31.0 36.0)
req_auth POST /orders/$ORDER8/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$ORDER8/fail "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "Admin cannot update failed order" \
  "req_auth PATCH /admin/orders/$ORDER8 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 409"

# =============================================================================
# TEST 9: Validation - Missing coordinates
# =============================================================================
test_section "Validation - Missing Coordinates"

ORDER9=$(create_test_order 30.0 35.0 31.0 36.0)

run_test "Update with empty body rejected" \
  "req_auth PATCH /admin/orders/$ORDER9 '$ADMIN_TOKEN' '{}' 400"

run_test "Update with only pickup lat rejected" \
  "req_auth PATCH /admin/orders/$ORDER9 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5}' 400"

run_test "Update with only pickup lng rejected" \
  "req_auth PATCH /admin/orders/$ORDER9 '$ADMIN_TOKEN' '{\"pickup_lng\":35.5}' 400"

run_test "Update with only dropoff lat rejected" \
  "req_auth PATCH /admin/orders/$ORDER9 '$ADMIN_TOKEN' '{\"dropoff_lat\":31.5}' 400"

run_test "Update with only dropoff lng rejected" \
  "req_auth PATCH /admin/orders/$ORDER9 '$ADMIN_TOKEN' '{\"dropoff_lng\":36.5}' 400"

# Cleanup
req_auth POST /orders/$ORDER9/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 10: Validation - Invalid coordinates
# =============================================================================
test_section "Validation - Invalid Coordinates"

ORDER10=$(create_test_order 30.0 35.0 31.0 36.0)

run_test "Update with invalid pickup lat (>90) rejected" \
  "req_auth PATCH /admin/orders/$ORDER10 '$ADMIN_TOKEN' '{\"pickup_lat\":91,\"pickup_lng\":35.5}' 400"

run_test "Update with invalid pickup lat (<-90) rejected" \
  "req_auth PATCH /admin/orders/$ORDER10 '$ADMIN_TOKEN' '{\"pickup_lat\":-91,\"pickup_lng\":35.5}' 400"

run_test "Update with invalid pickup lng (>180) rejected" \
  "req_auth PATCH /admin/orders/$ORDER10 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":181}' 400"

run_test "Update with invalid pickup lng (<-180) rejected" \
  "req_auth PATCH /admin/orders/$ORDER10 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":-181}' 400"

run_test "Update with invalid dropoff lat rejected" \
  "req_auth PATCH /admin/orders/$ORDER10 '$ADMIN_TOKEN' '{\"dropoff_lat\":95,\"dropoff_lng\":36.5}' 400"

run_test "Update with invalid dropoff lng rejected" \
  "req_auth PATCH /admin/orders/$ORDER10 '$ADMIN_TOKEN' '{\"dropoff_lat\":31.5,\"dropoff_lng\":200}' 400"

# Cleanup
req_auth POST /orders/$ORDER10/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 11: Validation - Boundary coordinates
# =============================================================================
test_section "Validation - Boundary Coordinates"

ORDER11=$(create_test_order 30.0 35.0 31.0 36.0)

run_test "Update with max valid lat (90) accepted" \
  "req_auth PATCH /admin/orders/$ORDER11 '$ADMIN_TOKEN' '{\"pickup_lat\":90,\"pickup_lng\":35.5}' 200"

run_test "Update with min valid lat (-90) accepted" \
  "req_auth PATCH /admin/orders/$ORDER11 '$ADMIN_TOKEN' '{\"pickup_lat\":-90,\"pickup_lng\":35.5}' 200"

run_test "Update with max valid lng (180) accepted" \
  "req_auth PATCH /admin/orders/$ORDER11 '$ADMIN_TOKEN' '{\"dropoff_lat\":31.5,\"dropoff_lng\":180}' 200"

run_test "Update with min valid lng (-180) accepted" \
  "req_auth PATCH /admin/orders/$ORDER11 '$ADMIN_TOKEN' '{\"dropoff_lat\":31.5,\"dropoff_lng\":-180}' 200"

# Cleanup
req_auth POST /orders/$ORDER11/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 12: Authorization - Only admins can update routes
# =============================================================================
test_section "Authorization - Admin Only"

ORDER12=$(create_test_order 30.0 35.0 31.0 36.0)

run_test "Enduser cannot update order route" \
  "req_auth PATCH /admin/orders/$ORDER12 '$ENDUSER_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 403"

run_test "Drone cannot update order route" \
  "req_auth PATCH /admin/orders/$ORDER12 '$DRONE1_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 403"

run_test "Unauthenticated request rejected" \
  "req PATCH /admin/orders/$ORDER12 '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 401"

# Cleanup
req_auth POST /orders/$ORDER12/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 13: Invalid order ID
# =============================================================================
test_section "Invalid Order ID"

run_test "Update with non-existent order ID rejected" \
  "req_auth PATCH /admin/orders/999999 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 404"

run_test "Update with invalid order ID format rejected" \
  "req_auth PATCH /admin/orders/abc '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 400"

run_test "Update with zero order ID rejected" \
  "req_auth PATCH /admin/orders/0 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 400"

run_test "Update with negative order ID rejected" \
  "req_auth PATCH /admin/orders/-1 '$ADMIN_TOKEN' '{\"pickup_lat\":30.5,\"pickup_lng\":35.5}' 400"

# =============================================================================
# TEST 14: Response validation
# =============================================================================
test_section "Response Validation"

ORDER14=$(create_test_order 30.0 35.0 31.0 36.0)

PATCH_RESPONSE=$(req_auth PATCH /admin/orders/$ORDER14 "$ADMIN_TOKEN" '{"pickup_lat":30.8,"pickup_lng":35.8}' 200)

RESP_ORDER_ID=$(echo "$PATCH_RESPONSE" | jq -r '.order_id')
run_test "Response contains order_id" "[[ '$RESP_ORDER_ID' == '$ORDER14' ]]"

RESP_STATUS=$(echo "$PATCH_RESPONSE" | jq -r '.status')
run_test "Response status is pending" "[[ '$RESP_STATUS' == 'pending' ]]"

RESP_PICKUP_LAT=$(echo "$PATCH_RESPONSE" | jq -r '.pickup.lat')
run_test "Response pickup.lat is updated" "[[ '$RESP_PICKUP_LAT' == '30.8' ]]"

RESP_PICKUP_LNG=$(echo "$PATCH_RESPONSE" | jq -r '.pickup.lng')
run_test "Response pickup.lng is updated" "[[ '$RESP_PICKUP_LNG' == '35.8' ]]"

RESP_DROPOFF_LAT=$(echo "$PATCH_RESPONSE" | jq -r '.dropoff.lat')
run_test "Response dropoff.lat is unchanged" "[[ '$RESP_DROPOFF_LAT' == '31' ]]"

RESP_DROPOFF_LNG=$(echo "$PATCH_RESPONSE" | jq -r '.dropoff.lng')
run_test "Response dropoff.lng is unchanged" "[[ '$RESP_DROPOFF_LNG' == '36' ]]"

HAS_CREATED_AT=$(echo "$PATCH_RESPONSE" | jq 'has("created_at")')
run_test "Response contains created_at" "[[ '$HAS_CREATED_AT' == 'true' ]]"

HAS_UPDATED_AT=$(echo "$PATCH_RESPONSE" | jq 'has("updated_at")')
run_test "Response contains updated_at" "[[ '$HAS_UPDATED_AT' == 'true' ]]"

# Cleanup
req_auth POST /orders/$ORDER14/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 15: Multiple updates to same order
# =============================================================================
test_section "Multiple Updates to Same Order"

ORDER15=$(create_test_order 30.0 35.0 31.0 36.0)

run_test "First update succeeds" \
  "req_auth PATCH /admin/orders/$ORDER15 '$ADMIN_TOKEN' '{\"pickup_lat\":30.1,\"pickup_lng\":35.1}' 200"

run_test "Second update succeeds" \
  "req_auth PATCH /admin/orders/$ORDER15 '$ADMIN_TOKEN' '{\"pickup_lat\":30.2,\"pickup_lng\":35.2}' 200"

run_test "Third update succeeds" \
  "req_auth PATCH /admin/orders/$ORDER15 '$ADMIN_TOKEN' '{\"dropoff_lat\":31.3,\"dropoff_lng\":36.3}' 200"

# Verify final state
FINAL_STATE=$(req_auth GET /orders/$ORDER15 "$ENDUSER_TOKEN" '' 200)
FINAL_PICKUP_LAT=$(echo "$FINAL_STATE" | jq -r '.pickup.lat')
FINAL_PICKUP_LNG=$(echo "$FINAL_STATE" | jq -r '.pickup.lng')
FINAL_DROPOFF_LAT=$(echo "$FINAL_STATE" | jq -r '.dropoff.lat')
FINAL_DROPOFF_LNG=$(echo "$FINAL_STATE" | jq -r '.dropoff.lng')

run_test "Final pickup lat is from last update" "[[ '$FINAL_PICKUP_LAT' == '30.2' ]]"
run_test "Final pickup lng is from last update" "[[ '$FINAL_PICKUP_LNG' == '35.2' ]]"
run_test "Final dropoff lat is from last update" "[[ '$FINAL_DROPOFF_LAT' == '31.3' ]]"
run_test "Final dropoff lng is from last update" "[[ '$FINAL_DROPOFF_LNG' == '36.3' ]]"

# Cleanup
req_auth POST /orders/$ORDER15/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 16: Update clears handoff location
# =============================================================================
test_section "Update Clears Handoff Location"

ORDER16=$(create_test_order 30.0 35.0 31.0 36.0)

# Update the route
run_test "Admin updates route" \
  "req_auth PATCH /admin/orders/$ORDER16 '$ADMIN_TOKEN' '{\"pickup_lat\":30.9,\"pickup_lng\":35.9}' 200"

# Verify handoff fields are null
UPDATED_ORDER=$(req_auth GET /orders/$ORDER16 "$ENDUSER_TOKEN" '' 200)
HANDOFF_LAT=$(echo "$UPDATED_ORDER" | jq -r '.handoff_lat')
HANDOFF_LNG=$(echo "$UPDATED_ORDER" | jq -r '.handoff_lng')

run_test "Handoff lat is null after update" "[[ '$HANDOFF_LAT' == 'null' ]]"
run_test "Handoff lng is null after update" "[[ '$HANDOFF_LNG' == 'null' ]]"

# Cleanup
req_auth POST /orders/$ORDER16/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null 2>&1 || true

print_summary "Admin Order Route Update (PATCH)"
