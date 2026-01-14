# MoveX Deployment Project

Scripts và configurations để deploy MoveX platform lên Ubuntu server.

## 📋 Yêu cầu hệ thống

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4GB | 8GB+ |
| Disk | 20GB | 50GB+ |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04/24.04 LTS |

## 🏗 Architecture

```
                    ┌───────────────────────────────────────┐
                    │           Ubuntu Server                │
                    ├───────────────────────────────────────┤
                    │                                       │
   Internet ────────┼───► Port 8080 (Nginx API Gateway)    │
                    │           │                           │
                    │           ├─► /api/system  → :8180   │
                    │           ├─► /api/auth    → :8185   │
                    │           ├─► /api/master-data → :8181│
                    │           ├─► /api/oms     → :8182   │
                    │           └─► /api/tms     → :8183   │
                    │                                       │
   Internet ────────┼───► Port 8084 (Nginx Frontend)       │
                    │           │                           │
                    │           └─► Static files (React)   │
                    │                                       │
                    │     ┌─────────────────────────────┐   │
                    │     │   Docker Compose            │   │
                    │     │   - PostgreSQL :5435        │   │
                    │     │   - Redis :6389             │   │
                    │     │   - 5 Backend Services      │   │
                    │     └─────────────────────────────┘   │
                    └───────────────────────────────────────┘
```

## 🚀 Quick Start

### 1. Transfer files lên server

```bash
# Copy project lên server
scp -r movex-deploy root@<server-ip>:/opt/movex/

# SSH vào server
ssh root@<server-ip>
cd /opt/movex/movex-deploy
```

### 2. Configure environment

```bash
# Copy và chỉnh sửa environment file
cp .env.example .env
nano .env

# ⚠️ QUAN TRỌNG: Cập nhật các giá trị sau
#   - GITHUB_TOKEN=<your-token>
#   - SERVER_IP=<server-ip>
#   - DB_PASS=<strong-password>
#   - REDIS_PASSWORD=<strong-password>
```

### 3. Run deployment

```bash
# Make scripts executable
chmod +x scripts/*.sh scripts/utils/*.sh security/*.sh

# Option A: Full automated deployment
sudo ./scripts/05-deploy-all.sh

# Option B: Step-by-step deployment
sudo ./scripts/01-setup-server.sh   # Install dependencies
./scripts/02-clone-repos.sh          # Clone repositories
./scripts/03-build-services.sh       # Build backend
sudo ./scripts/04-build-frontend.sh  # Build & deploy frontend
```

### 4. Access the application

- **Frontend**: http://<server-ip>:8084
- **API**: http://<server-ip>:8080/api/system/actuator/health

## 📁 Project Structure

```
movex-deploy/
├── README.md                    # This file
├── .env.example                 # Environment template
├── .env                         # (gitignored) Your secrets
├── .gitignore                   # Git ignore rules
│
├── config/                      # Environment configs (copied to projects)
│   ├── frontend.env             # Frontend environment (VITE_* vars)
│   ├── backend-common.env       # Backend shared config (DB, Redis)
│   └── backend-auth.env         # Auth service specific config
│
├── scripts/
│   ├── 01-setup-server.sh       # Install Docker, Nginx, Java, Node.js
│   ├── 02-clone-repos.sh        # Clone all repos from GitHub
│   ├── 03-build-services.sh     # Build backend services
│   ├── 04-build-frontend.sh     # Build & deploy frontend
│   ├── 05-deploy-all.sh         # Full deployment orchestration
│   └── utils/
│       ├── env-loader.sh        # Environment utilities
│       └── health-check.sh      # Service health checks
│
├── nginx/
│   ├── movex-api-gateway.conf   # API Gateway (port 8080)
│   └── movex-frontend.conf      # Frontend server (port 8084)
│
├── docker/
│   └── docker-compose.prod.yml  # Production Docker Compose
│
└── security/
    └── firewall-rules.sh        # UFW firewall configuration
```

## ⚙️ Config Files

Config files trong thư mục `config/` được copy vào các projects trước khi build:

| Config File | Target | Description |
|-------------|--------|-------------|
| `frontend.env` | `movex-fe-masterdata/.env` | VITE_API_BASE_URL, etc. |
| `backend-common.env` | `movex-be-*/.env` | DB, Redis connection |
| `backend-auth.env` | `movex-be-auth/.env` | Auth-specific overrides |

