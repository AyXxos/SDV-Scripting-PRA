#!/bin/bash

set -Eeuo pipefail

# ==========================================
# CONFIGURATION
# ==========================================

SOURCE_DIR="/var/www"
BACKUP_DIR="/tmp"

REMOTE_USER="adam"
REMOTE_IP="10.1.60.10"
REMOTE_PORT="2224"
REMOTE_DIR="/home/adam/sauvegardes"

DATE=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="www_backup_${DATE}.tar.gz"

ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"
REMOTE_PATH="${REMOTE_DIR}/${ARCHIVE_NAME}"

# ==========================================
# NETTOYAGE AUTOMATIQUE
# ==========================================

cleanup() {
    rm -f "$ARCHIVE_PATH"
}

trap cleanup EXIT

error_handler() {
    echo ""
    echo "[ERREUR] La sauvegarde a échoué à la ligne $1."
}

trap 'error_handler $LINENO' ERR

# ==========================================
# VERIFICATIONS
# ==========================================

echo "=========================================="
echo "          SAUVEGARDE DE /var/www"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "[ERREUR] Ce script doit être exécuté en root."
    echo "Utilisation : sudo ./backup_www.sh"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "[ERREUR] Le dossier $SOURCE_DIR n'existe pas."
    exit 1
fi

for COMMAND in tar gzip ssh scp; do
    if ! command -v "$COMMAND" >/dev/null 2>&1; then
        echo "[ERREUR] Commande manquante : $COMMAND"
        exit 1
    fi
done

# ==========================================
# VERIFICATION DU SERVEUR DISTANT
# ==========================================

echo ""
echo "[1/3] Vérification du serveur de sauvegarde..."

ssh -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_IP" \
    "test -d '$REMOTE_DIR' && test -w '$REMOTE_DIR'"

echo "[OK] Dossier distant accessible en écriture."

# ==========================================
# CREATION DE L'ARCHIVE
# ==========================================

echo ""
echo "[2/3] Création de l'archive..."

tar -czpf "$ARCHIVE_PATH" \
    -C / \
    -- var/www

if [ ! -s "$ARCHIVE_PATH" ]; then
    echo "[ERREUR] Archive absente ou vide."
    exit 1
fi

ARCHIVE_SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)

echo "[OK] Archive créée : $ARCHIVE_NAME"
echo "Taille : $ARCHIVE_SIZE"

# ==========================================
# TRANSFERT VERS LE SERVEUR DISTANT
# ==========================================

echo ""
echo "[3/3] Transfert vers le serveur de sauvegarde..."

scp -P "$REMOTE_PORT" "$ARCHIVE_PATH" \
    "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH"

echo "[OK] Transfert terminé."

# ==========================================
# FIN
# ==========================================

echo ""
echo "=========================================="
echo "       SAUVEGARDE TERMINEE"
echo "=========================================="

echo ""
echo "Archive : $ARCHIVE_NAME"
echo "Taille  : $ARCHIVE_SIZE"
echo "Serveur : $REMOTE_IP"
echo "Port    : $REMOTE_PORT"
echo "Dossier : $REMOTE_DIR"
echo ""
echo "Sauvegarde réalisée avec succès !"

