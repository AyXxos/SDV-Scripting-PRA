#!/bin/bash

set -Eeuo pipefail

# ==========================================
# CONFIGURATION
# ==========================================

SOURCE_DIR="/srv/www/wordpress"
BACKUP_DIR="/tmp"

REMOTE_USER="adam"
REMOTE_IP="10.1.60.10"
REMOTE_PORT="2224"
REMOTE_DIR="/home/adam/sauvegardes"

ARCHIVE_NAME=""
ARCHIVE_PATH=""

# ==========================================
# NETTOYAGE AUTOMATIQUE
# ==========================================

cleanup() {
    if [ -n "$ARCHIVE_PATH" ] && [ -f "$ARCHIVE_PATH" ]; then
        rm -f "$ARCHIVE_PATH"
    fi
}

trap cleanup EXIT

# ==========================================
# GESTION DES ERREURS
# ==========================================

error_handler() {
    echo ""
    echo "[ERREUR] La restauration a échoué à la ligne $1."
}

trap 'error_handler $LINENO' ERR

# ==========================================
# VERIFICATIONS
# ==========================================

echo "=========================================="
echo "       RESTAURATION DE /var/www"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "[ERREUR] Exécutez ce script avec sudo."
    exit 1
fi

for COMMAND in tar ssh scp; do
    if ! command -v "$COMMAND" >/dev/null 2>&1; then
        echo "[ERREUR] Commande manquante : $COMMAND"
        exit 1
    fi
done

if [ ! -d "$SOURCE_DIR" ]; then
    echo "[ERREUR] Le dossier $SOURCE_DIR n'existe pas."
    exit 1
fi

# ==========================================
# RECUPERATION DES ARCHIVES
# ==========================================

echo ""
echo "[1/4] Connexion au serveur de sauvegarde..."

ARCHIVES=$(ssh -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_IP" \
    "find '$REMOTE_DIR' -maxdepth 1 -type f -name 'www_backup_*.tar.gz' -printf '%f\n' | sort -r")

if [ -z "$ARCHIVES" ]; then
    echo "[ERREUR] Aucune archive disponible."
    exit 1
fi

mapfile -t ARCHIVE_LIST <<< "$ARCHIVES"

# ==========================================
# SELECTION DE L'ARCHIVE
# ==========================================

echo ""
echo "=========================================="
echo "       ARCHIVES DISPONIBLES"
echo "=========================================="
echo ""

PS3="Sélectionne le numéro de l'archive à restaurer (0 pour quitter) : "

select ARCHIVE_NAME in "${ARCHIVE_LIST[@]}"; do

    if [ "$REPLY" = "0" ]; then
        echo "Restauration annulée."
        exit 0
    fi

    if [[ "$REPLY" =~ ^[0-9]+$ ]] &&
       [ "$REPLY" -ge 1 ] &&
       [ "$REPLY" -le "${#ARCHIVE_LIST[@]}" ]; then
        break
    fi

    echo "Sélection invalide. Réessaie."
done

ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

echo ""
echo "Archive sélectionnée : $ARCHIVE_NAME"

# ==========================================
# CONFIRMATION
# ==========================================

echo ""
echo "ATTENTION !"
echo "La restauration va écraser les fichiers existants"
echo "dans /srv/www/wordpress lorsque ceux-ci sont présents dans l'archive."
echo "Les fichiers supplémentaires actuels ne seront pas supprimés."
echo ""

read -r -p "Confirmer la restauration ? (oui/non) : " CONFIRMATION

if [ "$CONFIRMATION" != "oui" ]; then
    echo "Restauration annulée."
    exit 0
fi

# ==========================================
# TELECHARGEMENT DE L'ARCHIVE
# ==========================================

echo ""
echo "[2/4] Téléchargement de l'archive..."

scp -P "$REMOTE_PORT" \
    "$REMOTE_USER@$REMOTE_IP:$REMOTE_DIR/$ARCHIVE_NAME" \
    "$ARCHIVE_PATH"

echo "[OK] Téléchargement terminé."

# ==========================================
# VERIFICATION DE L'ARCHIVE
# ==========================================

echo ""
echo "[3/4] Vérification de l'archive..."

if ! tar -tzf "$ARCHIVE_PATH" >/dev/null; then
    echo "[ERREUR] Archive invalide ou endommagée."
    exit 1
fi

# Vérifier que l'archive contient uniquement var/www
if ! tar -tzf "$ARCHIVE_PATH" | awk '
    /^\// { exit 1 }
    {
        n = split($0, parts, "/")
        for (i = 1; i <= n; i++) {
            if (parts[i] == "..") exit 1
        }
        if ($0 != "srv/www/wordpress" && $0 !~ /^srv\/www\/wordpress\//) exit 1
    }
'; then
    echo "[ERREUR] L'archive contient des chemins non autorisés."
    exit 1
fi

echo "[OK] Archive valide."

# ==========================================
# RESTAURATION
# ==========================================

echo ""
echo "[4/4] Restauration des fichiers..."

if tar -xzpf "$ARCHIVE_PATH" \
    -C / \
    --overwrite; then

    echo ""
    echo "[OK] Restauration effectuée avec succès !"

else
    echo "[ERREUR] Échec de la restauration."
    exit 1
fi

# ==========================================
# FIN
# ==========================================

echo ""
echo "=========================================="
echo "       RESTAURATION TERMINEE"
echo "=========================================="

echo ""
echo "Archive restaurée : $ARCHIVE_NAME"
echo "Dossier restauré : $SOURCE_DIR"
echo ""
echo "Les fichiers ont été restaurés avec succès !"

