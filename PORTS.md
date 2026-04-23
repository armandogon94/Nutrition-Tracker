# Port Allocation — Project 03: Nutrition Tracker

> All host-exposed ports are globally unique across all 16 projects so every project can run simultaneously. See `../PORT-MAP.md` for the full map.

## Current Assignments

| Service | Host Port | Container Port | File |
|---------|-----------|---------------|------|
| Frontend (Next.js) | **3030** | 3000 | docker-compose.yml |
| Backend (FastAPI) | **8030** | 8001 | docker-compose.yml |
| PostgreSQL | **5433** | 5432 | docker-compose.yml |

> Note: Backend container port is 8001 (not 8000) — the FastAPI app is configured with `--port 8001`. The host-facing port is 8030.

## Allowed Range for New Services

If you need to add a new service to this project, pick from these ranges **only**:

| Type | Allowed Host Ports |
|------|--------------------|
| Frontend / UI | `3030 – 3039` |
| Backend / API | `8030 – 8039` |
| PostgreSQL | `5433` (already assigned — do not spin up a second instance) |
| Redis | Not assigned yet. If adding Redis, use host port `6379` is taken — contact the port map owner for an assignment. Currently no Redis in this project. |

## Do Not Use

Every port outside the ranges above is reserved by another project. Always check `../PORT-MAP.md` before picking a port.

Key ranges already taken:
- `3020-3029 / 8020-8029` → Project 02
- `3040-3049 / 8040-8049` → Project 04
- `5432` → Project 02 PostgreSQL
- `5434` → Project 04 PostgreSQL
- `5435-5439` → Projects 05, 11, 12, 13, 15 PostgreSQL
- `6379-6385` → Projects 02, 05, 10, 12, 13, 15, 16 Redis
