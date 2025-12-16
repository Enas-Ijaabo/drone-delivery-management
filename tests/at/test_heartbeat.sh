#!/usr/bin/env bash
# Test suite for WebSocket /ws/heartbeat endpoint
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
DRONE1_TOKEN=$(get_token "drone1" "password")
DRONE2_TOKEN=$(get_token "drone2" "password")

# Clean up any orders assigned to test drones to ensure they're idle
# Create a dummy order and try to fail any existing orders
CLEANUP_ORDER=$(create_order "$ENDUSER_TOKEN" 29 35 29.1 35.1 2>/dev/null || echo "")
if [[ -n "$CLEANUP_ORDER" ]]; then
  # Try to free drone1
  req_auth POST /orders/$CLEANUP_ORDER/reserve "$DRONE1_TOKEN" '' 200 >/dev/null 2>&1 && \
    req_auth POST /orders/$CLEANUP_ORDER/fail "$DRONE1_TOKEN" '' 200 >/dev/null 2>&1 || true
  
  # Try to free drone2  
  CLEANUP_ORDER2=$(create_order "$ENDUSER_TOKEN" 28 34 28.1 34.1 2>/dev/null || echo "")
  if [[ -n "$CLEANUP_ORDER2" ]]; then
    req_auth POST /orders/$CLEANUP_ORDER2/reserve "$DRONE2_TOKEN" '' 200 >/dev/null 2>&1 && \
      req_auth POST /orders/$CLEANUP_ORDER2/fail "$DRONE2_TOKEN" '' 200 >/dev/null 2>&1 || true
  fi
fi

# WebSocket testing helper using Python script
ws_test() {
  local token="$1"
  local message="$2"
  local expected_type="$3"  # "ok" or "error"
  
  local script_dir="$(dirname "$0")/tools"
  local ws_script="$script_dir/ws_test.py"
  
  if [[ ! -f "$ws_script" ]]; then
    echo "ERROR: ws_test.py not found" >&2
    return 1
  fi
  
  local response
  response=$(python3 "$ws_script" "$token" "$message" 2>&1)
  local exit_code=$?
  
  # Exit code 2 means missing dependencies
  if [[ $exit_code -eq 2 ]]; then
    echo "SKIP: websockets module not installed"
    return 2
  fi
  
  # Check if response matches expected type
  if [[ "$expected_type" == "ok" && $exit_code -eq 0 ]]; then
    return 0
  elif [[ "$expected_type" == "error" && $exit_code -eq 1 ]]; then
    return 0
  else
    echo "Response: $response" >&2
    return 1
  fi
}

# Check if WebSocket testing is available
check_ws_available() {
  if ! command -v python3 &> /dev/null; then
    echo "SKIP: python3 not available"
    print_summary "WebSocket /ws/heartbeat"
    exit 0
  fi
  
  # Try a dummy connection to check websockets module
  local script_dir="$(dirname "$0")/tools"
  local ws_script="$script_dir/ws_test.py"
  
  if python3 "$ws_script" "dummy" "{}" 2>&1 | grep -q "websockets module not installed"; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SKIP: Python websockets module not installed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "To run WebSocket tests, install the websockets module:"
    echo "  pip3 install websockets"
    echo ""
    echo "Or use homebrew to install websocat:"
    echo "  brew install websocat"
    echo ""
    
    # Print minimal summary
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "Test Summary: WebSocket /ws/heartbeat"
    echo "═══════════════════════════════════════════════════"
    echo "Total Tests: 0"
    echo "Passed: 0"
    echo "Failed: 0"
    echo "Success Rate: N/A (skipped)"
    echo "═══════════════════════════════════════════════════"
    echo ""
    exit 0
  fi
}

# =============================================================================
# CHECK PREREQUISITES
# =============================================================================
test_section "WebSocket Heartbeat - Prerequisites"
check_ws_available

# =============================================================================
# AUTH & AUTHORIZATION TESTS (HTTP UPGRADE)
# =============================================================================
test_section "WebSocket Heartbeat - Authentication"

