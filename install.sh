#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# PatchGuard v1.0 — Script d'installation automatique
# Auteur : Sauti RAYMOND — github.com/SautiRay/patchguard
# License : MIT
# ═══════════════════════════════════════════════════════════════

set -e  # Arrête le script si une commande echoue

# ── Couleurs ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
TEAL='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ── Fonctions utilitaires ─────────────────────────────────────
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
err()  { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }
info() { echo -e "${TEAL}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[ATTENTION]${NC} $1"; }
step() { echo -e "\n${BOLD}${TEAL}━━━ $1 ━━━${NC}\n"; }

# ── Banniere ──────────────────────────────────────────────────
clear
echo -e "${TEAL}"
echo "  ██████╗  █████╗ ████████╗ ██████╗██╗  ██╗ ██████╗ ██╗   ██╗ █████╗ ██████╗ ██████╗"
echo "  ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║██╔════╝ ██║   ██║██╔══██╗██╔══██╗██╔══██╗"
echo "  ██████╔╝███████║   ██║   ██║     ███████║██║  ███╗██║   ██║███████║██████╔╝██║  ██║"
echo "  ██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║██║   ██║██║   ██║██╔══██║██╔══██╗██║  ██║"
echo "  ██║     ██║  ██║   ██║   ╚██████╗██║  ██║╚██████╔╝╚██████╔╝██║  ██║██║  ██║██████╔╝"
echo "  ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝"
echo -e "${NC}"
echo -e "${BOLD}  Automated Linux Security Patch Management — v1.0${NC}"
echo -e "  github.com/SautiRay/patchguard — MIT License\n"
echo    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Etape 1 : Verifier Ubuntu ─────────────────────────────────
step "ETAPE 1 — Verification du systeme"

if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    err "PatchGuard necessite Ubuntu 22.04 LTS."
fi
ok "Ubuntu detecte"

if [ "$EUID" -ne 0 ]; then
    err "Lancez ce script avec sudo : sudo bash install.sh"
fi
ok "Droits root confirmes"

# ── Etape 2 : Installer Docker ────────────────────────────────
step "ETAPE 2 — Installation de Docker"

if command -v docker &> /dev/null; then
    ok "Docker deja installe : $(docker --version)"
else
    info "Installation de Docker en cours..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh > /dev/null 2>&1
    systemctl enable docker > /dev/null 2>&1
    systemctl start docker > /dev/null 2>&1
    ok "Docker installe : $(docker --version)"
fi

if ! command -v docker compose &> /dev/null; then
    apt-get install -y docker-compose > /dev/null 2>&1
fi
ok "Docker Compose disponible"

# ── Etape 3 : Cloner PatchGuard ───────────────────────────────
step "ETAPE 3 — Installation de PatchGuard"

INSTALL_DIR="/opt/patchguard"

if [ -d "$INSTALL_DIR" ]; then
    warn "PatchGuard deja installe dans $INSTALL_DIR"
    read -p "Mettre a jour ? (o/n) : " UPDATE
    if [ "$UPDATE" = "o" ]; then
        cd "$INSTALL_DIR" && git pull origin main
        ok "PatchGuard mis a jour"
    fi
else
    git clone https://github.com/SautiRay/patchguard.git "$INSTALL_DIR"
    ok "PatchGuard clone dans $INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ── Etape 4 : Collecter les informations ──────────────────────
step "ETAPE 4 — Configuration"

echo -e "${BOLD}Informations necessaires pour la configuration :${NC}\n"

read -p "Nombre de serveurs cibles a surveiller (1-10) : " NB_SERVERS
read -p "Utilisateur SSH sur les serveurs cibles (ex: ubuntu) : " SSH_TARGET_USER
read -p "Adresse e-mail pour les notifications : " NOTIF_EMAIL
read -p "Mot de passe admin pour PatchGuard (interface web) : " ADMIN_PASSWORD

# Collecter les IPs des serveurs cibles
SERVERS_IPS=()
for i in $(seq 1 $NB_SERVERS); do
    read -p "Adresse IP du serveur cible $i : " IP
    SERVERS_IPS+=("$IP")
