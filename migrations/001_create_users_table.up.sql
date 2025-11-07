-- Drone Delivery Management initial schema

-- Users (humans and drones)
CREATE TABLE IF NOT EXISTS users (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(50) NOT NULL,
  password_hash VARCHAR(60) NOT NULL,
  type ENUM('admin','enduser','drone') NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_users_name (name),
  KEY idx_users_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed demo users (bcrypt; plaintext shown inline)
INSERT IGNORE INTO users (name, password_hash, type) VALUES
  ('admin', '$2a$10$pwF9DODNqZ.QVgGaMwU3keqWVIvlT02TNWjoUwt21xaJwyyVy66jy', 'admin'),   -- password: password
  ('enduser1', '$2a$10$pwF9DODNqZ.QVgGaMwU3keqWVIvlT02TNWjoUwt21xaJwyyVy66jy', 'enduser'), -- password: password
  ('enduser2', '$2a$10$pwF9DODNqZ.QVgGaMwU3keqWVIvlT02TNWjoUwt21xaJwyyVy66jy', 'enduser'), -- password: password
  ('drone1', '$2a$10$pwF9DODNqZ.QVgGaMwU3keqWVIvlT02TNWjoUwt21xaJwyyVy66jy', 'drone'),    -- password: password
  ('drone2', '$2a$10$pwF9DODNqZ.QVgGaMwU3keqWVIvlT02TNWjoUwt21xaJwyyVy66jy', 'drone');    -- password: password