# Note: WebSocket auth happens during upgrade, hard to test without WS client
# We'll test via actual WebSocket connections

run_test "WS heartbeat with valid drone token (drone1) -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.9454,\"lng\":35.9284}' 'ok'"

run_test "WS heartbeat with valid drone token (drone2) -> ok" \
  "ws_test '$DRONE2_TOKEN' '{\"lat\":32.0000,\"lng\":36.0000}' 'ok'"

# =============================================================================
# VALID HEARTBEAT MESSAGES
# =============================================================================
test_section "WebSocket Heartbeat - Valid Messages"

run_test "WS heartbeat with standard coordinates -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.9454,\"lng\":35.9284}' 'ok'"

run_test "WS heartbeat with zero coordinates -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":0.0,\"lng\":0.0}' 'ok'"

run_test "WS heartbeat with negative coordinates -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":-31.9454,\"lng\":-35.9284}' 'ok'"

run_test "WS heartbeat with boundary min lat -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":-90.0,\"lng\":0.0}' 'ok'"

run_test "WS heartbeat with boundary max lat -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":90.0,\"lng\":0.0}' 'ok'"

run_test "WS heartbeat with boundary min lng -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":0.0,\"lng\":-180.0}' 'ok'"

run_test "WS heartbeat with boundary max lng -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":0.0,\"lng\":180.0}' 'ok'"

run_test "WS heartbeat with decimal precision -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.945678,\"lng\":35.928456}' 'ok'"

# =============================================================================
# MISSING FIELDS
# =============================================================================
test_section "WebSocket Heartbeat - Missing Fields"

run_test "WS heartbeat missing lat -> error" \
  "ws_test '$DRONE1_TOKEN' '{\"lng\":35.9284}' 'error'"

run_test "WS heartbeat missing lng -> error" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.9454}' 'error'"

run_test "WS heartbeat empty object -> error" \
  "ws_test '$DRONE1_TOKEN' '{}' 'error'"

# =============================================================================
# INVALID COORDINATES
# =============================================================================
test_section "WebSocket Heartbeat - Invalid Coordinates"

run_test "WS heartbeat lat > 90 -> error" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":91.0,\"lng\":35.9284}' 'error'"

run_test "WS heartbeat lat < -90 -> error" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":-91.0,\"lng\":35.9284}' 'error'"

run_test "WS heartbeat lng > 180 -> error" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.9454,\"lng\":181.0}' 'error'"

run_test "WS heartbeat lng < -180 -> error" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.9454,\"lng\":-181.0}' 'error'"

# =============================================================================
# LOCATION PERSISTENCE
# =============================================================================
test_section "WebSocket Heartbeat - Location Updates"

# Use DRONE2 for this test to avoid state conflicts
ORDER_ID=$(create_order "$ENDUSER_TOKEN" 31.9 35.9 32.0 36.0)

# Reserve with DRONE2
if ! req_auth POST /orders/$ORDER_ID/reserve "$DRONE2_TOKEN" '' 200 >/dev/null 2>&1; then
  # Drone2 might be busy, skip this test
  ((TEST_COUNT++))
  ((FAIL_COUNT++))
  echo -e "${RED}✗${NC} GET order shows updated drone location (drone busy)"
else
  # Send heartbeat with specific location
  ws_test "$DRONE2_TOKEN" '{"lat":31.5555,"lng":35.6666}' 'ok' >/dev/null 2>&1 || true
  
  # Give a moment for DB update
  sleep 1
  
  # Check if location is reflected in order details
  run_test "GET order shows updated drone location" \
    "req_auth GET /orders/$ORDER_ID '$ENDUSER_TOKEN' '' 200 | grep -q '31.5555'"
  
  # Cleanup
  req_auth POST /orders/$ORDER_ID/fail "$DRONE2_TOKEN" '' 200 >/dev/null 2>&1 || true
fi

# =============================================================================
# MULTIPLE HEARTBEATS
# =============================================================================
test_section "WebSocket Heartbeat - Sequential Updates"

