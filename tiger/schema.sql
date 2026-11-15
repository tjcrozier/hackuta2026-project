
DROP TABLE IF EXISTS worker_pings;
DROP TABLE IF EXISTS worker_motion;

CREATE TABLE worker_pings (
    time            TIMESTAMPTZ NOT NULL,
    worker_id       TEXT NOT NULL,
    site_id         TEXT NOT NULL,
    lat             DOUBLE PRECISION,
    lon             DOUBLE PRECISION,
    x_m             REAL,
    y_m             REAL,
    z_m             REAL,
    floor           SMALLINT,
    accuracy_m      REAL,
    battery_pct     REAL,
    nearest_peer    TEXT,
    ble_rssi_dbm    REAL,
    peer_distance_m REAL
);

CREATE TABLE worker_motion (
    time          TIMESTAMPTZ NOT NULL,
    worker_id     TEXT NOT NULL,
    site_id       TEXT NOT NULL,
    accel_x       REAL,
    accel_y       REAL,
    accel_z       REAL,
    gyro_x        REAL,
    gyro_y        REAL,
    gyro_z        REAL,
    speed_mps     REAL,
    heading_deg   REAL,
    step_count    INTEGER,
    activity      TEXT,
    fall_detected BOOLEAN
);
