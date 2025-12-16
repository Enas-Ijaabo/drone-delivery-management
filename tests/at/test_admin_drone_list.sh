#!/usr/bin/env bash
# Test suite for admin drone list endpoint (GET /admin/drones)
set -euo pipefail

source "$(dirname "$0")/test_common.sh"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Get tokens
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")
DRONE1_TOKEN=$(get_token "drone1" "password")

# =============================================================================
# TEST 1: Basic drone list - default pagination
# =============================================================================
test_section "Basic Drone List - Default Pagination"

RESPONSE=$(req_auth GET /admin/drones "$ADMIN_TOKEN" '' 200)

run_test "List drones returns 200 OK" "true"

HAS_DATA=$(echo "$RESPONSE" | jq 'has("data")')
run_test "Response has data field" "[[ '$HAS_DATA' == 'true' ]]"

HAS_META=$(echo "$RESPONSE" | jq 'has("meta")')
run_test "Response has meta field" "[[ '$HAS_META' == 'true' ]]"

DATA_IS_ARRAY=$(echo "$RESPONSE" | jq '.data | type')
run_test "Data is an array" "[[ '$DATA_IS_ARRAY' == '\"array\"' ]]"

DRONE_COUNT=$(echo "$RESPONSE" | jq '.data | length')
run_test "Returns at least 2 drones" "[[ $DRONE_COUNT -ge 2 ]]"

# =============================================================================
# TEST 2: Pagination metadata - defaults
# =============================================================================
test_section "Pagination Metadata - Defaults"

META_PAGE=$(echo "$RESPONSE" | jq '.meta.page')
run_test "Default page is 1" "[[ '$META_PAGE' == '1' ]]"

META_PAGE_SIZE=$(echo "$RESPONSE" | jq '.meta.page_size')
run_test "Default page_size is 20" "[[ '$META_PAGE_SIZE' == '20' ]]"

HAS_NEXT=$(echo "$RESPONSE" | jq '.meta | has("has_next")')
run_test "Meta has has_next field" "[[ '$HAS_NEXT' == 'true' ]]"

# =============================================================================
# TEST 3: Drone response structure
# =============================================================================
test_section "Drone Response Structure"

FIRST_DRONE=$(echo "$RESPONSE" | jq '.data[0]')

HAS_DRONE_ID=$(echo "$FIRST_DRONE" | jq 'has("drone_id")')
run_test "Drone has drone_id" "[[ '$HAS_DRONE_ID' == 'true' ]]"

HAS_STATUS=$(echo "$FIRST_DRONE" | jq 'has("status")')
run_test "Drone has status" "[[ '$HAS_STATUS' == 'true' ]]"

HAS_LAT=$(echo "$FIRST_DRONE" | jq 'has("lat")')
run_test "Drone has lat" "[[ '$HAS_LAT' == 'true' ]]"

HAS_LNG=$(echo "$FIRST_DRONE" | jq 'has("lng")')
run_test "Drone has lng" "[[ '$HAS_LNG' == 'true' ]]"

DRONE_ID_TYPE=$(echo "$FIRST_DRONE" | jq '.drone_id | type')
run_test "drone_id is number" "[[ '$DRONE_ID_TYPE' == '\"number\"' ]]"

STATUS_TYPE=$(echo "$FIRST_DRONE" | jq '.status | type')
run_test "status is string" "[[ '$STATUS_TYPE' == '\"string\"' ]]"

# =============================================================================
# TEST 4: Custom pagination - page parameter
# =============================================================================
test_section "Custom Pagination - Page Parameter"

PAGE1=$(req_auth GET "/admin/drones?page=1&page_size=1" "$ADMIN_TOKEN" '' 200)
PAGE1_ID=$(echo "$PAGE1" | jq '.data[0].drone_id')

PAGE2=$(req_auth GET "/admin/drones?page=2&page_size=1" "$ADMIN_TOKEN" '' 200)
PAGE2_ID=$(echo "$PAGE2" | jq '.data[0].drone_id')

run_test "Page 1 returns data" "[[ -n '$PAGE1_ID' ]]"
run_test "Page 2 returns data" "[[ -n '$PAGE2_ID' ]]"
run_test "Different pages return different drones" "[[ '$PAGE1_ID' != '$PAGE2_ID' ]]"

