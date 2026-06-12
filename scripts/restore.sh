#!/bin/bash
# =============================================================================
# restore.sh - Restaurar backup de MoodleFlux
# Uso: bash scripts/restore.sh <backup_dir>
# Basado en: ADR-007
# =============================================================================
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Uso: bash scripts/restore.sh <backup_dir>"
    echo "Ej: bash scripts/restore.sh ./backups/moodle_20260101_120000"
    exit 1
fi

BACKUP_PATH="$1"

if [ ! -d "${BACKUP_PATH}" ]; then
    echo "ERROR: No existe el directorio: ${BACKUP_PATH}"
    exit 1
fi

echo "=== MoodleFlux Restore ==="
echo "-> Restaurando desde: ${BACKUP_PATH}"

set -a; source .env 2>/dev/null || true; set +a

echo "-> Deteniendo PHP-FPM..."
docker compose stop php-fpm

if [ -f "${BACKUP_PATH}/database.sql.gz" ]; then
    echo "-> Restaurando base de datos..."
    gunzip -c "${BACKUP_PATH}/database.sql.gz" | \
        docker compose exec -T mariadb \
        mariadb -u "${MOODLE_DB_USER:-moodle}" \
        -p"${MOODLE_DB_PASS}" \
        "${MOODLE_DB_NAME:-moodle}"
    echo "-> Base de datos restaurada"
fi

if [ -f "${BACKUP_PATH}/moodledata.tar.gz" ]; then
    echo "-> Restaurando moodledata..."
    docker run --rm -v moodleflux_moodledata:/dest -v "${BACKUP_PATH}:/source" alpine \
        tar xzf /source/moodledata.tar.gz -C /dest 2>/dev/null || \
    echo "WARNING: No se pudo restaurar moodledata"
fi

if [ -f "${BACKUP_PATH}/config.php" ]; then
    echo "-> Restaurando config.php..."
    cp "${BACKUP_PATH}/config.php" moodle/config.php
    echo "-> config.php restaurado"
fi

echo "-> Reanudando PHP-FPM..."
docker compose start php-fpm

echo "=== Restauracion completada ==="
