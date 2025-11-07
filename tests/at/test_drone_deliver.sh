#!/bin/bash
set -e

BASE="http://localhost:8080"

echo "========================================="
echo "Testing POST /orders/:id/deliver endpoint"
echo "========================================="
echo

# Wait for service
echo "Waiting for service to be ready..."
sleep 3

# Get tokens
echo "1. Getting authentication tokens..."
ENDUSER_TOKEN=$(curl -s -X POST "$BASE/auth/token" \
  -H "Content-Type: application/json" \
  -d '{"name":"enduser1","password":"password"}' | jq -r '.access_token')

DRONE_TOKEN=$(curl -s -X POST "$BASE/auth/token" \
  -H "Content-Type: application/json" \
  -d '{"name":"drone1","password":"password"}' | jq -r '.access_token')

echo "✓ Got enduser token"
echo "✓ Got drone token"
echo

# Create and reserve an order first
echo "2. Creating and reserving an order..."
ORDER_RESP=$(curl -s -X POST "$BASE/orders" \
  -H "Authorization: Bearer $ENDUSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pickup_lat": 40.758,
    "pickup_lng": -73.9855,
    "dropoff_lat": 40.7829,
    "dropoff_lng": -73.9654
  }')

ORDER_ID=$(echo "$ORDER_RESP" | jq -r '.order_id')
echo "✓ Created order ID: $ORDER_ID"

# Setup drone with location
docker-compose exec -T db mysql -u root -pexample drone <<EOF
INSERT INTO drone_status (drone_id, status, lat, lng, last_heartbeat_at) 
VALUES (4, 'idle', 40.748817, -73.985428, NOW())
ON DUPLICATE KEY UPDATE 
  status='idle', 
  lat=40.748817, 
  lng=-73.985428, 
  last_heartbeat_at=NOW(),
  current_order_id=NULL;
EOF

# Reserve the order
RESERVE_RESP=$(curl -s -X POST "$BASE/orders/$ORDER_ID/reserve" \
  -H "Authorization: Bearer $DRONE_TOKEN")

echo "✓ Order reserved with status: $(echo "$RESERVE_RESP" | jq -r '.status')"
echo

# Test: Deliver order from wrong state (should fail)
echo "3. Testing deliver from 'reserved' state (should fail with 409)..."
WRONG_STATE_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/$ORDER_ID/deliver" \
  -H "Authorization: Bearer $DRONE_TOKEN")

HTTP_CODE=$(echo "$WRONG_STATE_RESP" | tail -n 1)
BODY=$(echo "$WRONG_STATE_RESP" | sed '$d')

echo "HTTP Code: $HTTP_CODE"
echo "$BODY" | jq '.'

if [[ "$HTTP_CODE" == "409" ]]; then
  echo "✓ Correctly rejected delivery from wrong state"
else
  echo "✗ FAIL: Expected 409, got $HTTP_CODE"
  exit 1
fi
echo

# Update order to picked_up state
echo "4. Updating order to 'picked_up' state..."
docker-compose exec -T db mysql -u root -pexample drone <<EOF
UPDATE orders SET status = 'picked_up' WHERE id = $ORDER_ID;
UPDATE drone_status SET status = 'delivering' WHERE drone_id = 4;
EOF
echo "✓ Order status updated to 'picked_up'"
echo

# Test: Deliver order successfully
echo "5. Testing deliver order (drone token, valid picked_up order)..."
DELIVER_RESP=$(curl -s -X POST "$BASE/orders/$ORDER_ID/deliver" \
  -H "Authorization: Bearer $DRONE_TOKEN")

echo "$DELIVER_RESP" | jq '.'

# Validate response
STATUS=$(echo "$DELIVER_RESP" | jq -r '.status')

if [[ "$STATUS" == "delivered" ]]; then
  echo "✓ Order successfully delivered!"
else
  echo "✗ FAIL: Expected status='delivered'"
  echo "  Got: status=$STATUS"
  exit 1
fi
echo

# Test: Try to deliver already delivered order (should fail)
echo "6. Testing deliver already delivered order (should fail with 409)..."
DUPLICATE_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/$ORDER_ID/deliver" \
  -H "Authorization: Bearer $DRONE_TOKEN")

HTTP_CODE=$(echo "$DUPLICATE_RESP" | tail -n 1)
BODY=$(echo "$DUPLICATE_RESP" | sed '$d')

echo "HTTP Code: $HTTP_CODE"
echo "$BODY" | jq '.'

if [[ "$HTTP_CODE" == "409" ]]; then
  echo "✓ Correctly rejected duplicate delivery"
else
  echo "✗ FAIL: Expected 409, got $HTTP_CODE"
  exit 1
fi
echo