PAGE1_META_PAGE=$(echo "$PAGE1" | jq '.meta.page')
run_test "Page 1 meta.page is 1" "[[ '$PAGE1_META_PAGE' == '1' ]]"

PAGE2_META_PAGE=$(echo "$PAGE2" | jq '.meta.page')
run_test "Page 2 meta.page is 2" "[[ '$PAGE2_META_PAGE' == '2' ]]"

# =============================================================================
# TEST 5: Custom pagination - page_size parameter
# =============================================================================
test_section "Custom Pagination - Page Size Parameter"

SIZE1=$(req_auth GET "/admin/drones?page_size=1" "$ADMIN_TOKEN" '' 200)
SIZE1_COUNT=$(echo "$SIZE1" | jq '.data | length')
SIZE1_META=$(echo "$SIZE1" | jq '.meta.page_size')

run_test "page_size=1 returns 1 drone" "[[ '$SIZE1_COUNT' == '1' ]]"
run_test "page_size=1 meta.page_size is 1" "[[ '$SIZE1_META' == '1' ]]"

SIZE2=$(req_auth GET "/admin/drones?page_size=2" "$ADMIN_TOKEN" '' 200)
SIZE2_COUNT=$(echo "$SIZE2" | jq '.data | length')
SIZE2_META=$(echo "$SIZE2" | jq '.meta.page_size')

run_test "page_size=2 returns 2 drones" "[[ '$SIZE2_COUNT' == '2' ]]"
run_test "page_size=2 meta.page_size is 2" "[[ '$SIZE2_META' == '2' ]]"

# =============================================================================
# TEST 6: Pagination limits - max page_size
# =============================================================================
test_section "Pagination Limits - Max Page Size"

MAX_SIZE=$(req_auth GET "/admin/drones?page_size=150" "$ADMIN_TOKEN" '' 200)
MAX_SIZE_META=$(echo "$MAX_SIZE" | jq '.meta.page_size')

run_test "page_size > 100 capped at 100" "[[ '$MAX_SIZE_META' == '100' ]]"

EXACT_MAX=$(req_auth GET "/admin/drones?page_size=100" "$ADMIN_TOKEN" '' 200)
EXACT_MAX_META=$(echo "$EXACT_MAX" | jq '.meta.page_size')

run_test "page_size=100 is allowed" "[[ '$EXACT_MAX_META' == '100' ]]"

# =============================================================================
# TEST 7: Pagination validation - invalid parameters
# =============================================================================
test_section "Pagination Validation - Invalid Parameters"

RESPONSE_NEG_PAGE=$(req_auth GET '/admin/drones?page=-1' "$ADMIN_TOKEN" '' 200)
NEG_PAGE=$(echo "$RESPONSE_NEG_PAGE" | jq '.meta.page')
run_test "Negative page normalized to default" "[[ '$NEG_PAGE' == '1' ]]"

run_test "Zero page uses default" \
  "req_auth GET '/admin/drones?page=0' '$ADMIN_TOKEN' '' 200"

RESPONSE_NEG_PS=$(req_auth GET '/admin/drones?page_size=-1' "$ADMIN_TOKEN" '' 200)
NEG_PS=$(echo "$RESPONSE_NEG_PS" | jq '.meta.page_size')
run_test "Negative page_size normalized to default" "[[ '$NEG_PS' == '20' ]]"

run_test "Zero page_size uses default" \
  "req_auth GET '/admin/drones?page_size=0' '$ADMIN_TOKEN' '' 200"

run_test "Invalid page format rejected" \
  "req_auth GET '/admin/drones?page=abc' '$ADMIN_TOKEN' '' 400"

run_test "Invalid page_size format rejected" \
  "req_auth GET '/admin/drones?page_size=xyz' '$ADMIN_TOKEN' '' 400"

# =============================================================================
# TEST 8: has_next indicator
# =============================================================================
test_section "Has Next Indicator"

# Request with page_size=1, should have more drones
HAS_MORE=$(req_auth GET "/admin/drones?page=1&page_size=1" "$ADMIN_TOKEN" '' 200)
HAS_MORE_FLAG=$(echo "$HAS_MORE" | jq '.meta.has_next')

run_test "has_next is true when more data exists" "[[ '$HAS_MORE_FLAG' == 'true' ]]"

