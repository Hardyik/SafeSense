-- SafeSense Database Schema
-- Run this to create all tables from scratch

CREATE DATABASE IF NOT EXISTS safesense;
USE safesense;

-- ============================================================
-- USER
-- ============================================================
CREATE TABLE IF NOT EXISTS user (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(20),
    password_hash VARCHAR(255) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    role VARCHAR(20) DEFAULT 'user'
);

-- ============================================================
-- SHELTER
-- ============================================================
CREATE TABLE IF NOT EXISTS shelter (
    shelter_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    latitude FLOAT,
    longitude FLOAT,
    capacity INT,
    occupancy INT DEFAULT 0,
    contact VARCHAR(50),
    status VARCHAR(20) DEFAULT 'available',
    type VARCHAR(30)
);

-- ============================================================
-- DISASTER
-- ============================================================
CREATE TABLE IF NOT EXISTS disaster (
    disaster_id INT AUTO_INCREMENT PRIMARY KEY,
    type VARCHAR(50),
    severity VARCHAR(20),
    description TEXT,
    start_time DATETIME,
    status VARCHAR(20) DEFAULT 'active'
);

-- ============================================================
-- UPLOADED IMAGE
-- ============================================================
CREATE TABLE IF NOT EXISTS uploaded_image (
    image_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    disaster_id INT,
    image_url VARCHAR(255),
    latitude FLOAT,
    longitude FLOAT,
    uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending',
    FOREIGN KEY (user_id) REFERENCES user(user_id),
    FOREIGN KEY (disaster_id) REFERENCES disaster(disaster_id)
);

-- ============================================================
-- DETECTION RESULT
-- ============================================================
CREATE TABLE IF NOT EXISTS detection_result (
    detection_id INT AUTO_INCREMENT PRIMARY KEY,
    image_id INT,
    damage_type VARCHAR(50),
    severity VARCHAR(20),
    confidence FLOAT,
    road_status VARCHAR(30),
    detected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (image_id) REFERENCES uploaded_image(image_id)
);

-- ============================================================
-- ZONE RISK
-- ============================================================
CREATE TABLE IF NOT EXISTS zone_risk (
    zone_id INT PRIMARY KEY,
    boundaries_poly TEXT,
    risk_level VARCHAR(20),
    status VARCHAR(20),
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- ZONE WEATHER
-- ============================================================
CREATE TABLE IF NOT EXISTS zone_weather (
    zone_id INT AUTO_INCREMENT PRIMARY KEY,
    disaster_id INT,
    rainfall FLOAT,
    wind_speed FLOAT,
    seismic FLOAT,
    weather_status VARCHAR(30),
    recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (disaster_id) REFERENCES disaster(disaster_id)
);

-- ============================================================
-- EVACUATION ROUTE
-- ============================================================
CREATE TABLE IF NOT EXISTS evacuation_route (
    route_id INT AUTO_INCREMENT PRIMARY KEY,
    zone_id INT,
    shelter_id INT,
    user_id INT,
    path_geometry TEXT,
    distance FLOAT,
    estimated_time INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (zone_id) REFERENCES zone_risk(zone_id),
    FOREIGN KEY (shelter_id) REFERENCES shelter(shelter_id),
    FOREIGN KEY (user_id) REFERENCES user(user_id)
);

-- ============================================================
-- RESCUE GUIDANCE
-- ============================================================
CREATE TABLE IF NOT EXISTS rescue_guidance (
    guidance_id INT AUTO_INCREMENT PRIMARY KEY,
    route_id INT,
    instruction_text TEXT,
    step_order INT,
    priority VARCHAR(20),
    FOREIGN KEY (route_id) REFERENCES evacuation_route(route_id)
);

-- ============================================================
-- SAMPLE DATA
-- ============================================================

-- Sample shelters (5 near Nashik)
INSERT INTO shelter (name, latitude, longitude, capacity, occupancy, contact, status, type) VALUES
('Nashik Municipal School Shelter', 19.9975, 73.7898, 250, 45, '0253-2571234', 'available', 'school'),
('Godavari River Relief Camp', 19.9615, 73.7480, 400, 120, '0253-2572345', 'available', 'government'),
('Panchavati Community Hall', 20.0110, 73.7730, 150, 30, '0253-2573456', 'available', 'community'),
('Indira Nagar Emergency Center', 19.9850, 73.8100, 300, 85, '0253-2574567', 'available', 'emergency'),
('Satpur Relief Warehouse', 20.0250, 73.7600, 500, 200, '0253-2575678', 'available', 'warehouse');
