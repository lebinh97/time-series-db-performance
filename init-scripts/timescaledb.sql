-- 1. Extension first
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- 2. Base table
CREATE TABLE IF NOT EXISTS events (
    time     TIMESTAMPTZ NOT NULL DEFAULT now(),
    uid      TEXT        NOT NULL,
    activity TEXT        NOT NULL,
    device   TEXT        NOT NULL,
    screen   TEXT        NOT NULL
);

-- 3. Hypertable (creates time index automatically)
SELECT create_hypertable('events', 'time',
    chunk_time_interval => INTERVAL '1 minute',
    partitioning_column => 'device',
    number_partitions   => 4
);

-- 4. Additional indexes only (skip the time-only index, it already exists)
CREATE INDEX IF NOT EXISTS idx_events_uid ON events (uid,      time DESC);
CREATE INDEX IF NOT EXISTS idx_events_act ON events (activity, time DESC);

-- 5. Compression settings
ALTER TABLE events SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device',
    timescaledb.compress_orderby   = 'time DESC'
);

-- 6. Compression policy last (hypertable must exist and be configured first)
SELECT add_compression_policy('events', INTERVAL '1 minute');