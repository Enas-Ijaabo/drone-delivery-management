#!/usr/bin/env bash
# Test suite for GET /health endpoint
set -euo pipefail

# Source common test utilities
source "$(dirname "$0")/test_common.sh"

# Disable exit-on-error; run_test handles failures and summary prints
set +e

TEST_COUNT=0
PASS_COUNT=0

# =============================================================================
# HEALTH CHECK TESTS
# =============================================================================
test_section "Health Check"

run_test "GET /health -> 200" \
  "req GET /health '' 200"

run_test "Health response has correct content-type" \
  "curl -sf -w '%{content_type}' $BASE/health | grep -q 'text/plain'"

# =============================================================================
# SUMMARY
# =============================================================================
print_summary "GET /health"
