#!/usr/bin/env bash
# Test suite for admin order list endpoint (GET /admin/orders)
set -euo pipefail

source "$(dirname "$0")/test_common.sh"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Get tokens and user IDs
ADMIN_RESP=$(req POST /auth/token '{"name":"admin","password":"password"}' 200)
ADMIN_TOKEN=$(echo "$ADMIN_RESP" | jq -r '.access_token')

ENDUSER1_RESP=$(req POST /auth/token '{"name":"enduser1","password":"password"}' 200)
ENDUSER1_TOKEN=$(echo "$ENDUSER1_RESP" | jq -r '.access_token')
ENDUSER1_ID=$(echo "$ENDUSER1_RESP" | jq -r '.user.id')

ENDUSER2_RESP=$(req POST /auth/token '{"name":"enduser2","password":"password"}' 200)
ENDUSER2_TOKEN=$(echo "$ENDUSER2_RESP" | jq -r '.access_token')
ENDUSER2_ID=$(echo "$ENDUSER2_RESP" | jq -r '.user.id')

DRONE1_RESP=$(req POST /auth/token '{"name":"drone1","password":"password"}' 200)
DRONE1_TOKEN=$(echo "$DRONE1_RESP" | jq -r '.access_token')
DRONE1_ID=$(echo "$DRONE1_RESP" | jq -r '.user.id')

DRONE2_RESP=$(req POST /auth/token '{"name":"drone2","password":"password"}' 200)
DRONE2_TOKEN=$(echo "$DRONE2_RESP" | jq -r '.access_token')
DRONE2_ID=$(echo "$DRONE2_RESP" | jq -r '.user.id')

# Ensure drones are idle
mark_drone_fixed "$DRONE1_ID" "$DRONE1_TOKEN" 0.0 0.0 > /dev/null 2>&1 || true
mark_drone_fixed "$DRONE2_ID" "$DRONE2_TOKEN" 10.0 10.0 > /dev/null 2>&1 || true

# =============================================================================
# TEST 1: Authorization - Admin Only
# =============================================================================
test_section "Authorization - Admin Only"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}/admin/orders")
run_test "Unauthenticated request rejected" "[[ '$STATUS' == '401' ]]"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ENDUSER1_TOKEN" "${BASE}/admin/orders")
run_test "Enduser cannot list orders" "[[ '$STATUS' == '403' ]]"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $DRONE1_TOKEN" "${BASE}/admin/orders")
run_test "Drone cannot list orders" "[[ '$STATUS' == '403' ]]"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders")
run_test "Admin can list orders" "[[ '$STATUS' == '200' ]]"

# =============================================================================
# TEST 2: Basic List - Default Pagination
# =============================================================================
test_section "Basic List - Default Pagination"

# Create some test orders
ORDER1_ID=$(create_order "$ENDUSER1_TOKEN" 1.0 1.0 2.0 2.0)
ORDER2_ID=$(create_order "$ENDUSER1_TOKEN" 3.0 3.0 4.0 4.0)
ORDER3_ID=$(create_order "$ENDUSER2_TOKEN" 5.0 5.0 6.0 6.0)

RESPONSE=$(req_auth GET /admin/orders "$ADMIN_TOKEN" '' 200)
run_test "List orders returns 200 OK" "true"

HAS_DATA=$(echo "$RESPONSE" | jq 'has("data")')
run_test "Response has data field" "[[ '$HAS_DATA' == 'true' ]]"

HAS_META=$(echo "$RESPONSE" | jq 'has("meta")')
run_test "Response has meta field" "[[ '$HAS_META' == 'true' ]]"

IS_ARRAY=$(echo "$RESPONSE" | jq '.data | type')
run_test "Data is an array" "[[ '$IS_ARRAY' == '\"array\"' ]]"

COUNT=$(echo "$RESPONSE" | jq '.data | length')
run_test "Returns at least 3 orders" "[[ $COUNT -ge 3 ]]"

# =============================================================================
# TEST 3: Pagination Metadata - Defaults
# =============================================================================
test_section "Pagination Metadata - Defaults"

