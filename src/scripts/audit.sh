#!/bin/bash
# ============================================================
# audit.sh
# Script d'audit de sécurité automatique avec Lynis
# Détecte les failles et les correctifs manquants sur chaque VM
# TFE - Bachelier en Informatique et Systèmes - 2025
# ============================================================

# ── Variables de configuration ─────────────────────────────
DATE=$(date +"%Y-%m-%d_%H-%M")
RAPPORT_DIR="/opt/patch-manager/rapports"
RAPPORT_FILE="$RAPPORT_DIR/audit_$DATE.txt"
SSH_KEY="/home/raymond/.ssh/patch_key"
MACHINES=("192.168.56.101 srv-cible1" "192.168.56.102 srv-cible2" "192.168.56.103 srv-cible3")

# ── Création du dossier des rapports ───────────────────────
mkdir -p "$RAPPORT_DIR"

# ── Fonction pour écrire dans le rapport ───────────────────
log() {
    echo "$1" | tee -a "$RAPPORT_FILE"
}

# ── En-tête du rapport ─────────────────────────────────────
log "=============================================="
log " RAPPORT D'AUDIT DE SÉCURITÉ"
log " Date : $(date '+%d/%m/%Y à %H:%M')"
log " Généré par : $(whoami)@$(hostname)"
log "=============================================="

# ── Audit du serveur principal (srv-patch) ─────────────────
WSL_IP=$(hostname -I | awk '{print $1}' | head -n1)


log "[1] Audit local : $(hostname) (${WSL_IP})"
log "----------------------------------------------"
log "Serveur principal (srv-patch) - WSL2"
log ""

# Lancer l'audit Lynis en mode silencieux
sudo lynis audit system --quiet 2>/dev/null

# Récupérer le score
SCORE=$(grep "hardening_index" /var/log/lynis-report.dat \
        2>/dev/null | cut -d'=' -f2)
log "Score de sécurité (Hardening Index) : ${SCORE:-Non disponible} / 100"

# Lister les correctifs disponibles
PATCHES=$(apt list --upgradable 2>/dev/null | grep -c "/" 2>/dev/null)
log "Nombre de correctifs disponibles : ${PATCHES:-0}"

# Lister les correctifs de sécurité spécifiquement
SEC_PATCHES=$(apt list --upgradable 2>/dev/null \
              | grep -ic "security" 2>/dev/null)
log "Dont correctifs de sécurité : ${SEC_PATCHES:-0}"

# ── Audit des machines cibles via SSH ──────────────────────
for ENTRY in "${MACHINES[@]}"; do
    IP=$(echo "$ENTRY" | awk '{print $1}')
    NOM=$(echo "$ENTRY" | awk '{print $2}')

    log ""
    log "[*] Audit de la machine : $NOM ($IP)"
    log "----------------------------------------------"

    # Vérifier si la machine est accessible
    if ping -c 1 -W 3 "$IP" &>/dev/null; then
        log "Statut réseau : EN LIGNE"

        # Lancer Lynis sur la machine cible via SSH
        SCORE_CIBLE=$(ssh -o StrictHostKeyChecking=no \
            -i "$SSH_KEY" raylab@"$IP" \
            "sudo bash -c \"lynis audit system --quiet >/dev/null 2>&1 && \
            grep ^hardening_index= /var/log/lynis-report.dat | cut -d= -f2\"")
        log "Score de sécurité : ${SCORE_CIBLE:-Non disponible} / 100"

        # Compter les correctifs disponibles
        PATCHES_CIBLE=$(ssh -o StrictHostKeyChecking=no \
            -i "$SSH_KEY" raylab@"$IP" \
            "apt list --upgradable 2>/dev/null | grep -c '/'" \
            2>/dev/null)
        log "Correctifs disponibles : ${PATCHES_CIBLE:-0}"

        # Compter les correctifs de sécurité
        SEC_CIBLE=$(ssh -o StrictHostKeyChecking=no \
            -i "$SSH_KEY" raylab@"$IP" \
            "apt list --upgradable 2>/dev/null | grep -ic 'security'" \
            2>/dev/null)
        log "Dont correctifs de sécurité : ${SEC_CIBLE:-0}"

        # Vérifier si un redémarrage est nécessaire
        REBOOT=$(ssh -o StrictHostKeyChecking=no \
            -i "$SSH_KEY" raylab@"$IP" \
            "[ -f /var/run/reboot-required ] \
             && echo 'OUI - redémarrage nécessaire' \
             || echo 'NON'" 2>/dev/null)
        log "Redémarrage nécessaire : ${REBOOT:-Inconnu}"

    else
        log "Statut réseau : HORS LIGNE"
        log "Impossible d'effectuer l'audit sur cette machine."
    fi
done

# ── Pied de page du rapport ────────────────────────────────
log ""
log "=============================================="
log " Rapport complet sauvegardé :"
log " $RAPPORT_FILE"
log "=============================================="

echo ""
echo "Audit terminé. Rapport disponible : $RAPPORT_FILE"
