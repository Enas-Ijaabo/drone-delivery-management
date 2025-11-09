-- Create drone_status table (tracks status for users with type='drone')
CREATE TABLE IF NOT EXISTS drone_status (
  drone_id BIGINT PRIMARY KEY,
  status ENUM('idle','reserved','delivering','broken') NOT NULL DEFAULT 'idle',
  current_order_id BIGINT NULL,
  lat DECIMAL(9,6) NOT NULL DEFAULT 0.0,
  lng DECIMAL(9,6) NOT NULL DEFAULT 0.0,
  location POINT NOT NULL SRID 4326,
  last_heartbeat_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_drone_status_status (status),
  KEY idx_drone_status_current_order (current_order_id),
  SPATIAL INDEX idx_drone_location (location),
  CONSTRAINT fk_drone_status_user FOREIGN KEY (drone_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed status rows for existing drones so they start as idle
INSERT IGNORE INTO drone_status (drone_id, status, current_order_id, lat, lng, location)
SELECT id, 'idle', NULL, 0.0, 0.0, ST_SRID(POINT(0.0, 0.0), 4326)
FROM users
WHERE type = 'drone';

-- Create orders table
CREATE TABLE IF NOT EXISTS orders (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  enduser_id BIGINT NOT NULL,
  pickup_lat DECIMAL(9,6) NOT NULL,
  pickup_lng DECIMAL(9,6) NOT NULL,
  dropoff_lat DECIMAL(9,6) NOT NULL,
  dropoff_lng DECIMAL(9,6) NOT NULL,
  status ENUM('pending','reserved','picked_up','handoff_pending','delivered','failed','canceled') NOT NULL DEFAULT 'pending',
  assigned_drone_id BIGINT NULL,
  handoff_lat DECIMAL(9,6) NULL COMMENT 'For handoffs from broken drones',
  handoff_lng DECIMAL(9,6) NULL COMMENT 'For handoffs from broken drones',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  canceled_at TIMESTAMP NULL,
  KEY idx_orders_status (status),
  KEY idx_orders_enduser (enduser_id),
  KEY idx_orders_assigned_drone (assigned_drone_id),
  KEY idx_orders_assignment (status, assigned_drone_id, created_at),
  CONSTRAINT fk_orders_enduser FOREIGN KEY (enduser_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_orders_assigned_drone FOREIGN KEY (assigned_drone_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
