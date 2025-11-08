#!/usr/bin/env bash
# Test suite for POST /auth/token endpoint
set -euo pipefail

# Source common test utilities
source "$(dirname "$0")/test_common.sh"

# Disable strict modes after sourcing; run_test handles result capturing
set +e
set +u
set +o pipefail

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# =============================================================================
# SUCCESSFUL AUTHENTICATION TESTS
# =============================================================================
test_section "Authentication - Success Cases"

run_test "POST /auth/token (admin) -> 200" \
  "req POST /auth/token '{\"name\":\"admin\",\"password\":\"password\"}' 200"

run_test "Auth(admin) response has access_token" "verify_json_has_field '.access_token'"
run_test "Auth(admin) token_type bearer" "verify_json_field '.token_type' 'bearer'"
run_test "Auth(admin) user.name" "verify_json_field '.user.name' 'admin'"
run_test "Auth(admin) user.type admin" "verify_json_field '.user.type' 'admin'"

run_test "POST /auth/token (enduser) -> 200" \
  "req POST /auth/token '{\"name\":\"enduser1\",\"password\":\"password\"}' 200"

run_test "Auth(enduser) user.type enduser" "verify_json_field '.user.type' 'enduser'"

run_test "POST /auth/token (drone) -> 200" \
  "req POST /auth/token '{\"name\":\"drone1\",\"password\":\"password\"}' 200"

run_test "Auth(drone) user.type drone" "verify_json_field '.user.type' 'drone'"

# =============================================================================
# FAILED AUTHENTICATION TESTS
# =============================================================================
test_section "Authentication - Failure Cases"

run_test "POST /auth/token (wrong password) -> 401" \
  "req POST /auth/token '{\"name\":\"admin\",\"password\":\"wrong\"}' 401"

run_test "POST /auth/token (unknown user) -> 401" \
  "req POST /auth/token '{\"name\":\"nouser\",\"password\":\"password\"}' 401"

# =============================================================================
# VALIDATION TESTS
# =============================================================================
test_section "Authentication - Validation"

run_test "POST /auth/token (empty body) -> 400" \
  "req POST /auth/token '' 400"

run_test "POST /auth/token (invalid json) -> 400" \
  "req POST /auth/token 'not-json' 400"

run_test "POST /auth/token (missing name) -> 400" \
  "req POST /auth/token '{\"password\":\"password\"}' 400"

run_test "POST /auth/token (missing password) -> 400" \
  "req POST /auth/token '{\"name\":\"admin\"}' 400"

run_test "POST /auth/token (empty name) -> 400" \
  "req POST /auth/token '{\"name\":\"\",\"password\":\"password\"}' 400"

run_test "POST /auth/token (empty password) -> 400" \
  "req POST /auth/token '{\"name\":\"admin\",\"password\":\"\"}' 400"

# TODO: Test expired token (requires time manipulation)
# TODO: Test token refresh (if implemented)
# TODO: Test rate limiting on auth endpoint

# =============================================================================
# SUMMARY
# =============================================================================
print_summary "POST /auth/token"
