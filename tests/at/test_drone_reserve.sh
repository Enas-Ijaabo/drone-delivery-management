#!/bin/bash
set -e

BASE="http://localhost:8080"

echo "========================================="
echo "Testing POST /orders/:id/reserve endpoint"
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

# Create a pending order
echo "2. Creating a pending order..."
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
echo "  Status: $(echo "$ORDER_RESP" | jq -r '.status')"
echo

# Setup drone with location
echo "3. Setting up drone with location..."
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
echo "✓ Drone setup complete"
echo

# Test: Reserve order with drone token
echo "4. Testing reserve order (drone token, valid pending order)..."
RESERVE_RESP=$(curl -s -X POST "$BASE/orders/$ORDER_ID/reserve" \
  -H "Authorization: Bearer $DRONE_TOKEN")

echo "$RESERVE_RESP" | jq '.'

# Validate response
STATUS=$(echo "$RESERVE_RESP" | jq -r '.status')
ASSIGNED_DRONE=$(echo "$RESERVE_RESP" | jq -r '.assigned_drone_id')

if [[ "$STATUS" == "reserved" ]] && [[ "$ASSIGNED_DRONE" == "4" ]]; then
  echo "✓ Order successfully reserved!"
else
  echo "✗ FAIL: Expected status='reserved' and assigned_drone_id=4"
  echo "  Got: status=$STATUS, assigned_drone_id=$ASSIGNED_DRONE"
  exit 1
fi
echo

# Test: Try to reserve already reserved order (should fail)
echo "5. Testing reserve already reserved order (should fail with 409)..."
DUPLICATE_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/$ORDER_ID/reserve" \
  -H "Authorization: Bearer $DRONE_TOKEN")

HTTP_CODE=$(echo "$DUPLICATE_RESP" | tail -n 1)
BODY=$(echo "$DUPLICATE_RESP" | sed '$d')

echo "HTTP Code: $HTTP_CODE"
echo "$BODY" | jq '.'

if [[ "$HTTP_CODE" == "409" ]]; then
  echo "✓ Correctly rejected duplicate reservation"
else
  echo "✗ FAIL: Expected 409, got $HTTP_CODE"
  exit 1
fi
echo

# Test: Try to reserve with enduser token (should fail with 403)
echo "6. Creating another order for authorization test..."
ORDER2_RESP=$(curl -s -X POST "$BASE/orders" \
  -H "Authorization: Bearer $ENDUSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pickup_lat": 40.76,
    "pickup_lng": -73.99,
    "dropoff_lat": 40.78,
    "dropoff_lng": -73.97
  }')
ORDER2_ID=$(echo "$ORDER2_RESP" | jq -r '.order_id')

echo "Testing reserve with enduser token (should fail with 403)..."
AUTH_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/$ORDER2_ID/reserve" \
  -H "Authorization: Bearer $ENDUSER_TOKEN")

HTTP_CODE=$(echo "$AUTH_RESP" | tail -n 1)
BODY=$(echo "$AUTH_RESP" | sed '$d')

echo "HTTP Code: $HTTP_CODE"
echo "$BODY" | jq '.'

if [[ "$HTTP_CODE" == "403" ]]; then
  echo "✓ Correctly rejected enduser attempting to reserve"
else
  echo "✗ FAIL: Expected 403, got $HTTP_CODE"
  exit 1
fi
echo

# Test: Try to reserve without token (should fail with 401)
echo "7. Testing reserve without token (should fail with 401)..."
NO_AUTH_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/$ORDER2_ID/reserve")

HTTP_CODE=$(echo "$NO_AUTH_RESP" | tail -n 1)

echo "HTTP Code: $HTTP_CODE"

if [[ "$HTTP_CODE" == "401" ]]; then
  echo "✓ Correctly rejected unauthenticated request"
else
  echo "✗ FAIL: Expected 401, got $HTTP_CODE"
  exit 1
fi
echo

# Test: Try to reserve non-existent order (should fail with 404)
echo "8. Testing reserve non-existent order (should fail with 404)..."
NOT_FOUND_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders/99999/reserve" \
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
echo "9. Verifying drone status was updated..."
DRONE_STATUS=$(docker-compose exec -T db mysql -u root -pexample drone -sN \
  -e "SELECT status, current_order_id FROM drone_status WHERE drone_id = 4")

DRONE_ST=$(echo "$DRONE_STATUS" | awk '{print $1}')
CURRENT_ORDER=$(echo "$DRONE_STATUS" | awk '{print $2}')

echo "Drone status: $DRONE_ST"
echo "Current order: $CURRENT_ORDER"

if [[ "$DRONE_ST" == "reserved" ]] && [[ "$CURRENT_ORDER" == "$ORDER_ID" ]]; then
  echo "✓ Drone status correctly updated"
else
  echo "✗ FAIL: Expected drone status='reserved' and current_order_id=$ORDER_ID"
  exit 1
fi
echo

echo "========================================="
echo "✅ All tests passed!"
echo "========================================="