# Test that multiple heartbeats work on same connection
# This is harder to test in bash, but we can at least verify no crashes
run_test "WS multiple heartbeats in sequence -> ok" \
  "ws_test '$DRONE2_TOKEN' '{\"lat\":31.0,\"lng\":35.0}' 'ok' && \
   ws_test '$DRONE2_TOKEN' '{\"lat\":32.0,\"lng\":36.0}' 'ok' && \
   ws_test '$DRONE2_TOKEN' '{\"lat\":33.0,\"lng\":37.0}' 'ok'"

# =============================================================================
# INTEGRATION WITH ORDER STATES
# =============================================================================
test_section "WebSocket Heartbeat - Order Integration"

# Verify heartbeat works regardless of drone state
ORDER2_ID=$(create_order "$ENDUSER_TOKEN" 32.0 36.0 32.1 36.1)

run_test "WS heartbeat when drone is idle -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.1,\"lng\":35.1}' 'ok'"

req_auth POST /orders/$ORDER2_ID/reserve "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "WS heartbeat when drone is reserved -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.2,\"lng\":35.2}' 'ok'"

req_auth POST /orders/$ORDER2_ID/pickup "$DRONE1_TOKEN" '' 200 >/dev/null

run_test "WS heartbeat when drone is delivering -> ok" \
  "ws_test '$DRONE1_TOKEN' '{\"lat\":31.3,\"lng\":35.3}' 'ok'"

# Cleanup
req_auth POST /orders/$ORDER2_ID/deliver "$DRONE1_TOKEN" '' 200 >/dev/null

# =============================================================================
# FINAL CLEANUP - Ensure both drones are idle
# =============================================================================
test_section "WebSocket Heartbeat - Final Cleanup"

# Create cleanup orders and use them to reset drone states
FINAL_CLEANUP1=$(create_order "$ENDUSER_TOKEN" 29 35 29.1 35.1 2>/dev/null || echo "")
FINAL_CLEANUP2=$(create_order "$ENDUSER_TOKEN" 28 34 28.1 34.1 2>/dev/null || echo "")

if [[ -n "$FINAL_CLEANUP1" ]]; then
  # Try to reserve and fail to ensure drone1 is idle
  if req_auth POST /orders/$FINAL_CLEANUP1/reserve "$DRONE1_TOKEN" '' 200 >/dev/null 2>&1; then
    req_auth POST /orders/$FINAL_CLEANUP1/fail "$DRONE1_TOKEN" '' 200 >/dev/null 2>&1
  fi
fi

if [[ -n "$FINAL_CLEANUP2" ]]; then
  # Try to reserve and fail to ensure drone2 is idle
  if req_auth POST /orders/$FINAL_CLEANUP2/reserve "$DRONE2_TOKEN" '' 200 >/dev/null 2>&1; then
    req_auth POST /orders/$FINAL_CLEANUP2/fail "$DRONE2_TOKEN" '' 200 >/dev/null 2>&1
  fi
fi

# Verify both drones are idle by attempting a new reserve
VERIFY1=$(create_order "$ENDUSER_TOKEN" 30 35.5 30.1 35.6 2>/dev/null || echo "")
VERIFY2=$(create_order "$ENDUSER_TOKEN" 30.5 36 30.6 36.1 2>/dev/null || echo "")

if [[ -n "$VERIFY1" ]]; then
  run_test "Drone1 cleanup: can reserve new order" \
    "req_auth POST /orders/$VERIFY1/reserve '$DRONE1_TOKEN' '' 200"
  # Immediately fail to return to idle
  req_auth POST /orders/$VERIFY1/fail "$DRONE1_TOKEN" '' 200 >/dev/null 2>&1
fi

if [[ -n "$VERIFY2" ]]; then
  run_test "Drone2 cleanup: can reserve new order" \
    "req_auth POST /orders/$VERIFY2/reserve '$DRONE2_TOKEN' '' 200"
  # Immediately fail to return to idle
  req_auth POST /orders/$VERIFY2/fail "$DRONE2_TOKEN" '' 200 >/dev/null 2>&1
fi

print_summary "WebSocket /ws/heartbeat"
