# TimescaleDB + PostgreSQL Docker Compose

## Quick Start

```bash
docker compose up -d
```

## Connect

| Database     | Port  | Command |
|-------------|-------|---------|
| TimescaleDB | 5432  | `docker compose exec timescaledb psql -U tsadmin -d tsdb` |
| PostgreSQL  | 5433  | `docker compose exec postgres psql -U tsadmin -d tsdb` |

## Stop & Clean Up

```bash
docker compose down          # stop containers
docker compose down -v       # stop + remove volumes (all data gone!)
```
