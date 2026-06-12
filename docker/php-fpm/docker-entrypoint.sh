#!/bin/sh
# =============================================================================
# Entrypoint para el contenedor PHP-FPM de Moodle
# Genera config.php desde template + variables de entorno
# Basado en: ADR-007
# =============================================================================
set -e

: "${MOODLE_DB_HOST:?Must set MOODLE_DB_HOST}"
: "${MOODLE_DB_NAME:?Must set MOODLE_DB_NAME}"
: "${MOODLE_DB_USER:?Must set MOODLE_DB_USER}"
: "${MOODLE_DB_PASS:?Must set MOODLE_DB_PASS}"
: "${MOODLE_ADMIN_USER:?Must set MOODLE_ADMIN_USER}"
: "${MOODLE_ADMIN_PASS:?Must set MOODLE_ADMIN_PASS}"
: "${REDIS_HOST:?Must set REDIS_HOST}"
: "${REDIS_PORT:?Must set REDIS_PORT}"

if [ ! -f /var/www/html/config.php ]; then
    echo "-> Generando config.php desde template..."
    if [ -f /var/www/html/config.php.tpl ]; then
        envsubst < /var/www/html/config.php.tpl > /var/www/html/config.php
        echo "-> config.php generado"
    else
        echo "WARNING: No se encontro config.php.tpl. Moodle usara instalacion web."
    fi
fi

mkdir -p /var/www/moodledata
chown -R www-data:www-data /var/www/moodledata
chmod 755 /var/www/moodledata

exec "$@"
