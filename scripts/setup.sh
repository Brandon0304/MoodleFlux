#!/bin/bash
# =============================================================================
# setup.sh - Preparacion del entorno MoodleFlux
# Uso: bash scripts/setup.sh
# Basado en: ADR-007
# =============================================================================
set -euo pipefail

echo "=== MoodleFlux Setup ==="

echo "-> Verificando requisitos..."
command -v docker >/dev/null 2>&1 || { echo "ERROR: Docker no esta instalado"; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo "ERROR: Docker Compose no esta instalado"; exit 1; }

if [ ! -f .env ]; then
    echo "-> Creando .env desde .env.example..."
    cp .env.example .env
    echo "IMPORTANTE: .env creado. REVISA y ajusta las contrasenas antes de continuar."
    exit 0
fi

echo "-> Creando directorios..."
mkdir -p moodle moodledata docker/nginx/conf.d docker/php-fpm docker/mariadb docker/moodle scripts

if [ ! -d "moodle/.git" ]; then
    echo "-> Clonando Moodle ${MOODLE_VERSION:-MOODLE_500_STABLE}..."
    git clone --depth 1 --branch "${MOODLE_VERSION:-MOODLE_500_STABLE}" \
        "${MOODLE_REPO:-https://github.com/moodle/moodle.git}" moodle/
else
    echo "-> Moodle ya existe. Actualizando..."
    cd moodle && git pull && cd ..
fi

echo "-> Generando certificados SSL autofirmados..."
mkdir -p docker/nginx/ssl
if [ ! -f docker/nginx/ssl/moodleflux.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout docker/nginx/ssl/moodleflux.key \
        -out docker/nginx/ssl/moodleflux.crt \
        -subj "/CN=localhost/O=MoodleFlux/C=CO"
fi

echo "-> Configurando health endpoint..."
cp docker/php-fpm/health.php moodle/health.php

echo "-> Generando config.php..."
set -a; source .env; set +a
envsubst < docker/moodle/config.php.tpl > moodle/config.php

echo "-> Construyendo imagenes..."
docker compose build

echo "-> Arrancando contenedores..."
docker compose up -d

echo "=== Setup completado ==="
echo "-> Web: https://localhost"
echo "-> Mailpit UI: http://localhost:8025"
echo "-> Admin: ${MOODLE_ADMIN_USER:-admin} / ${MOODLE_ADMIN_PASS:-Admin_2026!}"
echo ""
echo "IMPORTANTE: El primer arranque puede tardar. Ejecuta 'docker compose logs -f' para monitorear."
echo "IMPORTANTE: Acepta el certificado autofirmado en tu navegador."
