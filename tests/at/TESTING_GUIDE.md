# Testing Guide - Drone Delivery Management API

## Overview

This document describes the testing strategy and test suites for the Drone Delivery Management API, specifically for the `GET /orders/{id}` endpoint implementation.

## Test Structure

### 1. Automated Acceptance Tests (`tests/at/api_smoke.sh`)

**48 automated test cases** covering:

#### Health Check (1 test)
- Service availability verification

#### Authentication (8 tests)
- Successful token generation (admin, enduser)
- Invalid credentials (wrong password, unknown user)
- Malformed requests (empty body, invalid JSON, missing fields)

#### Authorization (3 tests)
- Order creation requires enduser role
- Order cancellation requires enduser role
- Proper authentication token validation

#### Order Creation (17 tests)
- **Valid requests (5 tests):**
  - Standard decimal coordinates
  - Boundary values (±90 lat, ±180 lng)
  - Zero coordinates (equator/prime meridian)

- **Validation errors (12 tests):**
  - Missing required fields (pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)
  - Invalid formats (empty body, malformed JSON)
  - Out-of-range coordinates

#### Order Cancellation (11 tests)
- **Auth/Authz (3 tests):** Requires valid token and enduser role
- **Valid requests (2 tests):** Cancel pending order, prevent duplicate cancellation (409)
- **Ownership (2 tests):** Users can only cancel their own orders
- **Not found (4 tests):** Invalid IDs return 400, non-existent orders return 404

#### GET Order Details (8 tests)
- **Auth/Authz (2 tests):** Invalid token (401), not owned (403)
- **Validation (4 tests):** Invalid ID formats (400), non-existent order (404)
- **Success (2 tests):** Pending order, canceled order (with canceled_at)

### 2. Manual Drone Tests (`tests/at/manual_drone_tests.sh`)

**4 manual test scenarios** for drone-related functionality:

#### Test 1: Order with Drone (Reserved Status)
```bash
# Setup: Assign drone to order with 'reserved' status
# Verifies:
- assigned_drone_id field present
- drone_location with current coordinates
- eta_minutes calculated (drone → pickup → dropoff)
```

#### Test 2: Order with Drone (Picked Up Status)
```bash
# Setup: Update order to 'picked_up' status
# Verifies:
- ETA recalculated (drone → dropoff only)
- ETA is lower than reserved status
- Status-aware distance calculation
```

#### Test 3: Order Without Drone
```bash
# Setup: Create order, don't assign drone
# Verifies:
- No assigned_drone_id field
- No drone_location field
- No eta_minutes field
```

#### Test 4: Graceful Degradation
```bash
# Setup: Assign non-existent drone (ID 999)
# Verifies:
- assigned_drone_id present (999)
- No drone_location (drone not found)
- No eta_minutes (cannot calculate)
- Order details still returned successfully
```

## Running Tests

### Quick Test (All Automated)
```bash
cd /Users/asddsa/go/github/enas/drone-delivery-management
bash tests/at/api_smoke.sh
```

**Expected output:**
```
=========================================
All acceptance tests passed! ✓
=========================================
Total: 48 test cases
```

### Manual Drone Assignment Tests
```bash
cd /Users/asddsa/go/github/enas/drone-delivery-management
bash tests/at/manual_drone_tests.sh
```

**Expected output:**
```
========================================
All manual drone tests passed! ✓
========================================
  ✓ GET order with drone (reserved) - shows drone location & ETA
  ✓ GET order with drone (picked_up) - shows updated ETA
  ✓ GET order without drone - no drone fields
  ✓ Graceful degradation - handles missing drone gracefully
```

### Custom Manual Testing

#### 1. Setup Drone Location
```bash
docker-compose exec db mysql -u root -pexample drone -e \
  "INSERT INTO drone_status (drone_id, status, lat, lng, last_heartbeat_at) 
   VALUES (4, 'idle', 40.748817, -73.985428, NOW())
   ON DUPLICATE KEY UPDATE lat=40.748817, lng=-73.985428;"
```

#### 2. Get Authentication Token
```bash
TOKEN=$(curl -s -X POST http://localhost:8080/auth/token \
  -H "Content-Type: application/json" \
  -d '{"name":"enduser1","password":"password"}' | jq -r '.access_token')
```

#### 3. Create Order
```bash
ORDER_ID=$(curl -s -X POST http://localhost:8080/orders \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pickup_lat": 40.758,
    "pickup_lng": -73.9855,
    "dropoff_lat": 40.7829,
    "dropoff_lng": -73.9654
  }' | jq -r '.order_id')

echo "Created order: $ORDER_ID"
```

