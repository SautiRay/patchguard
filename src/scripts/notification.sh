#!/bin/bash
# ============================================================
# notification.sh
# Script de notification automatique par e-mail
#
# Rôle :
#  - Vérifier l'état des correctifs sur chaque machine cible
#  - Détecter les correctifs de sécurité en attente
#  - Déterminer si un redémarrage est requis
#  - Envoyer un rapport synthétique par e-mail
#
# TFE - Bachelier en Informatique et Systèmes - 2025
# ============================================================

# ────────────────────────────────────────────────────────────
# 1. Variables de configuration
# ────────────────────────────────────────────────────────────

# Adresse e-mail de l'administrateur
ADMIN_EMAIL="info.sautiray.it@gmail.com"

# Clé SSH utilisée pour accéder aux machines cibles
SSH_KEY="/home/raymond/.ssh/patch_key"

# Liste des machines cibles (IP + nom logique)
MACHINES=(
  "192.168.56.101 srv-cible1"
  "192.168.56.102 srv-cible2"
  "192.168.56.103 srv-cible3"
)

# Date et heure du rapport
DATE=$(date '+%d/%m/%Y à %H:%M')

# Dossier de stockage des rapports
RAPPORT_DIR="/opt/patch-manager/rapports"
mkdir -p "$RAPPORT_DIR"

# ────────────────────────────────────────────────────────────
# 2. Initialisation des variables de rapport
# ────────────────────────────────────────────────────────────

CORPS=""
TOTAL_ALERTES=0
TOTAL_PATCHES=0

# En-tête du rapport
CORPS+="==============================================\n"
CORPS+=" RAPPORT AUTOMATIQUE - GESTION DES CORRECTIFS\n"
CORPS+=" Date : $DATE\n"
CORPS+=" Serveur de gestion : srv-patch (localhost)\n"
CORPS+="==============================================\n\n"

# ────────────────────────────────────────────────────────────
# 3. Analyse de chaque machine cible
# ────────────────────────────────────────────────────────────

for ENTRY in "${MACHINES[@]}"; do
    IP=$(awk '{print $1}' <<< "$ENTRY")
    NOM=$(awk '{print $2}' <<< "$ENTRY")

    CORPS+="----------------------------------------------\n"
    CORPS+=" Machine : $NOM ($IP)\n"
    CORPS+="----------------------------------------------\n"

    # Vérification réelle de disponibilité (SSH, pas ping)
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSH_KEY" raylab@"$IP" "echo OK" >/dev/null 2>&1; then

        # ── Comptage des correctifs disponibles (méthode APT fiable)
        PATCHES=$(ssh -o ConnectTimeout=5 -i "$SSH_KEY" raylab@"$IP" \
            "sudo apt-get update -qq && sudo apt-get -s upgrade | awk '/^Inst/ {c++} END {print c+0}'" \
            2>/dev/null)
        PATCHES=${PATCHES:-0}

        # ── Comptage des correctifs de sécurité (approximation cohérente)
        SEC=$(ssh -o ConnectTimeout=5 -i "$SSH_KEY" raylab@"$IP" \
            "sudo apt-get update -qq && sudo apt-get -s upgrade | grep -i security | wc -l" \
            2>/dev/null)
        SEC=${SEC:-0}

        # ── Vérification du besoin de redémarrage
        REBOOT=$(ssh -o ConnectTimeout=5 -i "$SSH_KEY" raylab@"$IP" \
            "[ -f /var/run/reboot-required ] && echo OUI || echo NON" \
            2>/dev/null)

        # ── Dernière action APT enregistrée
        DERNIERE_MAJ=$(ssh -o ConnectTimeout=5 -i "$SSH_KEY" raylab@"$IP" \
            "grep -E 'upgrade|install' /var/log/dpkg.log 2>/dev/null | tail -1 | cut -d' ' -f1-2" \
            2>/dev/null)
        DERNIERE_MAJ=${DERNIERE_MAJ:-Inconnue}

        # ── Écriture des résultats
        CORPS+=" Statut              : EN LIGNE\n"
        CORPS+=" Correctifs totaux   : $PATCHES\n"
        CORPS+=" Correctifs sécurité : $SEC\n"
        CORPS+=" Redémarrage requis  : $REBOOT\n"
        CORPS+=" Dernière mise à jour: $DERNIERE_MAJ\n"

        TOTAL_PATCHES=$((TOTAL_PATCHES + PATCHES))

        # ── Détection d'alertes
        if [ "$SEC" -gt 0 ]; then
            CORPS+=" !! ALERTE : $SEC correctif(s) de sécurité en attente !!\n"
            TOTAL_ALERTES=$((TOTAL_ALERTES + 1))
        fi

        if [ "$REBOOT" = "OUI" ]; then
            CORPS+=" !! ALERTE : Un redémarrage est nécessaire !!\n"
            TOTAL_ALERTES=$((TOTAL_ALERTES + 1))
        fi

    else
        # Machine inaccessible
        CORPS+=" Statut : HORS LIGNE - vérification impossible\n"
        TOTAL_ALERTES=$((TOTAL_ALERTES + 1))
    fi

    CORPS+="\n"
done

# ────────────────────────────────────────────────────────────
# 4. Résumé global
# ────────────────────────────────────────────────────────────

CORPS+="==============================================\n"
CORPS+=" RÉSUMÉ GLOBAL\n"
CORPS+="==============================================\n"
CORPS+=" Total correctifs en attente : $TOTAL_PATCHES\n"
CORPS+=" Nombre d'alertes détectées  : $TOTAL_ALERTES\n\n"

if [ "$TOTAL_ALERTES" -gt 0 ]; then
    CORPS+=" STATUT : ATTENTION - DES ACTIONS SONT NÉCESSAIRES\n"
    SUJET="[ALERTE SÉCURITÉ] $TOTAL_ALERTES alerte(s) - $DATE"
else
    CORPS+=" STATUT : OK - Tous les systèmes sont à jour\n"
    SUJET="[PATCH MANAGER] Rapport OK - $DATE"
fi

CORPS+="==============================================\n"
CORPS+="Rapport généré automatiquement par\n"
CORPS+="le systèm de gestion des correctifs -TFE 2025\n"
CORPS+="==============================================\n"

# ────────────────────────────────────────────────────────────
# 5. Sauvegarde et envoi du rapport
# ────────────────────────────────────────────────────────────

FICHIER="$RAPPORT_DIR/notif_$(date +%Y%m%d_%H%M).txt"
echo -e "$CORPS" > "$FICHIER"

echo -e "$CORPS" | mail -s "$SUJET" "$ADMIN_EMAIL"

echo "Notification envoyée à : $ADMIN_EMAIL"
echo "Alertes détectées      : $TOTAL_ALERTES"
echo "Rapport sauvegardé     : $FICHIER"