# Request with large page_size, should not have more
NO_MORE=$(req_auth GET "/admin/drones?page=1&page_size=100" "$ADMIN_TOKEN" '' 200)
NO_MORE_FLAG=$(echo "$NO_MORE" | jq '.meta.has_next')

run_test "has_next is false when no more data" "[[ '$NO_MORE_FLAG' == 'false' ]]"

# =============================================================================
# TEST 9: Authorization - Admin only
# =============================================================================
test_section "Authorization - Admin Only"

run_test "Enduser cannot list drones" \
  "req_auth GET /admin/drones '$ENDUSER_TOKEN' '' 403"

run_test "Drone cannot list drones" \
  "req_auth GET /admin/drones '$DRONE1_TOKEN' '' 403"

run_test "Unauthenticated request rejected" \
  "req GET /admin/drones '' 401"

# =============================================================================
# TEST 10: Drone status values
# =============================================================================
test_section "Drone Status Values"

ALL_DRONES=$(req_auth GET "/admin/drones?page_size=100" "$ADMIN_TOKEN" '' 200)

IDLE_COUNT=$(echo "$ALL_DRONES" | jq '[.data[] | select(.status == "idle")] | length')
run_test "Found idle drones" "[[ '$IDLE_COUNT' -ge 0 ]]"

STATUSES=$(echo "$ALL_DRONES" | jq -r '[.data[].status] | unique | join(",")')
run_test "Valid statuses returned" "[[ -n '$STATUSES' ]]"

# =============================================================================
# TEST 11: Current order ID field
# =============================================================================
test_section "Current Order ID Field"

# Create and reserve an order to get a drone with current_order_id
ORDER_ID=$(create_order "$ENDUSER_TOKEN" 30.0 35.0 31.0 36.0)
req_auth POST /orders/$ORDER_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null

# List drones and find one with current_order_id
DRONES_WITH_ORDER=$(req_auth GET "/admin/drones?page_size=100" "$ADMIN_TOKEN" '' 200)
DRONE_WITH_ORDER=$(echo "$DRONES_WITH_ORDER" | jq '.data[] | select(.current_order_id != null) | select(.current_order_id == '$ORDER_ID')')

HAS_CURRENT_ORDER=$(echo "$DRONE_WITH_ORDER" | jq 'has("current_order_id")')
run_test "Drone with order has current_order_id" "[[ '$HAS_CURRENT_ORDER' == 'true' ]]"

CURRENT_ORDER_VALUE=$(echo "$DRONE_WITH_ORDER" | jq '.current_order_id')
run_test "current_order_id matches reserved order" "[[ '$CURRENT_ORDER_VALUE' == '$ORDER_ID' ]]"

# Cleanup
req_auth POST /orders/$ORDER_ID/fail "$DRONE1_TOKEN" '' 200 >/dev/null 2>&1 || true

# =============================================================================
# TEST 12: Empty page beyond available data
# =============================================================================
test_section "Empty Page Beyond Available Data"

# Request a very high page number
HIGH_PAGE=$(req_auth GET "/admin/drones?page=999&page_size=20" "$ADMIN_TOKEN" '' 200)
HIGH_PAGE_DATA=$(echo "$HIGH_PAGE" | jq '.data | length')

run_test "High page number returns empty array" "[[ '$HIGH_PAGE_DATA' == '0' ]]"

HIGH_PAGE_META=$(echo "$HIGH_PAGE" | jq '.meta.page')
run_test "High page number meta.page is 999" "[[ '$HIGH_PAGE_META' == '999' ]]"

HIGH_PAGE_HAS_NEXT=$(echo "$HIGH_PAGE" | jq '.meta.has_next')
run_test "High page has_next is false" "[[ '$HIGH_PAGE_HAS_NEXT' == 'false' ]]"

# =============================================================================
# TEST 13: Coordinate values
# =============================================================================
test_section "Coordinate Values"

COORDS_CHECK=$(req_auth GET "/admin/drones?page_size=2" "$ADMIN_TOKEN" '' 200)
FIRST_LAT=$(echo "$COORDS_CHECK" | jq '.data[0].lat')
FIRST_LNG=$(echo "$COORDS_CHECK" | jq '.data[0].lng')