PAGE=$(echo "$RESPONSE" | jq '.meta.page')
run_test "Default page is 1" "[[ '$PAGE' == '1' ]]"

PAGE_SIZE=$(echo "$RESPONSE" | jq '.meta.page_size')
run_test "Default page_size is 20" "[[ '$PAGE_SIZE' == '20' ]]"

HAS_NEXT=$(echo "$RESPONSE" | jq '.meta | has("has_next")')
run_test "Meta has has_next field" "[[ '$HAS_NEXT' == 'true' ]]"

# =============================================================================
# TEST 4: Order Response Structure
# =============================================================================
test_section "Order Response Structure"

FIRST_ORDER=$(echo "$RESPONSE" | jq '.data[0]')

HAS_ID=$(echo "$FIRST_ORDER" | jq 'has("order_id")')
run_test "Order has order_id" "[[ '$HAS_ID' == 'true' ]]"

HAS_STATUS=$(echo "$FIRST_ORDER" | jq 'has("status")')
run_test "Order has status" "[[ '$HAS_STATUS' == 'true' ]]"

HAS_PICKUP=$(echo "$FIRST_ORDER" | jq 'has("pickup")')
run_test "Order has pickup" "[[ '$HAS_PICKUP' == 'true' ]]"

HAS_DROPOFF=$(echo "$FIRST_ORDER" | jq 'has("dropoff")')
run_test "Order has dropoff" "[[ '$HAS_DROPOFF' == 'true' ]]"

HAS_CREATED=$(echo "$FIRST_ORDER" | jq 'has("created_at")')
run_test "Order has created_at" "[[ '$HAS_CREATED' == 'true' ]]"

PICKUP_LAT=$(echo "$FIRST_ORDER" | jq '.pickup.lat')
PICKUP_LNG=$(echo "$FIRST_ORDER" | jq '.pickup.lng')
run_test "Pickup has lat and lng" "[[ ! -z '$PICKUP_LAT' && ! -z '$PICKUP_LNG' ]]"

DROPOFF_LAT=$(echo "$FIRST_ORDER" | jq '.dropoff.lat')
DROPOFF_LNG=$(echo "$FIRST_ORDER" | jq '.dropoff.lng')
run_test "Dropoff has lat and lng" "[[ ! -z '$DROPOFF_LAT' && ! -z '$DROPOFF_LNG' ]]"

# =============================================================================
# TEST 5: Custom Pagination
# =============================================================================
test_section "Custom Pagination - Page Parameter"

RESPONSE_P1=$(req_auth GET '/admin/orders?page=1' "$ADMIN_TOKEN" '' 200)
COUNT_P1=$(echo "$RESPONSE_P1" | jq '.data | length')
run_test "Page 1 returns data" "[[ $COUNT_P1 -ge 1 ]]"

PAGE_P1=$(echo "$RESPONSE_P1" | jq '.meta.page')
run_test "Page 1 meta.page is 1" "[[ '$PAGE_P1' == '1' ]]"

RESPONSE_PS1=$(req_auth GET '/admin/orders?page_size=1' "$ADMIN_TOKEN" '' 200)
COUNT_PS1=$(echo "$RESPONSE_PS1" | jq '.data | length')
run_test "page_size=1 returns 1 order" "[[ '$COUNT_PS1' == '1' ]]"

PS1=$(echo "$RESPONSE_PS1" | jq '.meta.page_size')
run_test "page_size=1 meta.page_size is 1" "[[ '$PS1' == '1' ]]"

RESPONSE_PS2=$(req_auth GET '/admin/orders?page_size=2' "$ADMIN_TOKEN" '' 200)
COUNT_PS2=$(echo "$RESPONSE_PS2" | jq '.data | length')
run_test "page_size=2 returns 2 orders" "[[ '$COUNT_PS2' == '2' ]]"

# =============================================================================
# TEST 6: Pagination Limits
# =============================================================================
test_section "Pagination Limits - Max Page Size"

RESPONSE_LARGE=$(req_auth GET '/admin/orders?page_size=200' "$ADMIN_TOKEN" '' 200)
PS_LARGE=$(echo "$RESPONSE_LARGE" | jq '.meta.page_size')
run_test "page_size > 100 capped at 100" "[[ '$PS_LARGE' == '100' ]]"

