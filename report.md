# TimescaleDB vs PostgreSQL — Query Performance Report

Query: count(*), max(time) for device='iPhone' over last 10 minutes. 
Underlying data write 50k rows per second in both database, so after about 20 minutes of running the docker container you would have about 60 million rows in each of these database

## Result

| Query | PostgreSQL | TimescaleDB | Speedup |
|---|---|---|---|
| 10 min + device | 2,035 ms | **44 ms** | **46.2×** |
| 5 min + device | 1,869 ms | **26 ms** | **72.2×** |
| 1 min + device | 153 ms | **14 ms** | **10.9×** |
| 10 min, all devices | 881 ms | **127 ms** | **6.9×** |
| 1 min, all devices | 132 ms | **40 ms** | **3.3×** |

Larger time windows amplify the gap — more chunks, more compression at work.

## Why TimescaleDB Is Faster

### 1. Hypertable Chunking

TimescaleDB splits the table into small 1-minute chunks partitioned by device. A query for `device='iPhone'` touches only ~1/4 of the data. Each chunk has its own small index — scanning many small indexes is faster than one giant one.

> **In the plan:** PostgreSQL shows one `Parallel Index Only Scan` on `events` (1.5M rows). TimescaleDB shows `ChunkAppend` fanning out to 11 `_hyper_*_chunk` sub-scans, each touching 55K–160K rows.

### 2. Columnar Compression

Older chunks are converted from row-based to columnar storage. Each column is stored separately and compressed with type-specific encoding: delta-of-delta for timestamps, dictionary encoding for text, then a final ZSTD pass. A query that only needs `time` and `count(*)` reads just one column — the rest are never touched. PostgreSQL's row store must read the full row for any column.

**2.1. Hybrid: columnar for old data, row-based for new.** Recent chunks stay in row format for fast inserts; older chunks convert to columnar storage. Queries read only the needed columns — `time` and `count(*)` never touch `uid` or `activity`. PostgreSQL's row store always reads the full row.

**2.2. Vectorized Filter.** Instead of checking `time > now()-10min` row-by-row, TimescaleDB uses SIMD CPU instructions to compare 8–16 values at once on decompressed column batches. The plan shows `Vectorized Filter: ("time" > ...)`. PostgreSQL does sequential row-by-row filtering.

**2.3. VectorAgg.** After filtering, `count(*)` and `max(time)` run in SIMD batches on the decompressed column. The plan shows `Custom Scan (VectorAgg)`, replacing PostgreSQL's row-by-row `HashAggregate`.

> **In the plan:** Each compressed chunk shows `VectorAgg → ColumnarScan → Index (compress_hyper_*_device__ts_meta)`. The metadata index touches 157 segment entries (not 156K data rows). The `ColumnarScan` reports `actual time=0.000..0.000` — decompress-and-filter is so fast it rounds to zero. The 2 live chunks below prove the contrast: same chunk structure, but without compression they take 3–6ms each.

## Plan Comparison

**PostgreSQL** — 1 index, no chunks, no compression — flat plan

```
Finalize Aggregate
  → Gather  (Workers: 2, launched: 2)
      → Partial Aggregate
          → Parallel Index Only Scan (idx_events_device)
              rows: 519,072 per worker
              heap fetches: 618,359
```

**TimescaleDB** — hypertable chunks + compression — hierarchical plan

```
Level 1: Parallel ChunkAppend (Chunking benefit)
Gather (Workers: 2, launched: 2)
  → Parallel ChunkAppend  loops=3, 11 chunks across workers
      │
      │  Level 2: Per-chunk scan (Compression inside each chunk)
      │
      ├── Compressed chunks (9 total):
      │   ├── VectorAgg → ColumnarScan on _hyper_1_145
      │   │   rows: 156,858  time: 0.000ms  ← columnar, near-instant
      │   │   Vectorized Filter: time > now()-10min
      │   │   └── Index (compress_hyper_*_device__ts_meta)
      │   │       rows: 157  ← metadata, not data rows
      │   ├── VectorAgg → ColumnarScan ... (same, ~0.000ms each)
      │   └── ... 7 more identical compressed chunks ...
      │
      └── Live chunks (2 total):
          ├── Partial Aggregate → Index Only Scan on _hyper_1_169
          │   rows: 77,898  time: 6.0ms  ← no compression
          └── Partial Aggregate → Index Only Scan on _hyper_1_180
              rows: 31,127  time: 2.9ms
```

**Key:** PG scans 1 big index in 1 pass. TS scans 11 small chunks in parallel (L1), with columnar + vectorized operations inside each compressed chunk (L2).

---

*TimescaleDB hypertable (1-min chunks, partitioned by device), compression enabled (1-min policy). Producer inserts 1,000 rows/sec. Both databases on identical hardware (4 CPU, 6 GB RAM each).*