#### 4. Assign Drone to Order
```bash
docker-compose exec db mysql -u root -pexample drone -e \
  "UPDATE orders SET assigned_drone_id = 4, status = 'reserved' WHERE id = $ORDER_ID;"
```

#### 5. Get Order Details (With Drone)
```bash
curl -s -X GET "http://localhost:8080/orders/$ORDER_ID" \
  -H "Authorization: Bearer $TOKEN" | jq '.'
```

**Expected response:**
```json
{
  "order_id": 1,
  "status": "reserved",
  "pickup": {"lat": 40.758, "lng": -73.9855},
  "dropoff": {"lat": 40.7829, "lng": -73.9654},
  "created_at": "2025-11-07T17:17:04Z",
  "updated_at": "2025-11-07T17:17:04Z",
  "assigned_drone_id": 4,
  "drone_location": {
    "lat": 40.748817,
    "lng": -73.985428
  },
  "eta_minutes": 8
}
```

## Test Coverage Matrix

| Feature | Automated | Manual | Total |
|---------|-----------|--------|-------|
| Health check | 1 | 0 | 1 |
| Authentication | 8 | 0 | 8 |
| Authorization | 3 | 0 | 3 |
| Order creation | 17 | 0 | 17 |
| Order cancellation | 11 | 0 | 11 |
| GET order (no drone) | 8 | 1 | 9 |
| GET order (with drone) | 0 | 3 | 3 |
| **Total** | **48** | **4** | **52** |

## Known Limitations

### Automated Test Gaps
The following scenarios require manual testing due to lack of automatic drone assignment:

1. **409 Conflict on Order Creation** (TODO)
   - All drones busy/unavailable
   - User has pending unassigned order
   - *Implementation not yet added to business logic*

2. **Drone Assignment Scenarios**
   - Cannot automatically test drone assignment without scheduler
   - Requires direct database manipulation
   - *Future: Add drone assignment service for automated testing*

### Gin Framework Behavior
- `GET /orders/:id` without auth returns **404** instead of **401**
- This is expected Gin behavior: route group middleware runs after route matching
- Unauthenticated requests hit non-existent route at root level

## ETA Calculation Testing

### Formula
- Distance: Haversine formula (great-circle distance)
- Speed: 10 m/s (≈36 km/h)
- Result: Rounded up to nearest minute, minimum 1 minute

### Test Scenarios

#### Reserved/Pending Order
```
ETA = distance(drone → pickup) + distance(pickup → dropoff)
```
Example: Drone at Empire State Building → Times Square → Central Park = 8 minutes

#### Picked Up Order
```
ETA = distance(drone → dropoff)
```
Example: Drone at Empire State Building → Central Park = 7 minutes

### Verification Steps
1. Create order with known coordinates
2. Assign drone with known location
3. Verify ETA matches expected calculation
4. Update order status to 'picked_up'
5. Verify ETA decreased (removed pickup leg)

## Troubleshooting

### Tests Fail After Container Restart
**Problem:** `drone_status` table data is lost after restart (not persisted)

**Solution:**
```bash
docker-compose exec db mysql -u root -pexample drone -e \
  "INSERT INTO drone_status (drone_id, status, lat, lng, last_heartbeat_at) 
   VALUES (4, 'idle', 40.748817, -73.985428, NOW())
   ON DUPLICATE KEY UPDATE lat=40.748817, lng=-73.985428;"
```

### Order Not Found (404)
**Problem:** Orders are also lost after restart

**Solution:** Create a new order using POST /orders endpoint

### Token Expired
**Problem:** JWT tokens expire after configured time

**Solution:** Generate a new token using POST /auth/token

## Future Enhancements

### Test Improvements
- [ ] Add automated drone assignment service
- [ ] Implement 409 conflict scenarios
- [ ] Add load testing for concurrent order creation
- [ ] Add integration tests with drone simulator
- [ ] Add E2E tests with full order lifecycle

### Monitoring
- [ ] Add test result reporting (JUnit XML)
- [ ] Add performance metrics (response times)
- [ ] Add coverage reporting
- [ ] Add CI/CD integration

## Success Criteria

✅ **All 48 automated tests pass**
✅ **All 4 manual drone tests pass**
✅ **GET /orders/{id} returns correct data with/without drone**
✅ **ETA calculation is accurate and status-aware**
✅ **Graceful degradation when drone not found**
✅ **Proper authentication and authorization**

---

**Last Updated:** November 7, 2025
**Test Suite Version:** 1.0
**API Version:** 1.0
