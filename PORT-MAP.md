# Port Allocation Map — All Projects

> **Rule:** Every service exposed on the host machine gets a globally unique port. This prevents conflicts when running multiple projects simultaneously on the same Mac (local dev) or VPS (production). On the VPS, Traefik handles public traffic on 80/443 and routes to internal container ports — but we still need unique *host-exposed* ports for direct access, debugging, and health checks.

---

## Reserved System Ports (DO NOT USE)

These ports are commonly used by macOS, Linux, or popular dev tools. None of our projects should bind to them.

| Port | Used By |
|------|---------|
| 22 | SSH |
| 53 | DNS |
| 80 | HTTP (reserved for Traefik) |
| 443 | HTTPS (reserved for Traefik) |
| 631 | CUPS (macOS printing) |
| 1080 | SOCKS proxy |
| 3306 | MySQL (common, avoid even if not using) |
| 5000 | macOS AirPlay Receiver (Monterey+) |
| 5001 | macOS AirPlay Receiver alt |
| 5353 | mDNS / Bonjour (macOS) |
| 5900 | VNC / Screen Sharing (macOS) |
| 7000 | macOS AirPlay |
| 7001 | macOS AirPlay alt |
| 8080 | Common proxy / dev server (avoid) |
| 8443 | HTTPS alt (common) |
| 8888 | Jupyter Notebook default |
| 9090 | Prometheus default |
| 9200 | Elasticsearch |
| 27017 | MongoDB |

---

## Global Shared Services (Project 00 — VPS Infrastructure)

These run once on the VPS (not per-project). All projects connect to them via Docker internal networking.

| Port | Service | Project | Notes |
|------|---------|---------|-------|
| 80 | Traefik HTTP | 00 | Redirects to 443 |
| 443 | Traefik HTTPS | 00 | Public entry point |
| 8180 | Traefik Dashboard | 00 | Admin only (was 8080, moved to avoid conflicts) |
| 5432 | PostgreSQL 16 | 00 | Bind to 127.0.0.1 only. All projects share one PG instance with separate databases |
| 6379 | Redis 7 | 00 | Bind to 127.0.0.1 only. Shared cache, each project uses different DB number (0-15) |
| 5678 | N8N | 09 | Workflow automation UI |
| 19999 | Netdata | 00 | System monitoring |
| 9000 | Portainer | 00 | Docker management UI |

### Redis DB Number Allocation

| DB# | Project | Usage |
|-----|---------|-------|
| 0 | 00 — VPS | Session cache, general |
| 1 | 01 — Dashboard | Widget cache |
| 2 | 02 — Habits | Streak cache |
| 3 | 03 — Health App | Nutrition/food cache |
| 4 | 04 — Finance | Session + expense cache |
| 5 | 05 — Data Platform | ETL/pipeline cache |
| 6 | 06 — AI Agents | Conversation cache |
| 7 | 07 — ML System | Prediction cache |
| 8 | 09 — N8N Automation | Workflow state |
| 9 | 11 — Second Brain | Embedding/search cache |
| 10 | 12 — Proposals | Session + draft cache |
| 11-15 | Reserved | Future projects |

### PostgreSQL Database Names

| Database | Project |
|----------|---------|
| `vps_infra` | 00 — VPS Infrastructure |
| `dashboard_db` | 01 — Personal Dashboard |
| `habits_db` | 02 — Habit Tracker |
| `health_db` | 03 — Health & Fitness App |
| `finance_db` | 04 — Finance Tracker |
| `dataplatform_oltp` | 05 — Data Platform (OLTP) |
| `dataplatform_warehouse` | 05 — Data Platform (Star Schema) |
| `metabase_db` | 05 — Data Platform (Metabase internal) |
| `agents_db` | 06 — AI Agents |
| `ml_system_db` | 07 — ML System |
| `n8n_db` | 09 — N8N Automation |
| `listmonk_db` | 09 — Listmonk (email) |
| `twenty_db` | 09 — Twenty CRM |
| `umami_db` | 09 — Umami Analytics |
| `second_brain_db` | 11 — Second Brain |
| `proposals_db` | 12 — Proposal Generator |

---

## Per-Project Port Allocation

### Project 00 — VPS Infrastructure
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 80 | 80 | Traefik HTTP |
| 443 | 443 | Traefik HTTPS |
| 8180 | 8080 | Traefik Dashboard |
| 5432 | 5432 | PostgreSQL (127.0.0.1 only) |
| 6379 | 6379 | Redis (127.0.0.1 only) |
| 19999 | 19999 | Netdata |
| 9000 | 9000 | Portainer |

### Project 01 — Personal Dashboard
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3010 | 8080 | Dashy Web UI |

### Project 02 — Habit Tracker
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3020 | 3000 | Frontend (Next.js) |
| 8020 | 8000 | Backend API (FastAPI) |

### Project 03 — Health & Fitness App
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3030 | 3000 | Frontend (Next.js) |
| 8030 | 8000 | Backend API (FastAPI) |

