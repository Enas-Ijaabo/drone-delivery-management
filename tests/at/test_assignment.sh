#!/usr/bin/env bash
# Test suite for order assignment notifications via WebSocket
set -euo pipefail

source "$(dirname "$0")/test_common.sh"

# Allow helper scripts that need python modules
set +e
set +u
set +o pipefail

get_token_and_id() {
  local user="$1" pass="$2" var_prefix="$3"
  local resp
  resp=$(req POST /auth/token "{\"name\":\"$user\",\"password\":\"$pass\"}" 200)
  local token id
  token=$(echo "$resp" | jq -r '.access_token')
  id=$(echo "$resp" | jq -r '.user.id')
  eval "${var_prefix}_TOKEN=\$token"
  eval "${var_prefix}_ID=\$id"
}

get_token_and_id "enduser1" "password" "ENDUSER"
get_token_and_id "drone1" "password" "DRONE1"
get_token_and_id "drone2" "password" "DRONE2"

WS_SCRIPT="$(dirname "$0")/tools/ws_full_test.py"
if [[ ! -f "$WS_SCRIPT" ]]; then
  echo "ERROR: missing $WS_SCRIPT" >&2
  exit 1
fi

ws_wait_assignment() {
  local token="$1" timeout="$2" file="$3"
  python3 "$WS_SCRIPT" "$token" wait_assignment "$timeout" >"$file" 2>&1
  echo $? >"${file}.exit"
}

ws_send_ack() {
  local token="$1" order_id="$2" status="$3"
  python3 "$WS_SCRIPT" "$token" send_ack "$order_id" "$status" >/dev/null 2>&1
}

ws_heartbeat() {
  local token="$1" lat="$2" lng="$3"
  python3 "$WS_SCRIPT" "$token" heartbeat "$lat" "$lng" >/dev/null 2>&1
}

# Reset drone state
reset_drone_state() {
  local token="$1"
  local order_id
  order_id=$(create_order "$ENDUSER_TOKEN" 0 0 0.1 0.1 2>/dev/null || echo "")
  if [[ -n "$order_id" ]]; then
    req_auth POST /orders/"$order_id"/reserve "$token" '' 200 >/dev/null 2>&1 || true
    req_auth POST /orders/"$order_id"/fail "$token" '' 200 >/dev/null 2>&1 || true
  fi
}

reset_drone_state "$DRONE1_TOKEN"
reset_drone_state "$DRONE2_TOKEN"

test_section "Assignment Notification"

# Set known heartbeat location for drone1
ws_heartbeat "$DRONE1_TOKEN" 30.0 35.0

ASSIGN_FILE=$(mktemp)
ws_wait_assignment "$DRONE1_TOKEN" 10 "$ASSIGN_FILE" &
LISTENER_PID=$!
sleep 1

ORDER_ID=$(create_order "$ENDUSER_TOKEN" 30.1 35.1 30.2 35.2)
run_test "Order created" "[[ -n \"$ORDER_ID\" ]]"

wait "$LISTENER_PID"
LISTENER_RC=$(cat "${ASSIGN_FILE}.exit")
ASSIGN_PAYLOAD=$(cat "$ASSIGN_FILE")
run_test "Assignment notification received" "[[ $LISTENER_RC -eq 0 ]]"

ASSIGN_ORDER_ID=$(echo "$ASSIGN_PAYLOAD" | jq -r '.order_id')
run_test "Assignment references created order" "[[ \"$ASSIGN_ORDER_ID\" == \"$ORDER_ID\" ]]"

ws_send_ack "$DRONE1_TOKEN" "$ORDER_ID" "accepted"

req_auth POST /orders/"$ORDER_ID"/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/"$ORDER_ID"/fail "$DRONE1_TOKEN" '' 200 >/dev/null

rm -f "$ASSIGN_FILE" "${ASSIGN_FILE}.exit"

test_section "Far Order Still Pending"

FAR_ORDER_ID=$(create_order "$ENDUSER_TOKEN" 60.0 60.0 60.1 60.1)
run_test "Far order created" "[[ -n \"$FAR_ORDER_ID\" ]]"

sleep 1

ORDER_STATUS_JSON=$(req_auth GET /orders/"$FAR_ORDER_ID" "$ENDUSER_TOKEN" '' 200)
ORDER_STATUS=$(echo "$ORDER_STATUS_JSON" | jq -r '.status')
ASSIGNED_DRONE=$(echo "$ORDER_STATUS_JSON" | jq -r '.assigned_drone_id')

run_test "Far order remains pending" "[[ \"$ORDER_STATUS\" == \"pending\" ]]"
run_test "Far order has no assigned drone" "[[ \"$ASSIGNED_DRONE\" == \"null\" ]]"

test_section "Nearest Drone Selection"

# Position drones at different locations
ws_heartbeat "$DRONE1_TOKEN" 30.0 35.0  # Close to pickup
ws_heartbeat "$DRONE2_TOKEN" 32.0 37.0  # Far from pickup

ASSIGN2_FILE=$(mktemp)
ws_wait_assignment "$DRONE1_TOKEN" 10 "$ASSIGN2_FILE" &
LISTENER2_PID=$!
sleep 1

# Create order near drone1
NEAR_ORDER_ID=$(create_order "$ENDUSER_TOKEN" 30.1 35.1 30.2 35.2)
run_test "Order created near drone1" "[[ -n \"$NEAR_ORDER_ID\" ]]"

wait "$LISTENER2_PID"
LISTENER2_RC=$(cat "${ASSIGN2_FILE}.exit")
ASSIGN2_PAYLOAD=$(cat "$ASSIGN2_FILE")
run_test "Nearest drone (drone1) receives assignment" "[[ $LISTENER2_RC -eq 0 ]]"

ASSIGN2_ORDER_ID=$(echo "$ASSIGN2_PAYLOAD" | jq -r '.order_id')
ASSIGN2_DRONE_ID=$(echo "$ASSIGN2_PAYLOAD" | jq -r '.drone_id')
run_test "Assignment contains correct order_id" "[[ \"$ASSIGN2_ORDER_ID\" == \"$NEAR_ORDER_ID\" ]]"
run_test "Assignment sent to nearest drone" "[[ \"$ASSIGN2_DRONE_ID\" == \"$DRONE1_ID\" ]]"

# Cleanup
req_auth POST /orders/"$NEAR_ORDER_ID"/reserve "$DRONE1_TOKEN" '' 200 >/dev/null
req_auth POST /orders/"$NEAR_ORDER_ID"/fail "$DRONE1_TOKEN" '' 200 >/dev/null

rm -f "$ASSIGN2_FILE" "${ASSIGN2_FILE}.exit"

test_section "Final Cleanup"

reset_drone_state "$DRONE1_TOKEN"
reset_drone_state "$DRONE2_TOKEN"

run_test "Drone1 returned to idle state" "true"
run_test "Drone2 returned to idle state" "true"

print_summary "Assignment Notifications"
