#!/bin/bash
# ============================================================
# dashboard.sh
# Tableau de bord - État en temps réel des machines
# TFE - Bachelier en Informatique et Systèmes - 2025
# ============================================================

SSH_KEY="/home/raymond/.ssh/patch_key"
MACHINES=("localhost srv-patch" \
          "192.168.56.101 srv-cible1" \
          "192.168.56.102 srv-cible2" \
          "192.168.56.103 srv-cible3")

# ── Couleurs pour le terminal ──────────────────────────────
ROUGE='\033[0;31m'
VERT='\033[0;32m'
JAUNE='\033[1;33m'
BLEU='\033[0;34m'
CYAN='\033[0;36m'
GRAS='\033[1m'
RESET='\033[0m'

# ── Fonction pour afficher une ligne de séparation ─────────
ligne() {
    echo -e "${BLEU}══════════════════════════════════════════════════════${RESET}"
}

# ── Boucle principale - rafraîchit toutes les 30 secondes ──
while true; do
    clear

    # En-tête du tableau de bord
    ligne
    echo -e "${GRAS}${CYAN}   TABLEAU DE BORD — GESTION DES CORRECTIFS${RESET}"
    echo -e "   Dernière mise à jour : $(date '+%d/%m/%Y à %H:%M:%S')"
    ligne

    TOTAL_ALERTES=0

    for ENTRY in "${MACHINES[@]}"; do
        IP=$(echo "$ENTRY" | awk '{print $1}')
        NOM=$(echo "$ENTRY" | awk '{print $2}')

        echo ""
        echo -e "${GRAS}  Machine : $NOM ($IP)${RESET}"
        echo -e "  ─────────────────────────────────────────────"

        # Vérifier si la machine est en ligne
        if ping -c 1 -W 2 "$IP" &>/dev/null; then

            # Récupérer les informations (local ou SSH)
            if [ "$IP" = "localhost" ]; then
                # Informations locales pour srv-patch
                PATCHES=$(apt list --upgradable 2>/dev/null \
                          | grep -c "/" 2>/dev/null || echo "0")
                SEC=$(apt list --upgradable 2>/dev/null \
                      | grep -ic "security" 2>/dev/null || echo "0")
                REBOOT=$([ -f /var/run/reboot-required ] \
                         && echo "OUI" || echo "NON")
                UPTIME=$(uptime -p 2>/dev/null || echo "Inconnu")
                DISK=$(df -h / 2>/dev/null \
                       | awk 'NR==2{print $5}' || echo "?")
                RAM=$(free -m 2>/dev/null \
                      | awk 'NR==2{printf "%.0f%%", $3/$2*100}' \
                      || echo "?")
            else
                # Informations distantes via SSH
                PATCHES=$(ssh -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -i "$SSH_KEY" raylab@"$IP" \
                    "apt list --upgradable 2>/dev/null \
                     | grep -c '/'" 2>/dev/null || echo "?")
                SEC=$(ssh -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -i "$SSH_KEY" raylab@"$IP" \
                    "apt list --upgradable 2>/dev/null \
                     | grep -ic 'security'" 2>/dev/null || echo "?")
                REBOOT=$(ssh -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -i "$SSH_KEY" raylab@"$IP" \
                    "[ -f /var/run/reboot-required ] \
                     && echo 'OUI' || echo 'NON'" \
                    2>/dev/null || echo "?")
                UPTIME=$(ssh -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -i "$SSH_KEY" raylab@"$IP" \
                    "uptime -p" 2>/dev/null || echo "Inconnu")
                DISK=$(ssh -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -i "$SSH_KEY" raylab@"$IP" \
                    "df -h / | awk 'NR==2{print \$5}'" \
                    2>/dev/null || echo "?")
                RAM=$(ssh -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -i "$SSH_KEY" raylab@"$IP" \
                    "free -m | awk 'NR==2{printf \"%.0f%%\", \$3/\$2*100}'" \
                    2>/dev/null || echo "?")
            fi

            # Afficher le statut réseau
            echo -e "  Statut réseau    : ${VERT}EN LIGNE${RESET}"
            echo -e "  Disponibilité    : $UPTIME"
            echo -e "  Disque utilisé   : $DISK"
            echo -e "  RAM utilisée     : $RAM"
            echo ""

            # Afficher les correctifs avec couleurs selon l'urgence
            if [ "$PATCHES" = "0" ]; then
                echo -e "  Correctifs       : ${VERT}Aucun — système à jour${RESET}"
            elif [ "$PATCHES" != "?" ]; then
                echo -e "  Correctifs       : ${JAUNE}$PATCHES disponible(s)${RESET}"
                TOTAL_ALERTES=$((TOTAL_ALERTES + 1))
            else
                echo -e "  Correctifs       : ${JAUNE}Données indisponibles${RESET}"
            fi

            # Afficher les correctifs de sécurité
            if [ "$SEC" != "0" ] && [ "$SEC" != "?" ]; then
                echo -e "  Sécurité         : ${ROUGE}*** $SEC correctif(s) de sécurité en attente ***${RESET}"
            else
                echo -e "  Sécurité         : ${VERT}OK${RESET}"
            fi

            # Afficher le besoin de redémarrage
            if [ "$REBOOT" = "OUI" ]; then
                echo -e "  Redémarrage      : ${ROUGE}Nécessaire${RESET}"
            else
                echo -e "  Redémarrage      : ${VERT}Non nécessaire${RESET}"
            fi

        else
            # Machine hors ligne
            echo -e "  Statut réseau    : ${ROUGE}HORS LIGNE${RESET}"
            echo -e "  Impossible de récupérer les informations."
            TOTAL_ALERTES=$((TOTAL_ALERTES + 1))
        fi
    done

    # ── Résumé global ──────────────────────────────────────
    echo ""
    ligne
    if [ "$TOTAL_ALERTES" -eq 0 ]; then
        echo -e "  STATUT GLOBAL : ${VERT}${GRAS}TOUT EST À JOUR — AUCUNE ALERTE${RESET}"
    else
        echo -e "  STATUT GLOBAL : ${ROUGE}${GRAS}ATTENTION — $TOTAL_ALERTES ALERTE(S) DÉTECTÉE(S)${RESET}"
    fi
    ligne
    echo ""
    echo -e "  Rafraîchissement automatique dans ${CYAN}30 secondes${RESET}"
    echo -e "  Appuyer sur ${GRAS}Ctrl+C${RESET} pour quitter."
    echo ""

    # Attendre 30 secondes avant de rafraîchir
    sleep 30
done