RESPONSE_100=$(req_auth GET '/admin/orders?page_size=100' "$ADMIN_TOKEN" '' 200)
PS_100=$(echo "$RESPONSE_100" | jq '.meta.page_size')
run_test "page_size=100 is allowed" "[[ '$PS_100' == '100' ]]"

# =============================================================================
# TEST 7: Pagination Validation
# =============================================================================
test_section "Pagination Validation - Invalid Parameters"

set +e
RESPONSE_NEG_PAGE=$(req_auth GET '/admin/orders?page=-1' "$ADMIN_TOKEN" '' 200)
set -e
PAGE_NEG=$(echo "$RESPONSE_NEG_PAGE" | jq '.meta.page')
run_test "Negative page normalized to default" "[[ '$PAGE_NEG' == '1' ]]"

RESPONSE_ZERO=$(req_auth GET '/admin/orders?page=0' "$ADMIN_TOKEN" '' 200)
PAGE_ZERO=$(echo "$RESPONSE_ZERO" | jq '.meta.page')
run_test "Zero page uses default" "[[ '$PAGE_ZERO' == '1' ]]"

set +e
RESPONSE_NEG_PS=$(req_auth GET '/admin/orders?page_size=-1' "$ADMIN_TOKEN" '' 200)
set -e
PS_NEG=$(echo "$RESPONSE_NEG_PS" | jq '.meta.page_size')
run_test "Negative page_size normalized to default" "[[ '$PS_NEG' == '20' ]]"

RESPONSE_ZERO_PS=$(req_auth GET '/admin/orders?page_size=0' "$ADMIN_TOKEN" '' 200)
PS_ZERO=$(echo "$RESPONSE_ZERO_PS" | jq '.meta.page_size')
run_test "Zero page_size uses default" "[[ '$PS_ZERO' == '20' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?page=abc")
set -e
run_test "Invalid page format rejected" "[[ '$STATUS' == '400' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?page_size=xyz")
set -e
run_test "Invalid page_size format rejected" "[[ '$STATUS' == '400' ]]"

# =============================================================================
# TEST 8: Filter by Status
# =============================================================================
test_section "Filter by Status"

# Reserve one order
reserve_order "$DRONE1_ID" "$DRONE1_TOKEN" "$ORDER1_ID" > /dev/null

RESPONSE_PENDING=$(req_auth GET '/admin/orders?status=pending' "$ADMIN_TOKEN" '' 200)
PENDING_COUNT=$(echo "$RESPONSE_PENDING" | jq '[.data[] | select(.status == "pending")] | length')
TOTAL_COUNT=$(echo "$RESPONSE_PENDING" | jq '.data | length')
run_test "Filter by status=pending returns pending orders" "[[ '$TOTAL_COUNT' == '$PENDING_COUNT' ]]"

RESPONSE_RESERVED=$(req_auth GET '/admin/orders?status=reserved' "$ADMIN_TOKEN" '' 200)
RESERVED_COUNT=$(echo "$RESPONSE_RESERVED" | jq '[.data[] | select(.status == "reserved")] | length')
TOTAL_RESERVED=$(echo "$RESPONSE_RESERVED" | jq '.data | length')
run_test "Filter by status=reserved returns reserved orders" "[[ '$TOTAL_RESERVED' == '$RESERVED_COUNT' ]]"

HAS_ORDER1=$(echo "$RESPONSE_RESERVED" | jq --arg id "$ORDER1_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
run_test "Reserved filter includes ORDER1" "[[ '$HAS_ORDER1' == '1' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?status=invalid_status")
set -e
run_test "Filter by invalid status rejected" "[[ '$STATUS' == '400' ]]"

# =============================================================================
# TEST 9: Filter by Enduser ID
# =============================================================================
test_section "Filter by Enduser ID"

