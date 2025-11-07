#!/usr/bin/env bash
# Test suite for POST /orders/:id/reserve
set -euo pipefail

source "$(dirname "$0")/test_common.sh"

reset_drones
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")
DRONE1_TOKEN=$(get_token "drone1" "password")
DRONE2_TOKEN=$(get_token "drone2" "password")

test_section "Reserve - Auth"
ORDER=$(create_order "$ENDUSER_TOKEN" 31.9 35.9 32.0 36.0)
run_test "no auth -> 401" "req POST /orders/$ORDER/reserve '' 401"
run_test "invalid token -> 401" "req_auth POST /orders/$ORDER/reserve 'bad' '' 401"
run_test "enduser token -> 403" "req_auth POST /orders/$ORDER/reserve '$ENDUSER_TOKEN' '' 403"
run_test "admin token -> 403" "req_auth POST /orders/$ORDER/reserve '$ADMIN_TOKEN' '' 403"

test_section "Reserve - Order ID Validation"
run_test "invalid ID -> 400" "req_auth POST /orders/abc/reserve '$DRONE1_TOKEN' '' 400"
run_test "zero -> 400" "req_auth POST /orders/0/reserve '$DRONE1_TOKEN' '' 400"
run_test "negative -> 400" "req_auth POST /orders/-1/reserve '$DRONE1_TOKEN' '' 400"
run_test "non-existent -> 404" "req_auth POST /orders/999999/reserve '$DRONE1_TOKEN' '' 404"

test_section "Reserve - Valid"
run_test "valid pending order -> 200" "req_auth POST /orders/$ORDER/reserve '$DRONE1_TOKEN' '' 200"
verify_json_field ".status" "reserved" "$LAST_RESPONSE"

test_section "Reserve - Status Transitions"
run_test "already reserved -> 409" "req_auth POST /orders/$ORDER/reserve '$DRONE1_TOKEN' '' 409"

O2=$(create_order "$ENDUSER_TOKEN" 32 36 32.1 36.1)
req_auth POST /orders/$O2/cancel "$ENDUSER_TOKEN" '' 200 >/dev/null
run_test "canceled -> 409" "req_auth POST /orders/$O2/reserve '$DRONE2_TOKEN' '' 409"

reset_drones
O3=$(create_order "$ENDUSER_TOKEN" 33 37 33.1 37.1)
req_auth POST /orders/$O3/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$O3/pickup "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$O3/deliver "$DRONE1_TOKEN" '' 200 >/dev/null
run_test "delivered -> 409" "req_auth POST /orders/$O3/reserve '$DRONE2_TOKEN' '' 409"

reset_drones
O4=$(create_order "$ENDUSER_TOKEN" 34 38 34.1 38.1)
req_auth POST /orders/$O4/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$O4/fail "$DRONE1_TOKEN" '' 200 >/dev/null
run_test "failed -> 409" "req_auth POST /orders/$O4/reserve '$DRONE2_TOKEN' '' 409"

reset_drones
O5=$(create_order "$ENDUSER_TOKEN" 35 39 35.1 39.1)
req_auth POST /orders/$O5/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/$O5/pickup "$DRONE1_TOKEN" '' 200 >/dev/null
run_test "picked_up -> 409" "req_auth POST /orders/$O5/reserve '$DRONE2_TOKEN' '' 409"

print_summary "POST /orders/:id/reserve"
