#!/usr/bin/env bash
# Test suite for POST /orders/:id/cancel endpoint
set -euo pipefail

source "$(dirname "$0")/test_common.sh"
set +e
set +u
set +o pipefail

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Get tokens
ADMIN_TOKEN=$(get_token "admin" "password")
ENDUSER_TOKEN=$(get_token "enduser1" "password")
ENDUSER2_TOKEN=$(get_token "enduser2" "password")

# =============================================================================
# AUTH & AUTHORIZATION
# =============================================================================
test_section "Order Cancel - Auth & Authorization"

run_test "POST /orders/:id/cancel without auth -> 401" \
  "req POST /orders/1/cancel '' 401"

run_test "POST /orders/:id/cancel with invalid token -> 401" \
  "req_auth POST /orders/1/cancel 'invalid.token' '' 401"

run_test "POST /orders/:id/cancel with admin token -> 403" \
  "req_auth POST /orders/1/cancel '$ADMIN_TOKEN' '' 403"

# =============================================================================
# VALID CANCELLATION
# =============================================================================
test_section "Order Cancel - Valid Requests"

# Create order to cancel
ORDER_ID=$(create_order "$ENDUSER_TOKEN" 31.9 35.9 32.0 36.0)

run_test "POST /orders/:id/cancel (pending order) -> 200" \
  "req_auth POST /orders/$ORDER_ID/cancel '$ENDUSER_TOKEN' '' 200"

run_test "cancel sets status=canceled" "verify_json_field '.status' 'canceled'"
run_test "cancel has canceled_at" "verify_json_has_field '.canceled_at'"

run_test "POST /orders/:id/cancel (already canceled) -> 409" \
  "req_auth POST /orders/$ORDER_ID/cancel '$ENDUSER_TOKEN' '' 409"

# =============================================================================
# OWNERSHIP VALIDATION
# =============================================================================
test_section "Order Cancel - Ownership"

ORDER2_ID=$(create_order "$ENDUSER2_TOKEN" 32.0 36.0 32.1 36.1)

run_test "POST /orders/:id/cancel (not owned by user) -> 403" \
  "req_auth POST /orders/$ORDER2_ID/cancel '$ENDUSER_TOKEN' '' 403"

# =============================================================================
# INVALID ORDER IDS
# =============================================================================
test_section "Order Cancel - Invalid Order IDs"

run_test "POST /orders/:id/cancel (non-existent) -> 404" \
  "req_auth POST /orders/99999/cancel '$ENDUSER_TOKEN' '' 404"

run_test "POST /orders/:id/cancel (invalid format) -> 400" \
  "req_auth POST /orders/abc/cancel '$ENDUSER_TOKEN' '' 400"

run_test "POST /orders/:id/cancel (zero) -> 400" \
  "req_auth POST /orders/0/cancel '$ENDUSER_TOKEN' '' 400"

run_test "POST /orders/:id/cancel (negative) -> 400" \
  "req_auth POST /orders/-1/cancel '$ENDUSER_TOKEN' '' 400"

# TODO: Test cancel reserved order (should fail - order already assigned to drone)
# TODO: Test cancel picked_up order (should fail)
# TODO: Test cancel delivered order (should fail)

print_summary "POST /orders/:id/cancel"