RESPONSE_USER1=$(req_auth GET "/admin/orders?enduser_id=${ENDUSER1_ID}" "$ADMIN_TOKEN" '' 200)
USER1_COUNT=$(echo "$RESPONSE_USER1" | jq '.data | length')
run_test "Filter by enduser_id returns correct orders" "[[ $USER1_COUNT -ge 2 ]]"

HAS_O1=$(echo "$RESPONSE_USER1" | jq --arg id "$ORDER1_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
HAS_O2=$(echo "$RESPONSE_USER1" | jq --arg id "$ORDER2_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
run_test "Filter includes ORDER1 and ORDER2" "[[ '$HAS_O1' == '1' && '$HAS_O2' == '1' ]]"

HAS_O3=$(echo "$RESPONSE_USER1" | jq --arg id "$ORDER3_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
run_test "Filter excludes ORDER3" "[[ '$HAS_O3' == '0' ]]"

RESPONSE_USER2=$(req_auth GET "/admin/orders?enduser_id=${ENDUSER2_ID}" "$ADMIN_TOKEN" '' 200)
HAS_O3_U2=$(echo "$RESPONSE_USER2" | jq --arg id "$ORDER3_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
run_test "User2 filter includes ORDER3" "[[ '$HAS_O3_U2' == '1' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?enduser_id=abc")
set -e
run_test "Invalid enduser_id rejected" "[[ '$STATUS' == '400' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?enduser_id=-1")
set -e
run_test "Negative enduser_id rejected" "[[ '$STATUS' == '400' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?enduser_id=0")
set -e
run_test "Zero enduser_id rejected" "[[ '$STATUS' == '400' ]]"

RESPONSE_NOUSER=$(req_auth GET '/admin/orders?enduser_id=999999' "$ADMIN_TOKEN" '' 200)
NO_USER_COUNT=$(echo "$RESPONSE_NOUSER" | jq '.data | length')
run_test "Non-existent enduser_id returns empty" "[[ '$NO_USER_COUNT' == '0' ]]"

# =============================================================================
# TEST 10: Filter by Assigned Drone ID
# =============================================================================
test_section "Filter by Assigned Drone ID"

# Reserve ORDER2 for this test (ORDER1 is already reserved from previous test)
reserve_order "$DRONE2_ID" "$DRONE2_TOKEN" "$ORDER2_ID" > /dev/null 2>&1 || true

RESPONSE_DRONE1=$(req_auth GET "/admin/orders?assigned_drone_id=${DRONE1_ID}" "$ADMIN_TOKEN" '' 200)
DRONE1_COUNT=$(echo "$RESPONSE_DRONE1" | jq '.data | length')
run_test "Filter by assigned_drone_id returns orders" "[[ $DRONE1_COUNT -ge 1 ]]"

HAS_O1_D1=$(echo "$RESPONSE_DRONE1" | jq --arg id "$ORDER1_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
run_test "Drone1 filter includes ORDER1" "[[ '$HAS_O1_D1' == '1' ]]"

HAS_O2_D1=$(echo "$RESPONSE_DRONE1" | jq --arg id "$ORDER2_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
run_test "Drone1 filter excludes ORDER2 (assigned to drone2)" "[[ '$HAS_O2_D1' == '0' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?assigned_drone_id=abc")
set -e
run_test "Invalid assigned_drone_id rejected" "[[ '$STATUS' == '400' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?assigned_drone_id=-1")
set -e
run_test "Negative assigned_drone_id rejected" "[[ '$STATUS' == '400' ]]"

set +e
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "${BASE}/admin/orders?assigned_drone_id=0")
set -e
run_test "Zero assigned_drone_id rejected" "[[ '$STATUS' == '400' ]]"

# Reset drones and orders after TEST 10 to prepare for TEST 11
# TEST 11 needs ORDER2 to be pending, but TEST 10 reserved it with DRONE2
# We need to fail the order first, then reset the drone
fail_order "$DRONE2_ID" "$DRONE2_TOKEN" "$ORDER2_ID" > /dev/null 2>&1 || true
mark_drone_fixed "$DRONE2_ID" "$ADMIN_TOKEN" 10.0 10.0 > /dev/null 2>&1 || true

