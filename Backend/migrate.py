"""
Idempotent schema migration for an existing SafeSense database.

Safe to run multiple times — every change is checked against
information_schema before it's applied. Also seeds the first admin from
ADMIN_EMAIL / ADMIN_PASSWORD in .env if set (or pass --admin-email /
--admin-password).

Run from Backend/:
    python migrate.py
    python migrate.py --admin-email admin@ss.in --admin-password admin012
"""

import argparse
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / '.env')

import bcrypt
import mysql.connector  # noqa: E402  (needs env loaded first)


def connect():
    return mysql.connector.connect(
        host=os.getenv('DB_HOST', 'localhost'),
        user=os.getenv('DB_USER', 'root'),
        password=os.getenv('DB_PASSWORD', ''),
        database=os.getenv('DB_NAME', 'safesense'),
        autocommit=True,
    )


def column_exists(cur, table, column):
    cur.execute(
        """SELECT COUNT(*) AS c FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s AND COLUMN_NAME = %s""",
        (table, column))
    return cur.fetchone()['c'] > 0


def table_exists(cur, table):
    cur.execute(
        """SELECT COUNT(*) AS c FROM information_schema.TABLES
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s""",
        (table,))
    return cur.fetchone()['c'] > 0


def ensure_column(cur, table, column, ddl):
    """Add a column if missing. ddl is the full definition, e.g.
    "VARCHAR(500)" or "TEXT AFTER image_url"."""
    if column_exists(cur, table, column):
        print(f"  = {table}.{column} already exists")
        return
    try:
        cur.execute(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}")
        print(f"  + {table}.{column} added ({ddl})")
    except mysql.connector.Error as e:
        print(f"  ! {table}.{column}: {e.msg} — skipping")


def seed_admin(cur, email, password):
    cur.execute("SELECT user_id, role FROM user WHERE email = %s", (email,))
    row = cur.fetchone()
    if row:
        if row['role'] != 'admin':
            cur.execute("UPDATE user SET role = 'admin' WHERE user_id = %s",
                        (row['user_id'],))
            print(f"  + existing user {email} elevated to admin")
        else:
            print(f"  = {email} already an admin")
        return
    password_hash = bcrypt.hashpw(password.encode('utf-8'),
                                  bcrypt.gensalt()).decode('utf-8')
    cur.execute(
        """INSERT INTO user (name, email, phone, password_hash, role)
           VALUES ('Admin', %s, '', %s, 'admin')""", (email, password_hash))
    print(f"  + admin created: {email} (user_id {cur.lastrowid})")


def fk_names(cur, table, referenced=None, on_table=None):
    """Foreign keys on `table` (or on other tables referencing `table`)."""
    if referenced:
        cur.execute(
            """SELECT CONSTRAINT_NAME, TABLE_NAME FROM information_schema.KEY_COLUMN_USAGE
               WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME = %s""",
            (referenced,))
    else:
        cur.execute(
            """SELECT CONSTRAINT_NAME, TABLE_NAME FROM information_schema.TABLE_CONSTRAINTS
               WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s
                 AND CONSTRAINT_TYPE = 'FOREIGN KEY'""",
            (table,))
    return [(r['CONSTRAINT_NAME'], r['TABLE_NAME']) for r in cur.fetchall()]


