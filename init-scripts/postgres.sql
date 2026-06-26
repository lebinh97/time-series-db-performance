CREATE TABLE IF NOT EXISTS events (
    time     TIMESTAMPTZ NOT NULL DEFAULT now(),
    uid      TEXT        NOT NULL,
    activity TEXT        NOT NULL,
    device   TEXT        NOT NULL,
    screen   TEXT        NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_time   ON events (time DESC);
CREATE INDEX IF NOT EXISTS idx_events_uid    ON events (uid, time DESC);
CREATE INDEX IF NOT EXISTS idx_events_act    ON events (activity, time DESC);
CREATE INDEX IF NOT EXISTS idx_events_device ON events (device, time DESC);