# Recreate ORDER2 as pending for TEST 11
ORDER2_ID=$(create_order "$ENDUSER1_TOKEN" 3.0 3.0 4.0 4.0)

# =============================================================================
# TEST 11: Multiple Filters Combined
# =============================================================================
test_section "Multiple Filters Combined"

RESPONSE_COMBO1=$(req_auth GET "/admin/orders?status=pending&enduser_id=${ENDUSER1_ID}" "$ADMIN_TOKEN" '' 200)
COMBO1_COUNT=$(echo "$RESPONSE_COMBO1" | jq '.data | length')
run_test "Filter by status and enduser_id combined" "[[ $COMBO1_COUNT -ge 1 ]]"

HAS_O2_COMBO=$(echo "$RESPONSE_COMBO1" | jq --arg id "$ORDER2_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
run_test "Combined filter includes ORDER2" "[[ '$HAS_O2_COMBO' == '1' ]]"

HAS_O1_COMBO=$(echo "$RESPONSE_COMBO1" | jq --arg id "$ORDER1_ID" '[.data[] | select(.order_id == ($id | tonumber))] | length')
run_test "Combined filter excludes ORDER1 (wrong status)" "[[ '$HAS_O1_COMBO' == '0' ]]"

RESPONSE_COMBO2=$(req_auth GET "/admin/orders?status=reserved&assigned_drone_id=${DRONE1_ID}" "$ADMIN_TOKEN" '' 200)
COMBO2_COUNT=$(echo "$RESPONSE_COMBO2" | jq '.data | length')
run_test "Filter by status and assigned_drone_id" "[[ $COMBO2_COUNT -ge 1 ]]"

RESPONSE_COMBO3=$(req_auth GET "/admin/orders?status=reserved&enduser_id=${ENDUSER1_ID}&assigned_drone_id=${DRONE1_ID}" "$ADMIN_TOKEN" '' 200)
COMBO3_COUNT=$(echo "$RESPONSE_COMBO3" | jq '.data | length')
run_test "All three filters combined work" "[[ $COMBO3_COUNT -ge 1 ]]"

# =============================================================================
# TEST 12: Filters with Pagination
# =============================================================================
test_section "Filters with Pagination"

RESPONSE_FP1=$(req_auth GET '/admin/orders?status=pending&page=1&page_size=1' "$ADMIN_TOKEN" '' 200)
FP1_COUNT=$(echo "$RESPONSE_FP1" | jq '.data | length')
FP1_PAGE=$(echo "$RESPONSE_FP1" | jq '.meta.page')
run_test "Filter with pagination page=1" "[[ '$FP1_COUNT' == '1' && '$FP1_PAGE' == '1' ]]"

RESPONSE_FP2=$(req_auth GET '/admin/orders?status=pending&page=2&page_size=1' "$ADMIN_TOKEN" '' 200)
FP2_PAGE=$(echo "$RESPONSE_FP2" | jq '.meta.page')
run_test "Filter with pagination page=2" "[[ '$FP2_PAGE' == '2' ]]"

# =============================================================================
# TEST 13: Has Next Indicator
# =============================================================================
test_section "Has Next Indicator"

RESPONSE_HN=$(req_auth GET '/admin/orders?page_size=1' "$ADMIN_TOKEN" '' 200)
HAS_NEXT_TRUE=$(echo "$RESPONSE_HN" | jq '.meta.has_next')
run_test "has_next true when more data exists" "[[ '$HAS_NEXT_TRUE' == 'true' ]]"

RESPONSE_HN_FALSE=$(req_auth GET '/admin/orders?page=999' "$ADMIN_TOKEN" '' 200)
HAS_NEXT_FALSE=$(echo "$RESPONSE_HN_FALSE" | jq '.meta.has_next')
run_test "has_next false when no more data" "[[ '$HAS_NEXT_FALSE' == 'false' ]]"

# =============================================================================
# TEST 14: Empty Page Beyond Available Data
# =============================================================================
test_section "Empty Page Beyond Available Data"

RESPONSE_HIGH=$(req_auth GET '/admin/orders?page=999' "$ADMIN_TOKEN" '' 200)
HIGH_COUNT=$(echo "$RESPONSE_HIGH" | jq '.data | length')
run_test "High page number returns empty array" "[[ '$HIGH_COUNT' == '0' ]]"

HIGH_PAGE=$(echo "$RESPONSE_HIGH" | jq '.meta.page')
run_test "High page number meta.page is 999" "[[ '$HIGH_PAGE' == '999' ]]"

HIGH_HAS_NEXT=$(echo "$RESPONSE_HIGH" | jq '.meta.has_next')
run_test "High page has_next is false" "[[ '$HIGH_HAS_NEXT' == 'false' ]]"

# =============================================================================
# TEST 15: Order Details in List Response
# =============================================================================
test_section "Order Details in List Response"

# Pick up ORDER1
pickup_order "$DRONE1_ID" "$DRONE1_TOKEN" "$ORDER1_ID" > /dev/null

RESPONSE_PICKEDUP=$(req_auth GET '/admin/orders?status=picked_up' "$ADMIN_TOKEN" '' 200)
PICKEDUP_COUNT=$(echo "$RESPONSE_PICKEDUP" | jq '.data | length')
run_test "List includes picked_up orders" "[[ $PICKEDUP_COUNT -ge 1 ]]"

ORDER_ASSIGNED=$(echo "$RESPONSE_PICKEDUP" | jq --arg id "$ORDER1_ID" '.data[] | select(.order_id == ($id | tonumber))')
ASSIGNED_DRONE=$(echo "$ORDER_ASSIGNED" | jq '.assigned_drone_id')
run_test "Order shows assigned_drone_id" "[[ '$ASSIGNED_DRONE' == '$DRONE1_ID' ]]"

# Cancel ORDER3
cancel_order "$ENDUSER2_TOKEN" "$ORDER3_ID" > /dev/null

RESPONSE_CANCELED=$(req_auth GET '/admin/orders?status=canceled' "$ADMIN_TOKEN" '' 200)
CANCELED_COUNT=$(echo "$RESPONSE_CANCELED" | jq '.data | length')
run_test "List includes canceled orders" "[[ $CANCELED_COUNT -ge 1 ]]"

ORDER_CANCELED=$(echo "$RESPONSE_CANCELED" | jq --arg id "$ORDER3_ID" '.data[] | select(.order_id == ($id | tonumber))')
HAS_CANCELED_AT=$(echo "$ORDER_CANCELED" | jq 'has("canceled_at") and .canceled_at != null')
run_test "Canceled order shows canceled_at" "[[ '$HAS_CANCELED_AT' == 'true' ]]"

# =============================================================================
# TEST 16: Consistent Ordering
# =============================================================================
test_section "Consistent Ordering Across Requests"

RESPONSE_FIRST=$(req_auth GET '/admin/orders?page_size=5' "$ADMIN_TOKEN" '' 200)
RESPONSE_SECOND=$(req_auth GET '/admin/orders?page_size=5' "$ADMIN_TOKEN" '' 200)
FIRST_ID=$(echo "$RESPONSE_FIRST" | jq '.data[0].order_id')
SECOND_ID=$(echo "$RESPONSE_SECOND" | jq '.data[0].order_id')
run_test "Same filters return same order" "[[ '$FIRST_ID' == '$SECOND_ID' ]]"

# =============================================================================
# CLEANUP
# =============================================================================
test_section "Cleanup"

mark_drone_fixed "$DRONE1_ID" "$ADMIN_TOKEN" 0.0 0.0 > /dev/null
DRONE1_STATUS=$(get_drone_status "$DRONE1_ID" "$ADMIN_TOKEN")
run_test "Drone1 returned to idle" "[[ '$DRONE1_STATUS' == 'idle' ]]"

mark_drone_fixed "$DRONE2_ID" "$ADMIN_TOKEN" 10.0 10.0 > /dev/null
DRONE2_STATUS=$(get_drone_status "$DRONE2_ID" "$ADMIN_TOKEN")
run_test "Drone2 returned to idle" "[[ '$DRONE2_STATUS' == 'idle' ]]"

print_summary "Admin Order List (GET /admin/orders)"
