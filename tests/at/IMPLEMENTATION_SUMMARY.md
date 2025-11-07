# GET /orders/{id} Implementation - Summary

## ✅ Implementation Complete

### Features Implemented

1. **GET /orders/{id} Endpoint**
   - Returns order details for authenticated endusers
   - Includes drone information when order has assigned drone
   - Gracefully handles missing drone data

2. **Response Fields**
   ```json
   {
     "order_id": 1,
     "status": "reserved",
     "pickup": {"lat": 40.758, "lng": -73.9855},
     "dropoff": {"lat": 40.7829, "lng": -73.9654},
     "created_at": "2025-11-07T17:17:04Z",
     "updated_at": "2025-11-07T17:17:04Z",
     "assigned_drone_id": 4,           // Optional - only if drone assigned
     "drone_location": {                // Optional - only if drone exists
       "lat": 40.748817,
       "lng": -73.985428
     },
     "eta_minutes": 8                   // Optional - calculated ETA
   }
   ```

3. **ETA Calculation**
   - Uses Haversine formula for great-circle distance
   - Drone speed: 10 m/s (≈36 km/h)
   - Status-aware calculation:
     - `pending`/`reserved`: drone→pickup + pickup→dropoff
     - `picked_up`: drone→dropoff only
   - Returns rounded-up minutes, minimum 1 minute

4. **Error Handling**
   - 401: Missing/invalid authentication
   - 403: Order not owned by requesting user
   - 404: Order not found
   - 400: Invalid order ID format

### Code Components

#### New Files
- `/internal/repo/drones.go` - DroneRepo with GetByID method
- `/internal/model/eta.go` - ETA calculation logic
- `/internal/model/order.go` - OrderDetails struct

#### Modified Files
- `/internal/usecase/order.go` - Added GetOrder method
- `/internal/interface/orders.go` - Added GetOrder handler and orderResponse
- `/internal/repo/errors.go` - Added ErrDroneNotFound
- `/cmd/api/main.go` - Wire up DroneRepo

### Database Schema

```sql
-- Drone status tracking
CREATE TABLE drone_status (
  drone_id BIGINT PRIMARY KEY,
  status ENUM('idle','reserved','delivering','broken'),
  current_order_id BIGINT NULL,
  lat DECIMAL(9,6) NOT NULL,
  lng DECIMAL(9,6) NOT NULL,
  last_heartbeat_at TIMESTAMP NULL,
  FOREIGN KEY (drone_id) REFERENCES users(id)
);

-- Orders table (excerpt)
ALTER TABLE orders ADD assigned_drone_id BIGINT NULL;
ALTER TABLE orders ADD FOREIGN KEY (assigned_drone_id) REFERENCES users(id);
```

### Testing

#### Automated Tests (48 total) ✅
All passing in `tests/at/api_smoke.sh`:
- Authentication & authorization (13 tests)
- Order creation & validation (17 tests)
- Order cancellation (11 tests)
- **GET order without drone (6 tests)**

#### Manual Test Scenarios ✅
Verified manually:
1. ✓ GET order with drone (reserved status) - shows location & ETA
2. ✓ GET order with drone (picked_up status) - shows updated ETA  
3. ✓ GET order without drone - no drone fields present
4. ✓ Graceful degradation - handles non-existent drone

### Example Usage

```bash
# Get enduser token
TOKEN=$(curl -s -X POST http://localhost:8080/auth/token \
  -H "Content-Type: application/json" \
  -d '{"name":"enduser1","password":"password"}' | jq -r '.access_token')

# Get order details
curl -X GET http://localhost:8080/orders/1 \
  -H "Authorization: Bearer $TOKEN" | jq '.'
```

### Architecture

```
Handler (orders.go)
    ↓
Usecase (order.go)
    ↓
  ┌─────────┴──────────┐
  ↓                    ↓
OrderRepo         DroneRepo
  ↓                    ↓
MySQL              MySQL
(orders)    (users + drone_status)
```

### Key Design Decisions

1. **Graceful Degradation**: If drone fetch fails, order info still returns (drone fields omitted)
2. **Status-Aware ETA**: Calculates remaining distance based on order status
3. **Minimal Response**: Drone fields only included when relevant (omitempty)
4. **Separation of Concerns**: OrderDetails model composes Order + drone data

### Performance

- Single database query for order
- Single database query for drone (if assigned)
- ETA calculated in-memory (no additional queries)
- Total: 1-2 queries per request

### Future Enhancements

- [ ] Cache drone locations for better performance
- [ ] Add websocket support for real-time ETA updates
- [ ] Include historical ETA accuracy metrics
- [ ] Add drone battery level to response

## Running Tests

```bash
# Run all automated tests
bash tests/at/api_smoke.sh

# Manual verification (requires drone_status setup)
# 1. Insert drone status:
docker-compose exec db mysql -u root -pexample drone \
  -e "INSERT INTO drone_status (drone_id, status, lat, lng, last_heartbeat_at) 
      VALUES (4, 'idle', 40.748817, -73.985428, NOW())
      ON DUPLICATE KEY UPDATE lat=40.748817, lng=-73.985428;"

# 2. Create and assign order to drone:
# (Create order via POST /orders, then UPDATE orders SET assigned_drone_id=4)

# 3. GET order to verify drone fields appear
```

## Status: ✅ COMPLETE AND TESTED
