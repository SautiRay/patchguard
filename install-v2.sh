#!/bin/bash
# ============================================================
# install-v2.sh
# PatchGuard v2.0 — Script d'installation automatique
# Linux + Windows + AWX + Kubernetes
# Auteur : Sauti RAYMOND — github.com/SautiRay/patchguard
# License : MIT
# Usage : curl -sSL https://raw.githubusercontent.com/SautiRay/patchguard/v2.0/install-v2.sh | bash
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
err()  { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
step() { echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${NC}\n"; }

# ── Bannière ──────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}"
echo "  ██████╗  █████╗ ████████╗ ██████╗██╗  ██╗"
echo "  ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║"
echo "  ██████╔╝███████║   ██║   ██║     ███████║"
echo "  ██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║"
echo "  ██║     ██║  ██║   ██║   ╚██████╗██║  ██║"
echo "  ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "${BOLD}  PatchGuard v2.0 — Installation automatique${NC}"
echo -e "  Linux + Windows Server + AWX + Kubernetes"
echo -e "  github.com/SautiRay/patchguard — MIT License\n"
echo    "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Vérifications ─────────────────────────────────────────────────────────────
step "ÉTAPE 1 — Vérification du système"

if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    err "PatchGuard v2.0 nécessite Ubuntu 22.04+ LTS"
fi
ok "Ubuntu détecté"

if [ "$EUID" -ne 0 ]; then
    err "Lancez ce script avec sudo : sudo bash install-v2.sh"
fi
ok "Droits root confirmés"

RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$RAM" -lt 3000 ]; then
    err "PatchGuard v2.0 nécessite minimum 4GB RAM (détecté: ${RAM}MB)"
fi
ok "RAM suffisante : ${RAM}MB"

# ── Variables ─────────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/patchguard"
USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
PATCHGUARD_USER=${SUDO_USER:-$USER}

# ── Étape 2 — Dépendances système ────────────────────────────────────────────
step "ÉTAPE 2 — Installation des dépendances"

apt-get update -qq
apt-get install -y -qq \
    git curl wget ansible python3 python3-pip \
    openssh-client sshpass jq
ok "Dépendances système installées"

pip3 install pywinrm --break-system-packages -q
ok "pywinrm installé (support Windows)"

ansible-galaxy collection install ansible.windows -q 2>/dev/null || true
ansible-galaxy collection install community.windows -q 2>/dev/null || true
ok "Collections Ansible Windows installées"

# ── Étape 3 — Docker ─────────────────────────────────────────────────────────
step "ÉTAPE 3 — Installation Docker"

if command -v docker &>/dev/null; then
    ok "Docker déjà installé : $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker $PATCHGUARD_USER
    ok "Docker installé"
fi

if ! command -v docker compose &>/dev/null; then
    apt-get install -y -qq docker-compose-plugin
fi
ok "Docker Compose disponible"

# ── Étape 4 — k3s (Kubernetes) ───────────────────────────────────────────────
step "ÉTAPE 4 — Installation k3s (Kubernetes pour AWX)"

if command -v k3s &>/dev/null; then
    ok "k3s déjà installé"
else
    curl -sfL https://get.k3s.io | sh -
    sleep 10
    ok "k3s installé"
fi

# ── Étape 5 — Cloner PatchGuard ──────────────────────────────────────────────
step "ÉTAPE 5 — Installation PatchGuard v2.0"

if [ -d "$INSTALL_DIR" ]; then
    info "Mise à jour de PatchGuard existant..."
    cd $INSTALL_DIR
    git pull origin v2.0
else
    git clone -b v2.0 https://github.com/SautiRay/patchguard.git $INSTALL_DIR
fi
ok "PatchGuard v2.0 installé dans $INSTALL_DIR"

# ── Étape 6 — Configuration ──────────────────────────────────────────────────
step "ÉTAPE 6 — Configuration"

cd $INSTALL_DIR

# Générer clé SSH si absente
if [ ! -f "$USER_HOME/.ssh/id_rsa" ]; then
    sudo -u $PATCHGUARD_USER ssh-keygen -t rsa -b 4096 -f "$USER_HOME/.ssh/id_rsa" -N ""
    ok "Clé SSH générée"
else
    ok "Clé SSH existante conservée"
fi

# Créer .env si absent
if [ ! -f ".env" ]; then
    cat > .env << ENVEOF
# ── PatchGuard v2.0 Configuration ──
SECRET_KEY=$(openssl rand -hex 32)
SSH_USER=ubuntu
SSH_KEY=/root/.ssh/id_rsa
SSH_TIMEOUT=10

# Linux Servers (ajoutez vos serveurs)
# SERVER_1=192.168.1.10
# SERVER_1_USER=ubuntu

# Windows Servers (optionnel)
# WIN_SERVER_1=192.168.1.20
# WIN_USER=Administrateur
# WIN_PASSWORD=VotreMotDePasse
# WIN_ANSIBLE_INVENTORY=/opt/patchguard/src/ansible/inventaire_windows.ini
# WIN_PLAYBOOK_CHECK=/opt/patchguard/src/ansible/verifier_windows.yml
# WIN_PLAYBOOK_APPLY=/opt/patchguard/src/ansible/appliquer_windows.yml

# Ansible
ANSIBLE_INVENTORY=/opt/patchguard/src/ansible/inventaire.ini
ANSIBLE_PLAYBOOK_CHECK=/opt/patchguard/src/ansible/verifier_correctifs.yml
ANSIBLE_PLAYBOOK_APPLY=/opt/patchguard/src/ansible/appliquer_correctifs.yml
SCRIPT_AUDIT=/opt/patchguard/src/scripts/audit.sh
ENVEOF
    ok ".env créé — configurez vos serveurs dans $INSTALL_DIR/.env"
else
    ok ".env existant conservé"
fi

# ── Étape 7 — Certificat SSL ─────────────────────────────────────────────────
step "ÉTAPE 7 — Certificat SSL auto-signé"

mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/patchguard.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/patchguard.key \
        -out /etc/nginx/ssl/patchguard.crt \
        -subj "/C=BE/ST=Namur/L=Namur/O=PatchGuard/CN=localhost" 2>/dev/null
    ok "Certificat SSL généré"
else
    ok "Certificat SSL existant conservé"
fi

# ── Étape 8 — Démarrer les services ─────────────────────────────────────────
step "ÉTAPE 8 — Démarrage des services"

cd $INSTALL_DIR
docker compose up -d --build
ok "Services Docker démarrés"

# ── Étape 9 — Script de démarrage ────────────────────────────────────────────
step "ÉTAPE 9 — Configuration du démarrage automatique"

cp $INSTALL_DIR/scripts/start-patchguard.sh $USER_HOME/start-patchguard.sh
chmod +x $USER_HOME/start-patchguard.sh
chown $PATCHGUARD_USER:$PATCHGUARD_USER $USER_HOME/start-patchguard.sh
ok "Script de démarrage installé : ~/start-patchguard.sh"

# ── Résumé final ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  PatchGuard v2.0 — Installation terminée !${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  🛡️  Dashboard  : ${CYAN}https://localhost${NC}"
echo -e "  ⚙️  AWX        : ${CYAN}http://localhost:30080${NC}"
echo -e "  📊  Grafana    : ${CYAN}http://localhost:3000${NC}"
echo -e "  🔥  Prometheus : ${CYAN}http://localhost:9090${NC}"
echo ""
echo -e "  Credentials  : admin / patchguard2026"
echo ""
echo -e "  ${YELLOW}⚠️  Configurez vos serveurs dans :${NC}"
echo -e "     $INSTALL_DIR/.env"
echo ""
echo -e "  Prochain démarrage : ${CYAN}~/start-patchguard.sh${NC}"
echo ""
