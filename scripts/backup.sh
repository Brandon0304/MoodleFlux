#!/bin/bash
# =============================================================================
# backup.sh - Backup de base de datos + moodledata
# Uso: bash scripts/backup.sh [output_dir]
# Basado en: ADR-005, ADR-007
# =============================================================================
set -euo pipefail

BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/moodle_${TIMESTAMP}"

mkdir -p "${BACKUP_PATH}"

echo "=== MoodleFlux Backup ==="
echo "-> Directorio: ${BACKUP_PATH}"

echo "-> Respaldando base de datos..."
set -a; source .env 2>/dev/null || true; set +a
docker compose exec -T mariadb mariadb-dump \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    -u "${MOODLE_DB_USER:-moodle}" \
    -p"${MOODLE_DB_PASS}" \
    "${MOODLE_DB_NAME:-moodle}" \
    | gzip > "${BACKUP_PATH}/database.sql.gz"
echo "-> Base de datos respaldada"

echo "-> Respaldando moodledata..."
docker run --rm -v moodleflux_moodledata:/source -v "${BACKUP_PATH}:/dest" alpine \
    tar czf /dest/moodledata.tar.gz -C /source . 2>/dev/null || \
docker run --rm -v moodleflux_moodledata:/source -v "${BACKUP_PATH}:/dest" alpine \
    tar czf /dest/moodledata.tar.gz -C /source . 2>/dev/null || \
echo "WARNING: No se pudo respaldar moodledata (el volumen podria no existir)"

echo "-> Respaldando config.php..."
cp moodle/config.php "${BACKUP_PATH}/config.php" 2>/dev/null || true

echo "-> Limpiando backups antiguos (+7 dias)..."
find "${BACKUP_DIR}" -name "moodle_*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "=== Backup completado ==="
ls -lh "${BACKUP_PATH}/"