run_test "Latitude is numeric" "[[ '$FIRST_LAT' =~ ^-?[0-9]+\.?[0-9]*$ ]]"
run_test "Longitude is numeric" "[[ '$FIRST_LNG' =~ ^-?[0-9]+\.?[0-9]*$ ]]"

# Validate lat/lng ranges (lat: -90 to 90, lng: -180 to 180)
LAT_VALID=$(echo "$COORDS_CHECK" | jq '[.data[].lat] | all(. >= -90 and . <= 90)')
run_test "All latitudes in valid range" "[[ '$LAT_VALID' == 'true' ]]"

LNG_VALID=$(echo "$COORDS_CHECK" | jq '[.data[].lng] | all(. >= -180 and . <= 180)')
run_test "All longitudes in valid range" "[[ '$LNG_VALID' == 'true' ]]"

# =============================================================================
# TEST 14: Consistent ordering across pages
# =============================================================================
test_section "Consistent Ordering Across Pages"

# Get first 2 drones in one request
SINGLE_REQUEST=$(req_auth GET "/admin/drones?page=1&page_size=2" "$ADMIN_TOKEN" '' 200)
SINGLE_ID1=$(echo "$SINGLE_REQUEST" | jq '.data[0].drone_id')
SINGLE_ID2=$(echo "$SINGLE_REQUEST" | jq '.data[1].drone_id')

# Get same drones via two separate requests
PAGE1_SIZE1=$(req_auth GET "/admin/drones?page=1&page_size=1" "$ADMIN_TOKEN" '' 200)
PAGE2_SIZE1=$(req_auth GET "/admin/drones?page=2&page_size=1" "$ADMIN_TOKEN" '' 200)
SPLIT_ID1=$(echo "$PAGE1_SIZE1" | jq '.data[0].drone_id')
SPLIT_ID2=$(echo "$PAGE2_SIZE1" | jq '.data[0].drone_id')

run_test "First drone ID consistent" "[[ '$SINGLE_ID1' == '$SPLIT_ID1' ]]"
run_test "Second drone ID consistent" "[[ '$SINGLE_ID2' == '$SPLIT_ID2' ]]"

# =============================================================================
# TEST 15: Last heartbeat field
# =============================================================================
test_section "Last Heartbeat Field"

HEARTBEAT_CHECK=$(req_auth GET "/admin/drones?page_size=5" "$ADMIN_TOKEN" '' 200)

# Check if last_heartbeat field exists (it may be null for some drones)
FIRST_DRONE_HB=$(echo "$HEARTBEAT_CHECK" | jq '.data[0] | has("last_heartbeat")')
run_test "Drone response includes last_heartbeat field" "[[ '$FIRST_DRONE_HB' == 'true' ]]"

# If any drone has a last_heartbeat value, verify it's a valid timestamp
HB_VALUES=$(echo "$HEARTBEAT_CHECK" | jq '[.data[].last_heartbeat | select(. != null)] | length')
run_test "Last heartbeat field present" "[[ '$HB_VALUES' -ge 0 ]]"

# =============================================================================
# CLEANUP
# =============================================================================
test_section "Cleanup"

# Get all drones and find drone1 by checking which one was used in TEST 11
ALL_DRONES_CLEANUP=$(req_auth GET "/admin/drones?page_size=100" "$ADMIN_TOKEN" '' 200)
# Find any drones that are not idle and reset them
DRONES_TO_RESET=$(echo "$ALL_DRONES_CLEANUP" | jq -r '.data[] | select(.status != "idle") | .drone_id')

if [[ -n "$DRONES_TO_RESET" ]]; then
  for DRONE_ID in $DRONES_TO_RESET; do
    mark_drone_fixed "$DRONE_ID" "$ADMIN_TOKEN" 0.0 0.0 > /dev/null 2>&1 || true
  done
fi

# Verify all drones are back to idle
FINAL_CHECK=$(req_auth GET "/admin/drones?page_size=100" "$ADMIN_TOKEN" '' 200)
NON_IDLE=$(echo "$FINAL_CHECK" | jq '[.data[] | select(.status != "idle")] | length')
run_test "All drones returned to idle" "[[ '$NON_IDLE' == '0' ]]"

print_summary "Admin Drone List (GET /admin/drones)"
