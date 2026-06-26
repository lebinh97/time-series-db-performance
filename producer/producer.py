import json, os, random, signal, time
from datetime import datetime, timezone
from pathlib import Path
import psycopg2, psycopg2.extras

ROOT = Path(__file__).resolve().parent.parent
CFG  = json.loads((ROOT / "producer/config.json").read_text())
ENV  = os.environ

def make_conn(host_key, port_key):
    return psycopg2.connect(
        host=ENV[host_key], port=ENV[port_key],
        user=ENV["POSTGRES_USER"], password=ENV["POSTGRES_PASSWORD"],
        dbname=ENV["POSTGRES_DB"]
    )

devices, screens, activities = CFG["devices"], CFG["screens"], CFG["activities"]
uid_pool = CFG["uid_pool_size"]

SQL = "INSERT INTO events (time, uid, activity, device, screen) VALUES %s"

def generate(n):
    now = datetime.now(timezone.utc).isoformat()
    return [(now, f"user_{random.randint(1, uid_pool):04d}",
             random.choice(activities), random.choice(devices),
             random.choice(screens)) for _ in range(n)]

def insert(conn, rows, label, totals):
    t = time.perf_counter()
    with conn.cursor() as cur:
        psycopg2.extras.execute_values(cur, SQL, rows)
    conn.commit()
    totals[label] += len(rows)
    print(f"[{datetime.now():%H:%M:%S}] {label:12s} | +{len(rows):,} "
          f"| {totals[label]:>10,} total | {time.perf_counter()-t:.3f}s")

def main():
    batch, interval = CFG["rows_per_batch"], CFG["batch_interval_seconds"]
    conns  = {"PostgreSQL": make_conn("PG_HOST", "PG_PORT_DOCKER"),
              "TimescaleDB": make_conn("TIMESCALE_HOST", "TIMESCALE_PORT_DOCKER")}
    totals = dict.fromkeys(conns, 0)

    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    print(f"Producer: {batch} rows/{interval}s | pool={uid_pool} devices={len(devices)}")

    while running:
        rows = generate(batch)
        for label, conn in conns.items():
            insert(conn, rows, label, totals)
        time.sleep(interval)

    for conn in conns.values():
        conn.close()
    print("Stopped.", " | ".join(f"{k}: {v:,}" for k, v in totals.items()))

if __name__ == "__main__":
    main()