done

# IP du serveur de gestion
HOST_IP=$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
if [ -z "$HOST_IP" ]; then
    HOST_IP=$(hostname -I | awk '{print $1}')
fi
info "IP du serveur de gestion detectee : $HOST_IP"

# Generer une cle secrete JWT
SECRET_KEY=$(openssl rand -hex 32)
ok "Cle secrete JWT generee"

# ── Etape 5 : Generer les cles SSH ───────────────────────────
step "ETAPE 5 — Generation des cles SSH"

SSH_KEY_PATH="/root/.ssh/patchguard_key"

if [ ! -f "$SSH_KEY_PATH" ]; then
    ssh-keygen -t ed25519 -C "patchguard-$(hostname)" -f "$SSH_KEY_PATH" -N ""
    ok "Cle SSH generee : $SSH_KEY_PATH"
else
    ok "Cle SSH existante utilisee : $SSH_KEY_PATH"
fi

echo ""
info "Copie de la cle SSH vers les serveurs cibles..."
for IP in "${SERVERS_IPS[@]}"; do
    ssh-copy-id -i "${SSH_KEY_PATH}.pub" -o StrictHostKeyChecking=no "${SSH_TARGET_USER}@${IP}" 2>/dev/null && \
        ok "Cle copiee vers $IP" || \
        warn "Echec copie vers $IP — verifiez l'acces SSH manuellement"
done

# ── Etape 6 : Generer le certificat SSL ──────────────────────
step "ETAPE 6 — Configuration SSL"

mkdir -p /etc/nginx/ssl

read -p "Avez-vous un nom de domaine ? (o/n) : " HAS_DOMAIN

if [ "$HAS_DOMAIN" = "o" ]; then
    read -p "Nom de domaine (ex: patchguard.monentreprise.be) : " DOMAIN
    apt-get install -y certbot > /dev/null 2>&1
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "$NOTIF_EMAIL"
    cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/nginx/ssl/patchguard.crt
    cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" /etc/nginx/ssl/patchguard.key
    ok "Certificat Let's Encrypt installe pour $DOMAIN"
else
    DOMAIN="localhost"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/patchguard.key \
        -out /etc/nginx/ssl/patchguard.crt \
        -subj "/C=BE/ST=Namur/L=Namur/O=PatchGuard/CN=localhost" 2>/dev/null
    ok "Certificat auto-signe genere"
fi

# ── Etape 7 : Generer le fichier .env ────────────────────────
step "ETAPE 7 — Generation de la configuration"

cat > "$INSTALL_DIR/.env" << ENVEOF
# PatchGuard Configuration — Genere automatiquement le $(date)
APP_HOST=0.0.0.0
APP_PORT=8000
SECRET_KEY=${SECRET_KEY}

# SSH Configuration
SSH_USER=${SSH_TARGET_USER}
SSH_KEY_PATH=/root/.ssh/patchguard_key
SSH_TIMEOUT=10

# Target servers
SERVER_0=${HOST_IP}
SERVER_0_USER=$(whoami)
ENVEOF

# Ajouter les serveurs cibles
for i in "${!SERVERS_IPS[@]}"; do
    echo "SERVER_$((i+1))=${SERVERS_IPS[$i]}" >> "$INSTALL_DIR/.env"
done

cat >> "$INSTALL_DIR/.env" << ENVEOF2

# Ansible paths
ANSIBLE_INVENTORY=/opt/patch-manager/ansible/inventaire.ini
ANSIBLE_PLAYBOOK_CHECK=/opt/patch-manager/ansible/verifier_correctifs.yml
ANSIBLE_PLAYBOOK_APPLY=/opt/patch-manager/ansible/appliquer_correctifs.yml

# Scripts paths
SCRIPT_AUDIT=/opt/patch-manager/scripts/audit.sh
SCRIPT_NOTIFICATION=/opt/patch-manager/scripts/notification.sh
SCRIPT_DASHBOARD=/opt/patch-manager/scripts/dashboard.sh