### Project 04 — Expense Tracker + AI Finance Chat
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3040 | 3000 | Frontend (Next.js) |
| 8040 | 8000 | Backend API (FastAPI) |
| 8041 | 8001 | Telegram Bot (webhook server) |

### Project 05 — Unified Data Platform
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3050 | 3000 | React Dashboard (v2 Custom) |
| 8050 | 8000 | Dashboard API (FastAPI) |
| 3051 | 3000 | Metabase (BI v1) |
| 3052 | 3000 | Grafana (Monitoring v1) |
| 4200 | 4200 | Prefect Server UI |
| 8051 | 8080 | dbt Docs (lineage) |

### Project 06 — AI Agents Portfolio
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3060 | 3000 | Chainlit UI |
| 8060 | 8000 | Agent API (FastAPI) |
| 6333 | 6333 | Qdrant HTTP |
| 6334 | 6334 | Qdrant gRPC |

### Project 07 — ML System Portfolio
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3070 | 3000 | ML Dashboard UI |
| 8070 | 8000 | Prediction API (FastAPI) |
| 5070 | 5000 | MLflow UI |

### Project 09 — Content & Marketing Automation
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 5678 | 5678 | N8N Workflow UI |
| 3090 | 3000 | Mixpost (Social Scheduler) |
| 9091 | 9000 | Listmonk (Email) |
| 3091 | 3000 | Twenty CRM |
| 3092 | 3000 | Umami Analytics |

### Project 10 — Video Pipeline (LOCAL ONLY — MacBook)
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3100 | 3000 | Remotion Preview Server |
| 8100 | 8000 | Pipeline API (if used) |

### Project 11 — Second Brain
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3110 | 3000 | Frontend (Next.js) |
| 8110 | 8000 | Backend API (FastAPI) |
| 8111 | 8001 | Telegram Bot (webhook server) |

### Project 12 — Proposal Generator
| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 3120 | 3000 | Frontend (Next.js) |
| 8120 | 8000 | Backend API (FastAPI) |

---

## Port Numbering Convention

The pattern is simple and predictable:

```
Frontend:  3000 + (project_number × 10) = 30{NN}
Backend:   8000 + (project_number × 10) = 80{NN}
Extra:     +1 from the base (e.g., 8041 for Telegram bot in Project 04)
```

Examples:
- Project 03 → Frontend: 3030, Backend: 8030
- Project 11 → Frontend: 3110, Backend: 8110

This means you can always calculate a project's ports from its number.

---

## Quick Lookup by Port Range

| Range | Usage |
|-------|-------|
| 80, 443 | Traefik (public HTTP/HTTPS) |
| 3010-3120 | Frontend web UIs |
| 3051-3092 | Tool UIs (Metabase, Grafana, Mixpost, etc.) |
| 4200 | Prefect Server |
| 5070 | MLflow |
| 5432 | PostgreSQL (shared) |
| 5678 | N8N |
| 6333-6334 | Qdrant |
| 6379 | Redis (shared) |
| 8020-8120 | Backend APIs |
| 8041, 8111 | Telegram bots |
| 8051 | dbt Docs |
| 8180 | Traefik Dashboard |
| 9000 | Portainer |
| 9091 | Listmonk |
| 19999 | Netdata |

---

## How to Use This Map

### In docker-compose.yml (dev):
```yaml
services:
  frontend:
    ports:
      - "3030:3000"  # Project 03 frontend
  backend:
    ports:
      - "8030:8000"  # Project 03 backend
```

### In docker-compose.yml (production):
On the VPS, Traefik routes by subdomain, so you typically DON'T expose host ports for production services (Traefik connects via Docker network). But if you need direct access for debugging:
```yaml
services:
  backend:
    ports:
      - "127.0.0.1:8030:8000"  # Only accessible from localhost
```

### In .env files:
```bash
FRONTEND_PORT=3030
BACKEND_PORT=8030
NEXT_PUBLIC_API_URL=http://localhost:8030
```

### When starting dev servers locally (without Docker):
```bash
# Project 03 backend
cd 03-Nutrition-Tracker/backend && uvicorn app.main:app --port 8030

# Project 03 frontend
cd 03-Nutrition-Tracker/frontend && next dev -p 3030
```

---

## Notes

1. **PostgreSQL and Redis are shared** — One instance each on the VPS, all projects connect via Docker internal network. Locally, you can run one Docker PG + Redis and all projects connect to it.

2. **127.0.0.1 binding** — On the VPS, always bind database/admin ports to `127.0.0.1` so they're not exposed to the internet. Traefik is the only thing on 0.0.0.0:80/443.

3. **Container ports stay standard** — Inside the container, services run on their default ports (3000 for Next.js, 8000 for FastAPI). The host port mapping is what makes them unique externally.

4. **Project 10 is local-only** — Runs on MacBook, never on the VPS. Its ports (3100, 8100) are only used locally.

5. **Traefik Dashboard moved to 8180** — Default 8080 conflicts with too many things (Spring Boot, other proxies, macOS default PHP server).
