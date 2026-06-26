QUERY="SELECT activity, count(*) as cnt FROM events WHERE time > now() - INTERVAL '10 minute' AND device = 'iPhone' GROUP BY activity ORDER BY cnt DESC;"

echo "========== PostgreSQL EXPLAIN =========="
docker compose exec -T postgres     psql -U tsadmin -d tsdb -c "EXPLAIN ANALYZE $QUERY"

echo ""
echo "========== TimescaleDB EXPLAIN =========="
docker compose exec -T timescaledb psql -U tsadmin -d tsdb -c "EXPLAIN ANALYZE $QUERY"

echo ""
echo "========== PostgreSQL TIMING =========="
PG_OUT=$(docker compose exec -T postgres     psql -U tsadmin -d tsdb -c "\timing" -c "$QUERY" 2>&1)
echo "$PG_OUT"

echo ""
echo "========== TimescaleDB TIMING =========="
TS_OUT=$(docker compose exec -T timescaledb psql -U tsadmin -d tsdb -c "\timing" -c "$QUERY" 2>&1)
echo "$TS_OUT"

PG_TIME=$(echo "$PG_OUT" | grep -oE 'Time: [0-9.]+ ms' | grep -oE '[0-9.]+')
TS_TIME=$(echo "$TS_OUT" | grep -oE 'Time: [0-9.]+ ms' | grep -oE '[0-9.]+')
RATIO=$(echo "scale=2; $PG_TIME / $TS_TIME" | bc)

echo ""
echo "============================================"
echo "  PostgreSQL   :  ${PG_TIME} ms"
echo "  TimescaleDB  :  ${TS_TIME} ms"
echo "  Speedup      :  ${RATIO}x faster"
echo "============================================"
