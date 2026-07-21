#!/bin/bash
# ============================================================
# start-patchguard.sh
# Script de démarrage complet PatchGuard v2.0
# Démarre : Docker + k3s + AWX
# Usage : ~/start-patchguard.sh
# ============================================================

set -e
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "  ██████╗  █████╗ ████████╗ ██████╗██╗  ██╗"
echo "  ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║"
echo "  ██████╔╝███████║   ██║   ██║     ███████║"
echo "  ██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║"
echo "  ██║     ██║  ██║   ██║   ╚██████╗██║  ██║"
echo "  ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "${GREEN}  PatchGuard v2.0 — Starting...${NC}"
echo "  $(date)"
echo ""

cd ~/patchguard

echo -e "${YELLOW}[1/4] Detecting WSL2 IP...${NC}"
WSL_IP=$(hostname -I | awk '{print $1}')
echo "      IP detected: $WSL_IP"

cat > nginx/patchguard.conf << NGINX
server {
    listen 80;
    server_name localhost;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name localhost;
    ssl_certificate     /etc/nginx/ssl/patchguard.crt;
    ssl_certificate_key /etc/nginx/ssl/patchguard.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    location /api/ansible/ {
        proxy_pass         http://patchguard-api:8000;
        proxy_read_timeout 300s;
        proxy_connect_timeout 10s;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
    location /api/windows/ {
        proxy_pass         http://patchguard-api:8000;
        proxy_read_timeout 120s;
        proxy_connect_timeout 10s;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
    location /api/patches {
        proxy_pass         http://patchguard-api:8000;
        proxy_read_timeout 120s;
        proxy_connect_timeout 10s;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
    location /api/lynis {
        proxy_pass         http://patchguard-api:8000;
        proxy_read_timeout 120s;
        proxy_connect_timeout 10s;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
    location / {
        proxy_pass         http://patchguard-api:8000;
        proxy_read_timeout 60s;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
NGINX
echo -e "      ${GREEN}Nginx config updated ✓${NC}"

echo -e "${YELLOW}[2/4] Starting Docker services...${NC}"
docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d
echo -e "      ${GREEN}Docker services started ✓${NC}"

echo -e "${YELLOW}[3/4] Starting k3s (Kubernetes)...${NC}"
sudo systemctl start k3s 2>/dev/null || true
sleep 5
K3S_STATUS=$(sudo kubectl get nodes 2>/dev/null | grep -c "Ready" || echo "0")
if [ "$K3S_STATUS" -gt "0" ]; then
    echo -e "      ${GREEN}k3s Ready ✓${NC}"
else
    echo -e "      ${RED}k3s not ready — AWX will not be available${NC}"
fi

echo -e "${YELLOW}[4/4] Starting AWX port-forward...${NC}"
pkill -f "port-forward.*patchguard-awx" 2>/dev/null || true
sleep 2
AWX_PODS=$(sudo kubectl get pods -n awx 2>/dev/null | grep -c "Running" || echo "0")
if [ "$AWX_PODS" -gt "0" ]; then
    sudo kubectl port-forward svc/patchguard-awx-service \
        -n awx --address 0.0.0.0 30080:80 > /dev/null 2>&1 &
    sleep 3
    echo -e "      ${GREEN}AWX port-forward started ✓${NC}"
else
    echo -e "      ${RED}AWX pods not running — skipping${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  PatchGuard v2.0 — Ready !${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  🛡️  Dashboard    : ${CYAN}https://localhost${NC}"
echo -e "  ⚙️  AWX          : ${CYAN}http://localhost:30080${NC}"
echo -e "  📊  Grafana      : ${CYAN}http://localhost:3000${NC}"
echo -e "  🔥  Prometheus   : ${CYAN}http://localhost:9090${NC}"
echo ""
echo -e "  Credentials  : admin / patchguard2026"
echo ""
