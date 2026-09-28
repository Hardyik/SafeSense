-- ============================================================
-- MIGRATION 001 — bring an existing SafeSense database up to the
-- schema the fully-local (Flask + MySQL) app expects.
--
-- NOTE: prefer running the idempotent Python migration instead — it
-- checks information_schema before each change and also seeds the
-- first admin:
--
--     python migrate.py --admin-email you@example.com --admin-password secret
--
-- This file is the manual, plain-MySQL equivalent (MySQL 8 does not
-- support ADD COLUMN IF NOT EXISTS) — run each statement only if the
-- column/table is missing.
-- ============================================================
USE safesense;

-- uploaded_image: notes column for report descriptions
ALTER TABLE uploaded_image ADD COLUMN description TEXT AFTER image_url;
ALTER TABLE uploaded_image MODIFY image_url VARCHAR(500);

-- zone_risk: app-created zones need auto-increment IDs and a type
ALTER TABLE zone_risk MODIFY COLUMN zone_id INT AUTO_INCREMENT;
ALTER TABLE zone_risk ADD COLUMN disaster_type VARCHAR(50) AFTER risk_level;
ALTER TABLE zone_risk MODIFY COLUMN status VARCHAR(20) DEFAULT 'active';

-- ============================================================
-- EMERGENCY CONTACT (per-user quick-dial contacts — Section 9)
-- ============================================================
CREATE TABLE IF NOT EXISTS emergency_contact (
    contact_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(30) NOT NULL,
    relationship VARCHAR(100) DEFAULT '',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);

-- ============================================================
-- LOCATION SHARE (temporary location sharing — Section 10)
-- ============================================================
CREATE TABLE IF NOT EXISTS location_share (
    share_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    latitude FLOAT,
    longitude FLOAT,
    started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    active TINYINT(1) DEFAULT 1,
    FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);

-- ============================================================
-- EMERGENCY ALERT (admin broadcast alerts — Section 11)
-- ============================================================
CREATE TABLE IF NOT EXISTS emergency_alert (
    alert_id INT AUTO_INCREMENT PRIMARY KEY,
    disaster_type VARCHAR(50),
    severity VARCHAR(20),
    affected_area VARCHAR(200),
    description TEXT,
    recommended_action TEXT,
    status VARCHAR(20) DEFAULT 'active',
    created_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME,
    FOREIGN KEY (created_by) REFERENCES user(user_id)
);

-- ============================================================
-- FIRST ADMIN
-- No seed row here — app.py auto-creates the first admin at startup
-- from ADMIN_EMAIL / ADMIN_PASSWORD in .env (see SEED_ADMIN section),
-- so the password hash is always generated properly by bcrypt. Set
-- those two variables before the first run.
-- ============================================================
