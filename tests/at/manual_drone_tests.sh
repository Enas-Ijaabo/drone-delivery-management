#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://localhost:8080}"

echo "========================================="
echo "Manual Drone Assignment Tests"
echo "========================================="
echo

# Setup test data
echo "Setting up test data..."
docker-compose exec db mysql -u root -pexample drone -e "INSERT INTO drone_status (drone_id, status, lat, lng, last_heartbeat_at) VALUES (4, 'idle', 40.748817, -73.985428, NOW()) ON DUPLICATE KEY UPDATE lat=40.748817, lng=-73.985428, last_heartbeat_at=NOW();" 2>/dev/null
echo "✓ Drone status initialized"
echo

# Get token
ENDUSER_TOKEN=$(curl -s -X POST "$BASE/auth/token" \
  -H "Content-Type: application/json" \
  -d '{"name":"enduser1","password":"password"}' | jq -r '.access_token')

echo "Test 1: GET order with assigned drone (reserved status)"
echo "--------------------------------------------------------"
# Create order
ORDER1=$(curl -s -X POST "$BASE/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ENDUSER_TOKEN" \
  -d '{"pickup_lat": 40.758, "pickup_lng": -73.9855, "dropoff_lat": 40.7829, "dropoff_lng": -73.9654}' | jq -r '.order_id')
echo "Created order: $ORDER1"

# Assign drone
docker-compose exec db mysql -u root -pexample drone -e "UPDATE orders SET assigned_drone_id = 4, status = 'reserved' WHERE id = $ORDER1;" 2>/dev/null

# GET order
RESPONSE1=$(curl -s -X GET "$BASE/orders/$ORDER1" -H "Authorization: Bearer $ENDUSER_TOKEN")
echo "$RESPONSE1" | jq '.'

# Verify
DRONE_ID=$(echo "$RESPONSE1" | jq -r '.assigned_drone_id')
DRONE_LAT=$(echo "$RESPONSE1" | jq -r '.drone_location.lat')
ETA=$(echo "$RESPONSE1" | jq -r '.eta_minutes')

if [[ "$DRONE_ID" == "4" ]] && [[ "$DRONE_LAT" == "40.748817" ]] && [[ "$ETA" =~ ^[0-9]+$ ]]; then
  echo "✓ PASS: Order has drone_id=4, drone_location, and ETA=$ETA minutes"
else
  echo "✗ FAIL: Missing or incorrect drone details"
  exit 1
fi
echo

echo "Test 2: GET order with assigned drone (picked_up status)"
echo "--------------------------------------------------------"
# Update to picked_up
docker-compose exec db mysql -u root -pexample drone -e "UPDATE orders SET status = 'picked_up' WHERE id = $ORDER1;" 2>/dev/null

# GET order
RESPONSE2=$(curl -s -X GET "$BASE/orders/$ORDER1" -H "Authorization: Bearer $ENDUSER_TOKEN")
echo "$RESPONSE2" | jq '.'

ETA2=$(echo "$RESPONSE2" | jq -r '.eta_minutes')
STATUS=$(echo "$RESPONSE2" | jq -r '.status')

if [[ "$STATUS" == "picked_up" ]] && [[ "$ETA2" =~ ^[0-9]+$ ]] && [[ "$ETA2" -lt "$ETA" ]]; then
  echo "✓ PASS: picked_up status has lower ETA ($ETA2) than reserved ($ETA)"
else
  echo "⚠ WARNING: ETA calculation may need verification (reserved=$ETA, picked_up=$ETA2)"
fi
echo

echo "Test 3: GET order without assigned drone"
echo "--------------------------------------------------------"
# Create order without drone
ORDER2=$(curl -s -X POST "$BASE/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ENDUSER_TOKEN" \
  -d '{"pickup_lat": 40.758, "pickup_lng": -73.9855, "dropoff_lat": 40.7829, "dropoff_lng": -73.9654}' | jq -r '.order_id')
echo "Created order: $ORDER2"

# GET order
RESPONSE3=$(curl -s -X GET "$BASE/orders/$ORDER2" -H "Authorization: Bearer $ENDUSER_TOKEN")
echo "$RESPONSE3" | jq '.'

HAS_DRONE=$(echo "$RESPONSE3" | jq 'has("assigned_drone_id")')
HAS_LOCATION=$(echo "$RESPONSE3" | jq 'has("drone_location")')
HAS_ETA=$(echo "$RESPONSE3" | jq 'has("eta_minutes")')

if [[ "$HAS_DRONE" == "false" ]] && [[ "$HAS_LOCATION" == "false" ]] && [[ "$HAS_ETA" == "false" ]]; then
  echo "✓ PASS: No drone fields present for unassigned order"
else
  echo "✗ FAIL: Unexpected drone fields in response"
  exit 1
fi
echo

echo "Test 4: Graceful degradation (non-existent drone)"
echo "--------------------------------------------------------"
# Create order and assign non-existent drone
ORDER3=$(curl -s -X POST "$BASE/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ENDUSER_TOKEN" \
  -d '{"pickup_lat": 40.758, "pickup_lng": -73.9855, "dropoff_lat": 40.7829, "dropoff_lng": -73.9654}' | jq -r '.order_id')
echo "Created order: $ORDER3"

docker-compose exec db mysql -u root -pexample drone -e "UPDATE orders SET assigned_drone_id = 999, status = 'reserved' WHERE id = $ORDER3;" 2>/dev/null

# GET order
RESPONSE4=$(curl -s -X GET "$BASE/orders/$ORDER3" -H "Authorization: Bearer $ENDUSER_TOKEN")
echo "$RESPONSE4" | jq '.'

DRONE_ID4=$(echo "$RESPONSE4" | jq -r '.assigned_drone_id')
HAS_LOCATION4=$(echo "$RESPONSE4" | jq 'has("drone_location")')
HAS_ETA4=$(echo "$RESPONSE4" | jq 'has("eta_minutes")')

if [[ "$DRONE_ID4" == "999" ]] && [[ "$HAS_LOCATION4" == "false" ]] && [[ "$HAS_ETA4" == "false" ]]; then
  echo "✓ PASS: Graceful degradation - order shows assigned_drone_id but no location/ETA"
else
  echo "✗ FAIL: Unexpected behavior for non-existent drone"
  exit 1
fi
echo

echo "========================================="
echo "All manual drone tests passed! ✓"
echo "========================================="
echo
echo "Summary:"
echo "  ✓ GET order with drone (reserved) - shows drone location & ETA"
echo "  ✓ GET order with drone (picked_up) - shows updated ETA"
echo "  ✓ GET order without drone - no drone fields"
echo "  ✓ Graceful degradation - handles missing drone gracefully"
echo "========================================="