# Notification
NOTIF_EMAIL=${NOTIF_EMAIL}
ENVEOF2

chmod 600 "$INSTALL_DIR/.env"
ok "Fichier .env genere et securise (chmod 600)"

# ── Etape 8 : Adapter les IPs dans les configs ────────────────
step "ETAPE 8 — Adaptation des configurations"

# Nginx
sed -i "s|proxy_pass.*http://.*:8000;|proxy_pass http://${HOST_IP}:8000;|g" \
    "$INSTALL_DIR/nginx/patchguard.conf"
ok "Nginx configure avec l'IP $HOST_IP"

# Prometheus
cat > "$INSTALL_DIR/prometheus/prometheus.yml" << PROMEOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'patchguard'
    static_configs:
      - targets: ['${HOST_IP}:8000']
    metrics_path: '/metrics'
PROMEOF
ok "Prometheus configure avec l'IP $HOST_IP"

# Lynis permissions sur les serveurs cibles
info "Configuration Lynis sur les serveurs cibles..."
for IP in "${SERVERS_IPS[@]}"; do
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no \
        "${SSH_TARGET_USER}@${IP}" \
        "sudo apt install lynis -y > /dev/null 2>&1; sudo chmod 644 /var/log/lynis-report.dat 2>/dev/null; echo 'report_file_permissions=644' | sudo tee -a /etc/lynis/lynis.conf > /dev/null" \
        2>/dev/null && ok "Lynis configure sur $IP" || warn "Impossible de configurer Lynis sur $IP"
done

# ── Etape 9 : Lancer PatchGuard ──────────────────────────────
step "ETAPE 9 — Lancement de PatchGuard"

cd "$INSTALL_DIR"

# Arreter les services conflictuels
systemctl stop nginx 2>/dev/null || true
systemctl stop grafana-server 2>/dev/null || true
pkill -f prometheus 2>/dev/null || true
pkill -f uvicorn 2>/dev/null || true

info "Lancement des conteneurs Docker..."
service docker start > /dev/null 2>&1
docker compose down > /dev/null 2>&1
docker compose up --build -d

sleep 8
ok "PatchGuard demarre"

# ── Etape 10 : Verification finale ───────────────────────────
step "ETAPE 10 — Verification"

sleep 5

# Test API
if curl -sf "http://localhost:8000/api/health" > /dev/null 2>&1; then
    ok "API FastAPI repond sur le port 8000"
else
    warn "API ne repond pas encore — attendez 30 secondes et verifiez avec : curl http://localhost:8000/api/health"
fi

# Test HTTPS
if curl -sfk "https://localhost/api/health" > /dev/null 2>&1; then
    ok "HTTPS Nginx repond sur le port 443"
else
    warn "HTTPS ne repond pas encore"
fi

# Status conteneurs
echo ""
docker compose ps

# ── Etape 11 : Resume final ───────────────────────────────────
step "INSTALLATION TERMINEE"

echo -e "${GREEN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║   PatchGuard est installe et operationnel !   ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${BOLD}Acces :${NC}"
echo -e "  PWA Dashboard  →  ${TEAL}https://${HOST_IP}${NC}"
echo -e "  Grafana        →  ${TEAL}http://${HOST_IP}:3000${NC}  (admin / patchguard2026)"
echo -e "  Prometheus     →  ${TEAL}http://${HOST_IP}:9090${NC}"
echo ""
echo -e "${BOLD}Login PWA :${NC}"
echo -e "  Username : admin"
echo -e "  Password : ${ADMIN_PASSWORD}"
echo ""
echo -e "${BOLD}Prochaines etapes :${NC}"
echo -e "  1. Ouvrir ${TEAL}https://${HOST_IP}${NC} dans votre navigateur"
echo -e "  2. Configurer Postfix pour les notifications e-mail"
echo -e "  3. Configurer cron : sudo crontab -e"
echo ""
echo -e "${YELLOW}Documentation complete : github.com/SautiRay/patchguard${NC}"
echo ""