def make_zone_id_auto_increment(cur):
    """zone_risk.zone_id must be AUTO_INCREMENT so admins can create zones
    from the app. MySQL refuses to modify it while FKs reference it, so the
    FKs are dropped and restored around the change."""
    cur.execute("SHOW COLUMNS FROM zone_risk LIKE 'zone_id'")
    if 'auto_increment' in (cur.fetchone() or {}).get('Extra', ''):
        print("  = zone_id already auto_increment")
        return

    referencing = fk_names(cur, referenced='zone_risk')      # e.g. evacuation_route
    outbound = fk_names(cur, table='zone_risk')              # e.g. zone_risk -> evacuation_route

    dropped = []
    for name, tbl in referencing + outbound:
        try:
            cur.execute(f"ALTER TABLE {tbl} DROP FOREIGN KEY {name}")
            dropped.append((name, tbl))
        except mysql.connector.Error as e:
            print(f"  ! could not drop {tbl}.{name}: {e.msg}")

    try:
        cur.execute("ALTER TABLE zone_risk MODIFY zone_id INT AUTO_INCREMENT")
        print("  + zone_id is now AUTO_INCREMENT")
    except mysql.connector.Error as e:
        print(f"  ! zone_id: {e.msg}")

    for name, tbl in dropped:
        try:
            if name == 'evacuation_route_ibfk_1':
                cur.execute(
                    f"""ALTER TABLE {tbl} ADD CONSTRAINT {name}
                        FOREIGN KEY (zone_id) REFERENCES zone_risk(zone_id)""")
            elif name == 'zone_risk_ibfk_1':
                cur.execute(
                    f"""ALTER TABLE {tbl} ADD CONSTRAINT {name}
                        FOREIGN KEY (zone_id) REFERENCES evacuation_route(zone_id)""")
        except mysql.connector.Error as e:
            print(f"  ! could not restore {tbl}.{name}: {e.msg} (add it back manually)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--admin-email', default=os.getenv('ADMIN_EMAIL', ''))
    parser.add_argument('--admin-password', default=os.getenv('ADMIN_PASSWORD', ''))
    parser.add_argument('--reset-admin-password', action='store_true',
                        help='re-hash and overwrite the admin password even '
                             'if the account already exists')
    args = parser.parse_args()

    conn = connect()
    cur = conn.cursor(dictionary=True)

    print("\n== Schema migration ==")

    print("\n[core tables]")
    for ddl in (
        """CREATE TABLE IF NOT EXISTS emergency_contact (
               contact_id INT AUTO_INCREMENT PRIMARY KEY,
               user_id INT NOT NULL,
               name VARCHAR(100) NOT NULL,
               phone VARCHAR(30) NOT NULL,
               relationship VARCHAR(100) DEFAULT '',
               created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
               FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
           )""",
        """CREATE TABLE IF NOT EXISTS location_share (
               share_id INT AUTO_INCREMENT PRIMARY KEY,
               user_id INT NOT NULL,
               latitude FLOAT,
               longitude FLOAT,
               started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
               last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
               expires_at DATETIME NOT NULL,
               active TINYINT(1) DEFAULT 1,
               FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
           )""",
        """CREATE TABLE IF NOT EXISTS emergency_alert (
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
           )""",
    ):
        name = ddl.split('EXISTS')[1].split('(')[0].strip()
        cur.execute(ddl)
        print(f"  = {name} ready")

    print("\n[uploaded_image]")
    ensure_column(cur, 'uploaded_image', 'description', 'TEXT')
    if not column_exists(cur, 'uploaded_image', 'image_url'):
        ensure_column(cur, 'uploaded_image', 'image_url', 'VARCHAR(500)')
    else:
        cur.execute(
            """SELECT CHARACTER_MAXIMUM_LENGTH AS n FROM information_schema.COLUMNS
               WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME='uploaded_image'
                 AND COLUMN_NAME='image_url'""")
        n = cur.fetchone()['n']
        if n and n < 500:
            cur.execute("ALTER TABLE uploaded_image MODIFY image_url VARCHAR(500)")
            print("  + image_url widened to VARCHAR(500)")
        else:
            print("  = image_url length ok")

    print("\n[zone_risk]")
    ensure_column(cur, 'zone_risk', 'disaster_type', 'VARCHAR(50)')
    make_zone_id_auto_increment(cur)

    print("\n[verifying]")
    for t in ('user', 'uploaded_image', 'emergency_contact', 'location_share',
              'emergency_alert', 'zone_risk', 'shelter', 'disaster',
              'detection_result'):
        ok = table_exists(cur, t)
        print(f"  {'OK ' if ok else 'MISSING'} {t}")

    if args.admin_email and args.admin_password:
        print("\n[admin]")
        seed_admin(cur, args.admin_email, args.admin_password)

    cur.close()
    conn.close()
    print("\nDone.")
    if not (args.admin_email and args.admin_password):
        print("No admin seeded — pass --admin-email/--admin-password or set "
              "ADMIN_EMAIL/ADMIN_PASSWORD in .env if you need one.")


if __name__ == '__main__':
    sys.exit(main())