**Cách chỉnh sửa:**
```bash
# 1. Sửa config files
nano config/frontend.env
nano config/backend-common.env

# 2. Chạy build - env sẽ được copy tự động
./scripts/03-build-services.sh
./scripts/04-build-frontend.sh
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_TOKEN` | GitHub Personal Access Token | **required** |
| `GITHUB_ORG` | GitHub organization | `xink-movex` |
| `GITHUB_BRANCH` | Branch to clone | `feature/demo-260114` |
| `DB_USER` | PostgreSQL username | `root` |
| `DB_PASS` | PostgreSQL password | `root` ⚠️ |
| `REDIS_PASSWORD` | Redis password | `movex123` ⚠️ |
| `SERVER_IP` | Server public IP | - |
| `NGINX_API_PORT` | API Gateway port | `8080` |
| `NGINX_FRONTEND_PORT` | Frontend port | `8084` |

> ⚠️ **Security**: Thay đổi passwords mặc định trên production!

### Port Mapping

| Port | Service | Access |
|------|---------|--------|
| 2226 | SSH | External |
| 8080 | Nginx API Gateway | External |
| 8084 | Nginx Frontend | External |
| 8180 | System Service | Internal (Docker) |
| 8181 | MasterData Service | Internal |
| 8182 | OMS Service | Internal |
| 8183 | TMS Service | Internal |
| 8185 | Auth Service | Internal |
| 5435 | PostgreSQL | Internal |
| 6389 | Redis | Internal |

## 🔐 Security

### Firewall (UFW)

Script `security/firewall-rules.sh` sẽ:
- Allow ports: 22 (SSH), 8080 (API), 8084 (Frontend)
- Block direct access to internal services
- Rate limit SSH connections

```bash
# Xem firewall status
sudo ufw status verbose

# Disable firewall (emergency)
sudo ufw disable
```

### Best Practices

1. **GitHub Token**: Không commit file `.env` vào git
2. **Database**: Thay đổi default credentials
3. **CORS**: Cấu hình allowed origins trong `nginx/movex-api-gateway.conf`
4. **HTTPS**: Thêm SSL certificates cho production

## 📊 Monitoring

### Health Check

```bash
# Check all services
./scripts/utils/health-check.sh

# Check specific service
curl http://localhost:8080/api/system/actuator/health
curl http://localhost:8084/health
```

### View Logs

```bash
# Docker service logs
docker compose -f docker/docker-compose.prod.yml logs -f

# Specific service
docker compose -f docker/docker-compose.prod.yml logs -f system

# Nginx logs
tail -f /var/log/nginx/movex-api-access.log
tail -f /var/log/nginx/movex-api-error.log
```

### Resource Usage

```bash
# Docker stats
docker stats

# System resources
htop
```

## 🔄 Operations

### Restart Services

```bash
# All services
docker compose -f docker/docker-compose.prod.yml restart

# Specific service
docker compose -f docker/docker-compose.prod.yml restart system

# Nginx
sudo systemctl restart nginx
```

### Update Deployment

```bash
# Pull latest code
./scripts/02-clone-repos.sh

# Rebuild and restart
./scripts/03-build-services.sh
docker compose -f docker/docker-compose.prod.yml up -d --build

# Rebuild frontend
sudo ./scripts/04-build-frontend.sh
```

### Stop Everything

```bash
docker compose -f docker/docker-compose.prod.yml down
sudo systemctl stop nginx
```

## 🐛 Troubleshooting

### Service not starting

```bash
# Check logs
docker compose -f docker/docker-compose.prod.yml logs system

# Check if port is in use
sudo lsof -i :8080

# Restart Docker daemon
sudo systemctl restart docker
```

### Database connection issues

```bash
# Check database health
docker exec movex_postgres pg_isready -U root

# Connect to database
docker exec -it movex_postgres psql -U root -d system
```

### Nginx errors

```bash
# Test configuration
sudo nginx -t

# Check error log
sudo tail -f /var/log/nginx/error.log
```

## 📄 License

Private - MoveX Platform

## 👥 Contact

- Team: MoveX Development Team
- Repository: https://github.com/xink-movex