# Test: Create another order and try to deliver with wrong drone
echo "7. Testing deliver order assigned to different drone (should fail with 404)..."
ORDER2_RESP=$(curl -s -X POST "$BASE/orders" \
  -H "Authorization: Bearer $ENDUSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pickup_lat": 40.760,
    "pickup_lng": -73.987,
    "dropoff_lat": 40.785,
    "dropoff_lng": -73.967
  }')

ORDER2_ID=$(echo "$ORDER2_RESP" | jq -r '.order_id')

# Manually assign to a different drone and set to picked_up
docker-compose exec -T db mysql -u root -pexample drone <<EOF
UPDATE orders SET status = 'picked_up', assigned_drone_id = 999 WHERE id = $ORDER2_ID;
EOF

WRONG_DRONE_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/$ORDER2_ID/deliver" \
  -H "Authorization: Bearer $DRONE_TOKEN")

HTTP_CODE=$(echo "$WRONG_DRONE_RESP" | tail -n 1)
BODY=$(echo "$WRONG_DRONE_RESP" | sed '$d')

echo "HTTP Code: $HTTP_CODE"
echo "$BODY" | jq '.'

if [[ "$HTTP_CODE" == "404" ]]; then
  echo "✓ Correctly rejected delivery by wrong drone"
else
  echo "✗ FAIL: Expected 404, got $HTTP_CODE"
  exit 1
fi
echo

# Test: Try to deliver with enduser token (should fail with 403)
echo "8. Creating another order for authorization test..."
ORDER3_RESP=$(curl -s -X POST "$BASE/orders" \
  -H "Authorization: Bearer $ENDUSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pickup_lat": 40.762,
    "pickup_lng": -73.989,
    "dropoff_lat": 40.787,
    "dropoff_lng": -73.969
  }')

ORDER3_ID=$(echo "$ORDER3_RESP" | jq -r '.order_id')

echo "Testing deliver with enduser token (should fail with 403)..."
AUTH_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/$ORDER3_ID/deliver" \
  -H "Authorization: Bearer $ENDUSER_TOKEN")

HTTP_CODE=$(echo "$AUTH_RESP" | tail -n 1)
BODY=$(echo "$AUTH_RESP" | sed '$d')

echo "HTTP Code: $HTTP_CODE"
echo "$BODY" | jq '.'

if [[ "$HTTP_CODE" == "403" ]]; then
  echo "✓ Correctly rejected enduser attempting to deliver"
else
  echo "✗ FAIL: Expected 403, got $HTTP_CODE"
  exit 1
fi
echo

# Test: Try to deliver without token (should fail with 401)
echo "9. Testing deliver without token (should fail with 401)..."
NO_TOKEN_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/$ORDER_ID/deliver")

HTTP_CODE=$(echo "$NO_TOKEN_RESP" | tail -n 1)

echo "HTTP Code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "401" ]]; then
  echo "✓ Correctly rejected unauthenticated request"
else
  echo "✗ FAIL: Expected 401, got $HTTP_CODE"
  exit 1
fi
echo

# Test: Try to deliver non-existent order (should fail with 404)
echo "10. Testing deliver non-existent order (should fail with 404)..."
NOT_FOUND_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/99999/deliver" \
  -H "Authorization: Bearer $DRONE_TOKEN")

HTTP_CODE=$(echo "$NOT_FOUND_RESP" | tail -n 1)
BODY=$(echo "$NOT_FOUND_RESP" | sed '$d')

echo "HTTP Code: $HTTP_CODE"
echo "$BODY" | jq '.'

if [[ "$HTTP_CODE" == "404" ]]; then
  echo "✓ Correctly returned 404 for non-existent order"
else
  echo "✗ FAIL: Expected 404, got $HTTP_CODE"
  exit 1
fi
echo

# Verify drone status was updated
echo "11. Verifying drone status was updated to idle..."
DRONE_STATUS=$(docker-compose exec -T db mysql -u root -pexample drone -sN \
  -e "SELECT status, current_order_id FROM drone_status WHERE drone_id = 4")

DRONE_ST=$(echo "$DRONE_STATUS" | awk '{print $1}')
CURRENT_ORDER=$(echo "$DRONE_STATUS" | awk '{print $2}')

echo "Drone status: $DRONE_ST"
echo "Current order: $CURRENT_ORDER"

if [[ "$DRONE_ST" == "idle" ]] && [[ "$CURRENT_ORDER" == "NULL" ]]; then
  echo "✓ Drone status correctly updated to idle with no current order"
else
  echo "✗ FAIL: Expected drone status='idle' and current_order_id=NULL"
  echo "  Got: status=$DRONE_ST, current_order=$CURRENT_ORDER"
  exit 1
fi
echo

echo "========================================="
echo "✅ All tests passed!"
echo "========================================="
