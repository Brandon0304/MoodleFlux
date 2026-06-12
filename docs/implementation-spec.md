# MoodleFlux — Spec Técnico de Implementación para Build Agent

> **Versión:** 1.0  
> **Fecha:** 2026-06-12  
> **Propósito:** Guía detallada para que el Build agent implemente docker-compose.yml, Dockerfiles, configs de Nginx/PHP/MariaDB, config.php de Moodle, scripts de inicialización y .env.example.  
> **Basado en:** ADR-001 al ADR-008 + docs/reference/*

---

## Índice

1. [Estructura final del repositorio](#1-estructura-final-del-repositorio)
2. [docker-compose.yml](#2-docker-composeyml)
3. [Servicio Nginx](#3-servicio-nginx)
4. [Servicio PHP-FPM](#4-servicio-php-fpm)
5. [Servicio Redis](#5-servicio-redis)
6. [Servicio MariaDB](#6-servicio-mariadb)
7. [Servicio Mailpit](#7-servicio-mailpit)
8. [config.php de Moodle](#8-configphp-de-moodle)
9. [.env.example](#9-envexample)
10. [Scripts de inicialización](#10-scripts-de-inicialización)
11. [Scripts operativos](#11-scripts-operativos)
12. [Instrucciones de uso para el desarrollador](#12-instrucciones-de-uso)

---

## 1. Estructura final del repositorio

```
MoodleFlux/
├── .agents/                    ← YA EXISTE (no tocar)
├── .github/                    ← YA EXISTE (workflows CI/CD, no tocar)
├── docs/                       ← YA EXISTE (ADRs, diagramas, referencias)
│   └── implementation-spec.md  ← ESTE DOCUMENTO
├── docker/
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   │       └── moodle.conf
│   ├── php-fpm/
│   │   ├── Dockerfile
│   │   ├── php.ini
│   │   └── www.conf
│   ├── mariadb/
│   │   └── my.cnf
│   └── moodle/
│       └── config.php.tpl      ← Template no versionado como .php
├── scripts/
│   ├── backup.sh
│   ├── restore.sh
│   └── healthcheck.sh
├── moodle/                     ← NO VERSIONAR (gitignorado)
│   ├── config.php              ← Generado desde config.php.tpl + .env
│   └── ... (core de Moodle)
├── .env.example                ← Template de entorno
├── .gitignore                  ← YA EXISTE, actualizar si falta algo
├── docker-compose.yml          ← A CREAR
└── README.md                   ← YA EXISTE (actualizar con instrucciones)
```

---

## 2. docker-compose.yml

### 2.1 Especificación general

| Aspecto | Valor |
|---------|-------|
| Versión de schema | `3.9` (compatible Docker Engine 20.10+) |
| Project name | `${COMPOSE_PROJECT_NAME:-moodleflux}` (desde .env) |
| Redes | `frontend_net` (expuesta al host) + `backend_net` (interna, sin acceso externo) |
| Política de reinicio | `unless-stopped` en todos los servicios |

### 2.2 Redes

```yaml
networks:
  frontend_net:
    driver: bridge
    # Solamente nginx se conecta a frontend_net
  backend_net:
    driver: bridge
    internal: true   # Sin acceso desde el host
```

### 2.3 Volúmenes

```yaml
volumes:
  mariadb-data:
    driver: local
  redis-data:
    driver: local
  moodledata:
    driver: local
    # Para pruebas locales, usar bind mount:
    # driver_opts:
    #   type: none
    #   device: ${PWD}/moodledata
    #   o: bind
```

### 2.4 Servicios (tabla resumen)

| Servicio | Imagen | Puertos | Depende de | Redes |
|----------|--------|---------|------------|-------|
| `nginx` | `nginx:1.27-alpine` | `443:443` | `php-fpm` | frontend, backend |
| `php-fpm` | build local `./docker/php-fpm` | _ninguno_ | `mariadb`, `redis` | backend |
| `redis` | `redis:7-alpine` | _ninguno_ | — | backend |
| `mariadb` | `mariadb:10.11` | _ninguno_ (opcional 3306) | — | backend |
| `mailpit` | `axllent/mailpit:latest` | `8025:8025` | — | backend |

### 2.5 Orden de arranque seguro

```
mariadb ──▶ redis ──▶ php-fpm ──▶ nginx
   ↑          ↑          │
   └──────────┴──────────┘ (condition: service_healthy)
```

Usar `depends_on` con `condition: service_healthy` para php-fpm → mariadb y php-fpm → redis.

### 2.6 Health checks obligatorios

Cada servicio DEBE tener un health check:

| Servicio | Test | Intervalo | Timeout | Retries | Start period |
|----------|------|-----------|---------|---------|--------------|
| nginx | `["CMD", "nginx", "-t"]` | 30s | 10s | 3 | 10s |
| php-fpm | `["CMD", "php", "/var/www/html/health.php"]` | 15s | 5s | 3 | 30s |
| redis | `["CMD", "redis-cli", "ping"]` | 10s | 3s | 5 | 5s |
| mariadb | `["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]` | 10s | 5s | 5 | 30s |
| mailpit | `["CMD", "wget", "--spider", "http://localhost:8025/health"]` | 30s | 10s | 3 | 15s |

### 2.7 Límites de recursos

Cada contenedor DEBE tener resource limits para evitar que un servicio agote los recursos del host:

```yaml
services:
  nginx:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 128M
    mem_limit: 128m
    mem_reservation: 64m

  php-fpm:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
    mem_limit: 512m
    mem_reservation: 256m

  redis:
    deploy:
      resources:
        limits:
          cpus: '0.3'
          memory: 256M
    mem_limit: 256m
    mem_reservation: 128m

  mariadb:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
    mem_limit: 1g
    mem_reservation: 512m

  mailpit:
    deploy:
      resources:
        limits:
          cpus: '0.2'
          memory: 128M
    mem_limit: 128m
    mem_reservation: 64m
```

### 2.8 Variables de entorno por servicio

Cada servicio recibe variables de entorno para configurarse:

```yaml
services:
  php-fpm:
    environment:
      MOODLE_DB_HOST: mariadb
      MOODLE_DB_NAME: ${MOODLE_DB_NAME:-moodle}
      MOODLE_DB_USER: ${MOODLE_DB_USER:-moodle}
      MOODLE_DB_PASS: ${MOODLE_DB_PASS:?Must set MOODLE_DB_PASS}
      MOODLE_ADMIN_USER: ${MOODLE_ADMIN_USER:-admin}
      MOODLE_ADMIN_PASS: ${MOODLE_ADMIN_PASS:?Must set MOODLE_ADMIN_PASS}
      MOODLE_SITE_NAME: ${MOODLE_SITE_NAME:-MoodleFlux PoC}
      MOODLE_LANG: ${MOODLE_LANG:-es}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      PHP_MEMORY_LIMIT: ${PHP_MEMORY_LIMIT:-256M}
      PHP_MAX_EXECUTION_TIME: ${PHP_MAX_EXECUTION_TIME:-120}
      PHP_MAX_CHILDREN: ${PHP_MAX_CHILDREN:-10}
      PHP_START_SERVERS: ${PHP_START_SERVERS:-2}
      PHP_MIN_SPARE_SERVERS: ${PHP_MIN_SPARE_SERVERS:-1}
      PHP_MAX_SPARE_SERVERS: ${PHP_MAX_SPARE_SERVERS:-3}
      TZ: ${TZ:-America/Bogota}

  mariadb:
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:?Must set MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MOODLE_DB_NAME:-moodle}
      MYSQL_USER: ${MOODLE_DB_USER:-moodle}
      MYSQL_PASSWORD: ${MOODLE_DB_PASS:?Must set MOODLE_DB_PASS}
      TZ: ${TZ:-America/Bogota}

  nginx:
    environment:
      TZ: ${TZ:-America/Bogota}

  redis:
    environment:
      TZ: ${TZ:-America/Bogota}
```

### 2.9 Volúmenes montados

```yaml
services:
  php-fpm:
    volumes:
      - moodledata:/var/www/moodledata
      - ./docker/moodle/config.php.tpl:/var/www/html/config.php:ro
      # Nota: config.php se genera en entrypoint, pero este mount lo sobrescribe
      # Mejor enfoque: generar config.php en entrypoint desde template + env vars

  mariadb:
    volumes:
      - mariadb-data:/var/lib/mysql
      - ./docker/mariadb/my.cnf:/etc/mysql/conf.d/moodle.cnf:ro

  redis:
    volumes:
      - redis-data:/data

  nginx:
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./docker/nginx/conf.d:/etc/nginx/conf.d:ro
      - moodledata:/var/www/moodledata:ro   # Para servir estáticos
      # Moodle core montado como bind para desarrollo:
      - ./moodle:/var/www/html:ro
```

---

## 3. Servicio Nginx

### 3.1 nginx.conf

```nginx
user  nginx;
worker_processes  auto;          # ADR-002: event-driven, auto detecta CPUs
worker_rlimit_nofile 65535;      # Límite de archivos abiertos

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  4096;    # ADR-002: alta concurrencia
    multi_accept on;
    use epoll;                   # Linux高性能
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Formato de log JSON estructurado (ADR-008)
    log_format json_combined escape=json '{'
        '"time_local":"$time_local",'
        '"remote_addr":"$remote_addr",'
        '"remote_user":"$remote_user",'
        '"request":"$request",'
        '"status":$status,'
        '"body_bytes_sent":$body_bytes_sent,'
        '"request_time":$request_time,'
        '"http_referrer":"$http_referer",'
        '"http_user_agent":"$http_user_agent",'
        '"http_x_forwarded_for":"$http_x_forwarded_for",'
        '"upstream_addr":"$upstream_addr",'
        '"upstream_response_time":"$upstream_response_time"'
    '}';

    access_log  /var/log/nginx/access.log  json_combined;
    access_log off;   # En producción quitar este off

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;

    keepalive_timeout   65;
    keepalive_requests  100;

    # Tamaños
    client_max_body_size        100M;   # ADR-006: límite de subida
    client_body_buffer_size     128k;
    proxy_buffer_size           4k;
    proxy_buffers              8 4k;

    # Timeouts (ADR-002)
    proxy_connect_timeout       10s;
    proxy_send_timeout          60s;
    proxy_read_timeout          120s;

    # Seguridad (ADR-006)
    server_tokens               off;      # Oculta versión de Nginx
    add_header X-Content-Type-Options    "nosniff" always;
    add_header X-Frame-Options           "SAMEORIGIN" always;
    add_header X-XSS-Protection          "1; mode=block" always;

    # Compresión
    gzip              on;
    gzip_vary         on;
    gzip_proxied      any;
    gzip_comp_level   6;
    gzip_types        text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_min_length   1000;

    include /etc/nginx/conf.d/*.conf;
}
```

### 3.2 moodle.conf

```nginx
upstream php-fpm {
    # Para escalado con --scale php-fpm=N, Nginx balancea round-robin
    # En Docker Compose, el service name resuelve a todas las réplicas
    server php-fpm:9000;
    keepalive 32;                       # Conexiones persistentes
}

server {
    listen       443 ssl http2;
    # listen       80;                  # Redirigir a HTTPS (descomentar en prod)
    # return 301 https://$host$request_uri;
    # }

    server_name  localhost moodleflux.local;

    # SSL (ADR-006)
    ssl_certificate     /etc/nginx/ssl/moodleflux.crt;
    ssl_certificate_key /etc/nginx/ssl/moodleflux.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # HSTS (ADR-006)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Root de Moodle
    root /var/www/html;
    index index.php index.html;

    # ============================================================
    # Health check endpoint (ADR-008)
    # ============================================================
    location /health {
        access_log off;
        # Se pasa a PHP-FPM para que verifique DB + Redis
        try_files /dev/null /health.php;
    }

    # ============================================================
    # Archivos estáticos (servidos directamente por Nginx)
    # ============================================================
    location ~* \.(jpg|jpeg|gif|png|css|js|ico|svg|webp|woff|woff2|ttf|eot)$ {
        expires 365d;
        add_header Cache-Control "public, immutable";
        access_log off;
        try_files $uri @php-fpm;
    }

    # ============================================================
    # moodledata - archivos subidos
    # ============================================================
    location /moodledata {
        internal;    # No accesible directamente desde el exterior
        alias /var/www/moodledata;
        expires 7d;
        add_header Cache-Control "public";
    }

    # ============================================================
    # Rewrite de Moodle (clean URLs)
    # ============================================================
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # ============================================================
    # Proxy a PHP-FPM
    # ============================================================
    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass php-fpm;
        fastcgi_index index.php;

        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;

        # Buffer y timeouts
        fastcgi_buffer_size 128k;
        fastcgi_buffers 8 128k;
        fastcgi_read_timeout 120s;
        fastcgi_send_timeout 60s;

        # Pasar esquema HTTPS correctamente
        fastcgi_param HTTPS on;
    }

    # ============================================================
    # Denegar acceso a archivos sensibles
    # ============================================================
    location ~ /\.(?!well-known) {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ /(config\.php|install\.php|admin\/upgrade\.php) {
        # Permitir acceso normal - Moodle los protege internamente
        try_files $uri /index.php?$query_string;
    }

    # ============================================================
    # Páginas de error
    # ============================================================
    error_page 404 /index.php;
    error_page 500 502 503 504 /error/5xx.html;

    # ============================================================
    # Logs
    # ============================================================
    access_log /var/log/nginx/moodle_access.log json_combined;
    error_log  /var/log/nginx/moodle_error.log warn;
}
```

### 3.3 Generación de certificado SSL autofirmado

El Build agent debe incluir un script o instrucción para generar el certificado SSL autofirmado local:

```bash
# En el Dockerfile de nginx O en un script de setup:
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/moodleflux.key \
  -out /etc/nginx/ssl/moodleflux.crt \
  -subj "/CN=localhost/O=MoodleFlux/C=CO"
```

**Opción recomendada:** Generar los certificados en el host y montarlos como volumen en lugar de generarlos en el Dockerfile, para evitar regenerarlos en cada build.

---

## 4. Servicio PHP-FPM

### 4.1 Dockerfile

```dockerfile
# ============================================================
# Dockerfile para PHP-FPM con Moodle
# Basado en ADR-001: PHP 8.3 con extensiones Moodle
# ============================================================
FROM php:8.3-fpm-alpine AS base

LABEL maintainer="MoodleFlux Architecture"
LABEL description="PHP-FPM container for Moodle LMS with Redis, intl, and database extensions"

# Argumentos de build
ARG MOODLE_VERSION=MOODLE_500_STABLE
ARG WWW_DATA_UID=1000

# ============================================================
# 1. Instalar dependencias del sistema
# ============================================================
RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        icu-dev \
        libzip-dev \
        openssl-dev \
        postgresql-dev \
        oniguruma-dev \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libxml2-dev \
    ; \
    apk add --no-cache \
        icu-libs \
        libzip \
        libxml2 \
        libpng \
        freetype \
        libjpeg-turbo \
        bash \
        curl \
        git \
        mariadb-client \
        openssl \
        shadow   # para usermod/groupmod
    ;

# ============================================================
# 2. Instalar extensiones PHP requeridas por Moodle
# ============================================================
RUN set -eux; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        gd \
        intl \
        mbstring \
        mysqli \
        opcache \
        pcntl \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        soap \
        xmlrpc \
        zip \
    ; \
    # Redis extension para sesiones y caché
    pecl install redis; \
    docker-php-ext-enable redis; \
    # Limpiar
    apk del .build-deps; \
    rm -rf /var/cache/apk/* /tmp/*

# ============================================================
# 3. Configurar PHP
# ============================================================
COPY php.ini /usr/local/etc/php/conf.d/moodle-php.ini
COPY www.conf /usr/local/etc/php-fpm.d/www.conf

# ============================================================
# 4. Crear directorios y permisos
# ============================================================
RUN set -eux; \
    mkdir -p /var/www/moodledata /var/www/html /var/log/php; \
    chown -R www-data:www-data /var/www; \
    chmod 755 /var/www

# ============================================================
# 5. Entrypoint personalizado
# ============================================================
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
```

### 4.2 php.ini

```ini
; ============================================================
; PHP configuration for Moodle LMS
; Basado en ADR-001, ADR-002, ADR-004
; ============================================================

[PHP]
; ========== MEMORIA Y EJECUCIÓN ==========
memory_limit = ${PHP_MEMORY_LIMIT:-256M}
max_execution_time = ${PHP_MAX_EXECUTION_TIME:-120}
max_input_time = 300
max_input_vars = 5000

; ========== SUBIDA DE ARCHIVOS ==========
file_uploads = On
upload_max_filesize = 100M
post_max_size = 110M
max_file_uploads = 20

; ========== MANEJO DE ERRORES ==========
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
log_errors = On
error_log = /var/log/php/error.log

; ========== OPCODE CACHE ==========
[opcache]
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 60
opcache.fast_shutdown = 1
opcache.validate_timestamps = 0       ; En producción. En dev: = 1
; En desarrollo, cambiar a:
; opcache.validate_timestamps = 1
; opcache.revalidate_freq = 2

; ========== REDIS (sesiones) ==========
[session]
session.save_handler = redis
session.save_path = "tcp://${REDIS_HOST:-redis}:${REDIS_PORT:-6379}?prefix=MOODLE_SESSION_&database=0"
session.name = MoodleSession
session.use_cookies = 1
session.use_only_cookies = 1
session.cookie_httponly = 1
session.cookie_secure = 1             ; Solo HTTPS
session.cookie_samesite = "Lax"
session.gc_maxlifetime = 7200
session.gc_probability = 1
session.gc_divisor = 100

; ========== MANEJO DE ARCHIVOS TEMPORALES ==========
upload_tmp_dir = /tmp
```

### 4.3 www.conf (PHP-FPM pool)

```ini
; ============================================================
; PHP-FPM pool configuration for Moodle
; Basado en ADR-002: pool dinámico para escalado horizontal
; ============================================================

[www]

user = www-data
group = www-data

; ========== ESCUCHA ==========
listen = 0.0.0.0:9000
listen.backlog = 65535
listen.allowed_clients = 127.0.0.1

; Para socket Unix (más rápido si Nginx está en el mismo contenedor):
; listen = /var/run/php-fpm.sock
; listen.mode = 0660
; listen.owner = www-data
; listen.group = www-data

; ========== POOL DINÁMICO (ADR-002) ==========
pm = dynamic
pm.max_children = ${PHP_MAX_CHILDREN:-10}
pm.start_servers = ${PHP_START_SERVERS:-2}
pm.min_spare_servers = ${PHP_MIN_SPARE_SERVERS:-1}
pm.max_spare_servers = ${PHP_MAX_SPARE_SERVERS:-3}
pm.max_requests = 500               ; Reciclar worker cada N requests
pm.status_path = /php-fpm-status

; ========== TIMEOUTS ==========
request_terminate_timeout = ${PHP_MAX_EXECUTION_TIME:-120}
request_slowlog_timeout = 30        ; Log de slow queries (>30s)
slowlog = /var/log/php/slow.log

; ========== LOGS ==========
catch_workers_output = yes
php_admin_value[error_log] = /var/log/php/fpm-error.log
php_admin_flag[log_errors] = on

; ========== VARIABLES DE ENTORNO ==========
env[MOODLE_DB_HOST] = $MOODLE_DB_HOST
env[MOODLE_DB_NAME] = $MOODLE_DB_NAME
env[MOODLE_DB_USER] = $MOODLE_DB_USER
env[MOODLE_DB_PASS] = $MOODLE_DB_PASS
env[MOODLE_ADMIN_USER] = $MOODLE_ADMIN_USER
env[MOODLE_ADMIN_PASS] = $MOODLE_ADMIN_PASS
env[REDIS_HOST] = $REDIS_HOST
env[REDIS_PORT] = $REDIS_PORT
```

### 4.4 docker-entrypoint.sh

```bash
#!/bin/bash
# ============================================================
# Entrypoint para el contenedor PHP-FPM de Moodle
# Genera config.php desde template + variables de entorno
# ============================================================
set -e

# Validar variables obligatorias
: "${MOODLE_DB_HOST:?Must set MOODLE_DB_HOST}"
: "${MOODLE_DB_NAME:?Must set MOODLE_DB_NAME}"
: "${MOODLE_DB_USER:?Must set MOODLE_DB_USER}"
: "${MOODLE_DB_PASS:?Must set MOODLE_DB_PASS}"
: "${MOODLE_ADMIN_USER:?Must set MOODLE_ADMIN_USER}"
: "${MOODLE_ADMIN_PASS:?Must set MOODLE_ADMIN_PASS}"
: "${REDIS_HOST:?Must set REDIS_HOST}"
: "${REDIS_PORT:?Must set REDIS_PORT}"

# Generar config.php si no existe (primera vez)
if [ ! -f /var/www/html/config.php ]; then
    echo "→ Generando config.php desde template..."

    # Si existe el template, usarlo. Si no, generarlo inline
    if [ -f /var/www/html/config.php.tpl ]; then
        # Sustituir variables en el template
        envsubst < /var/www/html/config.php.tpl > /var/www/html/config.php
    else
        echo "⚠ No se encontró config.php.tpl. Moodle usará su instalación web."
    fi

    echo "✓ config.php generado"
fi

# Verificar que moodledata existe y tiene permisos
mkdir -p /var/www/moodledata
chown -R www-data:www-data /var/www/moodledata
chmod 755 /var/www/moodledata

# Ejecutar el comando principal (php-fpm)
exec "$@"
```

> **IMPORTANTE:** El `envsubst` requiere que el paquete `gettext` esté instalado en Alpine. Agregar `apk add --no-cache gettext` al Dockerfile.

---

## 5. Servicio Redis

### 5.1 Configuración (vía command en docker-compose.yml)

Redis no necesita un archivo de configuración externo. Se configura vía argumentos de línea de comandos en `docker-compose.yml`:

```yaml
services:
  redis:
    image: redis:7-alpine
    command:
      - redis-server
      - --appendonly yes
      - --appendfsync everysec
      - --save 900 1
      - --save 300 10
      - --save 60 10000
      - --maxmemory 256mb
      - --maxmemory-policy allkeys-lru
      - --timeout 300
      - --tcp-keepalive 60
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
```

**Explicación de cada flag:**

| Flag | Propósito |
|------|-----------|
| `--appendonly yes` | Persistencia AOF (Append Only File) |
| `--appendfsync everysec` | Sincronizar cada segundo (balance rendimiento/durabilidad) |
| `--save 900 1` | RDB snapshot si hay ≥1 cambio en 15 min |
| `--save 300 10` | RDB snapshot si hay ≥10 cambios en 5 min |
| `--save 60 10000` | RDB snapshot si hay ≥10000 cambios en 1 min |
| `--maxmemory 256mb` | Límite máximo de memoria |
| `--maxmemory-policy allkeys-lru` | Política de evicción: eliminar claves menos usadas |

### 5.2 Bases de datos Redis (lógicas)

| DB | Propósito | Config en Moodle |
|:--:|-----------|------------------|
| 0 | Sesiones de usuario | `session_redis_database = 0` |
| 1 | Caché de curso | `cache_store_redis_database = 1` |
| 2 | Caché de cadenas/idioma | `cache_store_redis_database = 2` |
| 3 | Caché de consultas SQL | `cache_store_redis_database = 3` |
| 4 | Lock factory | `lock_redis_database = 4` |

---

## 6. Servicio MariaDB

### 6.1 my.cnf

```ini
; ============================================================
; MariaDB configuration for Moodle LMS
; Basado en ADR-005: optimizado para concurrencia multi-tenant
; ============================================================
[mysqld]

; ========== ALMACENAMIENTO ==========
innodb_file_per_table = ON
innodb_buffer_pool_size = 512M          ; 50-70% de RAM disponible
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2      ; Balance rendimiento/durabilidad
innodb_flush_method = O_DIRECT
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000

; ========== CONCURRENCIA ==========
max_connections = 200                    ; Suficiente para PoC local
thread_cache_size = 16
thread_handling = pool-of-threads        ; MariaDB thread pool

; ========== TEMPORALES ==========
tmp_table_size = 64M
max_heap_table_size = 64M

; ========== QUERY CACHE ==========
query_cache_type = 0                     ; Desactivado (obsoleto en 10.11+)
query_cache_size = 0

; ========== MOODLE-SPECIFIC ==========
innodb_lock_wait_timeout = 120
optimizer_switch = 'derived_merge=on'
max_allowed_packet = 64M
wait_timeout = 600
interactive_timeout = 600

; ========== CHARSET ==========
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

; ========== LOGS ==========
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 5                     ; Consultas >5s
log_queries_not_using_indexes = 0       ; Desactivado en PoC para no llenar logs

[client]
default-character-set = utf8mb4

[mysql]
default-character-set = utf8mb4
```

### 6.2 Volumen de inicialización

No se necesita un `init.sql` explícito porque MariaDB crea la base de datos automáticamente con `MYSQL_DATABASE` y `MYSQL_USER` vía variables de entorno. Sin embargo, se puede incluir un `init.sql` opcional para:

- Configurar el charset utf8mb4 por defecto para la base de datos.
- Ajustar el collation.
- Crear índices adicionales si Moodle no los crea automáticamente.

```sql
-- docker/mariadb/init.sql (OPCIONAL)
-- Se ejecuta automáticamente en la primera inicialización

ALTER DATABASE moodle CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Moodle ya crea sus tablas con utf8mb4, pero aseguramos la BD
```

---

## 7. Servicio Mailpit

Mailpit es un servidor SMTP de prueba que captura todos los correos enviados por Moodle y los muestra en una interfaz web. Esencial para desarrollo para verificar emails sin enviarlos realmente.

```yaml
services:
  mailpit:
    image: axllent/mailpit:latest
    container_name: moodleflux-mailpit
    ports:
      - "8025:8025"    # Web UI para ver correos capturados
    networks:
      - backend_net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:8025/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
```

**Config en config.php de Moodle para usar Mailpit:**

```php
$CFG->smtphosts = 'mailpit:1025';    // Puerto SMTP de Mailpit
$CFG->smtpsecure = 'none';
$CFG->smtpauthtype = 'LOGIN';
$CFG->smtpuser = '';
$CFG->smtppass = '';
$CFG->noreplyaddress = 'noreply@moodleflux.local';
```

---

## 8. config.php de Moodle

### 8.1 config.php.tpl (template con envsubst)

Este archivo se guarda como `docker/moodle/config.php.tpl` y el entrypoint genera `moodle/config.php` usando `envsubst`.

```php
<?php
// ============================================================
// MoodleFlux - config.php (generado desde template)
// Basado en ADR-001, ADR-004, ADR-005, ADR-006
// ============================================================

// ========== BASE DE DATOS (ADR-005) ==========
$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = '${MOODLE_DB_HOST}';
$CFG->dbname    = '${MOODLE_DB_NAME}';
$CFG->dbuser    = '${MOODLE_DB_USER}';
$CFG->dbpass    = '${MOODLE_DB_PASS}';
$CFG->prefix    = 'mdl_';
$CFG->dboptions = [
    'dbpersist'  => false,
    'dbsocket'   => false,
    'dbport'     => 3306,
    'dbcollation' => 'utf8mb4_unicode_ci',
    'readonly'   => [],          // Para futuras réplicas de lectura
];

// ========== DIRECTORIOS ==========
$CFG->wwwroot   = '${MOODLE_WWWROOT:-https://localhost}';
$CFG->dataroot  = '/var/www/moodledata';
$CFG->dirroot   = '/var/www/html';
$CFG->libdir    = '/var/www/html/lib';
$CFG->localcachedir = '/tmp/moodle_localcache';   // NO compartido entre workers
$CFG->tempdir   = '/tmp/moodle_temp';
$CFG->cachedir  = '/tmp/moodle_cache';
$CFG->admin     = 'admin';

// ========== SESIONES (Redis - ADR-004) ==========
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host    = '${REDIS_HOST}';
$CFG->session_redis_port    = ${REDIS_PORT};
$CFG->session_redis_database = 0;
$CFG->session_redis_prefix  = 'MOODLE_SESSION_';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;

// ========== CACHÉ (Redis - ADR-004) ==========
// Cache Store 1: Caché de curso (DB 1)
$CFG->cache_store_redis_1 = json_encode([
    'server'   => '${REDIS_HOST}:${REDIS_PORT}',
    'prefix'   => 'cache1_',
    'database' => 1,
]);
// Cache Store 2: Caché de cadenas/idioma (DB 2)
$CFG->cache_store_redis_2 = json_encode([
    'server'   => '${REDIS_HOST}:${REDIS_PORT}',
    'prefix'   => 'cache2_',
    'database' => 2,
]);
// Cache Store 3: Caché de consultas SQL (DB 3)
$CFG->cache_store_redis_3 = json_encode([
    'server'   => '${REDIS_HOST}:${REDIS_PORT}',
    'prefix'   => 'cache3_',
    'database' => 3,
]);

// ========== LOCK FACTORY (Redis - ADR-004) ==========
$CFG->lock_factory = '\\core\\lock\\redis_lock_factory';
$CFG->lock_redis_host = '${REDIS_HOST}';
$CFG->lock_redis_port = ${REDIS_PORT};
$CFG->lock_redis_database = 4;

// ========== CONFIGURACIÓN DEL SITIO ==========
$CFG->siteidentifier = 'MoodleFlux_PoC';
$CFG->sitename = '${MOODLE_SITE_NAME:-MoodleFlux PoC}';
$CFG->lang = '${MOODLE_LANG:-es}';
$CFG->country = 'CO';
$CFG->timezone = '${TZ:-America/Bogota}';

// ========== SEGURIDAD (ADR-006) ==========
$CFG->ssl_encrypt = true;
$CFG->loginhttps = true;                // Login solo por HTTPS
$CFG->cronclionly = true;
$CFG->preventexecpath = true;
$CFG->passwordpolicy = true;
$CFG->minpasswordlength = 8;
$CFG->disableuserimages = false;
$CFG->allowthemechangeonurl = false;
$CFG->rememberusername = 2;             // 2 = obligatorio cookie de sesión

// ========== CORREO (Mailpit) ==========
$CFG->smtphosts = 'mailpit:1025';
$CFG->smtpsecure = 'none';
$CFG->smtpauthtype = 'LOGIN';
$CFG->smtpuser = '';
$CFG->smtppass = '';
$CFG->noreplyaddress = 'noreply@moodleflux.local';

// ========== RENDIMIENTO (ADR-002) ==========
$CFG->pathtophp = '/usr/local/bin/php';
$CFG->pathtodu = '/usr/bin/du';
$CFG->pathtodot = '/usr/bin/dot';       // Para generación de gráficos
$CFG->aspellpath = '/usr/bin/aspell';
$CFG->pathtogs = '/usr/bin/gs';
$CFG->pathtopgit = '/usr/bin/git';
$CFG->cronremotepassword = '';
$CFG->tool_generator_users_password = 'moodleflux2026';

// ========== DEBUG (local - desactivar en producción) ==========
$CFG->debug = (E_ALL & ~E_DEPRECATED & ~E_STRICT);
$CFG->debugdisplay = 0;
$CFG->debugsmtp = 0;
$CFG->perfdebug = 0;
$CFG->langstringcache = true;

// ========== MULTI-TENENCIA (ADR-003) ==========
// No requiere configuración en config.php
// Se implementa vía Categorías + Cohorts + Roles desde la UI

// ========== PLUGINS ==========
$CFG->dirroot = '/var/www/html';
$CFG->local_tenant_isolation_enabled = false;  // Habilitar cuando se desarrolle el plugin

// ========== SAL DE SEGURIDAD ==========
$CFG->passwordsaltmain = '${MOODLE_PASSWORD_SALT:-changeme_in_production}';

// ========== VERSIÓN DE LA BASE DE DATOS (NO TOCAR) ==========
require_once(__DIR__ . '/lib/setup.php');
```

---

## 9. .env.example

```bash
# ============================================================
# MoodleFlux - Variables de Entorno
# Copiar a .env y ajustar antes de ejecutar docker compose up
# ============================================================

# ---- Proyecto ----
COMPOSE_PROJECT_NAME=moodleflux
TZ=America/Bogota

# ---- Base de Datos ----
MOODLE_DB_HOST=mariadb
MOODLE_DB_NAME=moodle
MOODLE_DB_USER=moodle
MOODLE_DB_PASS=moodle_secret_2026
MYSQL_ROOT_PASSWORD=root_secret_2026

# ---- Redis ----
REDIS_HOST=redis
REDIS_PORT=6379

# ---- Administrador de Moodle ----
MOODLE_ADMIN_USER=admin
MOODLE_ADMIN_PASS=Admin_2026!
MOODLE_SITE_NAME=MoodleFlux PoC
MOODLE_LANG=es

# ---- Web ----
MOODLE_WWWROOT=https://localhost

# ---- PHP ----
PHP_MEMORY_LIMIT=256M
PHP_MAX_EXECUTION_TIME=120
PHP_MAX_CHILDREN=10
PHP_START_SERVERS=2
PHP_MIN_SPARE_SERVERS=1
PHP_MAX_SPARE_SERVERS=3

# ---- Seguridad ----
MOODLE_PASSWORD_SALT=changeme_in_production_$(openssl rand -hex 32)

# ---- Moodle Source (para scripts de setup) ----
MOODLE_VERSION=MOODLE_500_STABLE
MOODLE_REPO=https://github.com/moodle/moodle.git
```

---

## 10. Scripts de inicialización

### 10.1 setup.sh (para el desarrollador)

Script único que prepara el entorno desde cero:

```bash
#!/bin/bash
# ============================================================
# setup.sh - Preparación del entorno MoodleFlux
# Uso: bash scripts/setup.sh
# ============================================================
set -euo pipefail

echo "=== MoodleFlux Setup ==="

# 1. Validar requisitos
echo "→ Verificando requisitos..."
command -v docker >/dev/null 2>&1 || { echo "ERROR: Docker no está instalado"; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo "ERROR: Docker Compose no está instalado"; exit 1; }

# 2. Crear .env si no existe
if [ ! -f .env ]; then
    echo "→ Creando .env desde .env.example..."
    cp .env.example .env
    # Generar salt aleatorio
    sed -i "s/changeme_in_production.*/changeme_in_production_$(openssl rand -hex 32)/" .env
    echo "⚠  .env creado. REVISA y ajusta las contraseñas antes de continuar."
    exit 0
fi

# 3. Crear directorios necesarios
echo "→ Creando directorios..."
mkdir -p moodle moodledata docker/nginx/conf.d docker/php-fpm docker/mariadb docker/moodle scripts

# 4. Clonar Moodle si no existe
if [ ! -d "moodle/.git" ]; then
    echo "→ Clonando Moodle ${MOODLE_VERSION:-MOODLE_500_STABLE}..."
    git clone --depth 1 --branch ${MOODLE_VERSION:-MOODLE_500_STABLE} \
        ${MOODLE_REPO:-https://github.com/moodle/moodle.git} moodle/
else
    echo "→ Moodle ya existe. Actualizando..."
    cd moodle && git pull && cd ..
fi

# 5. Generar certificados SSL locales
echo "→ Generando certificados SSL autofirmados..."
mkdir -p docker/nginx/ssl
if [ ! -f docker/nginx/ssl/moodleflux.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout docker/nginx/ssl/moodleflux.key \
        -out docker/nginx/ssl/moodleflux.crt \
        -subj "/CN=localhost/O=MoodleFlux/C=CO"
fi

# 6. Generar config.php
echo "→ Generando config.php..."
source .env
envsubst < docker/moodle/config.php.tpl > moodle/config.php

# 7. Construir y arrancar
echo "→ Construyendo imágenes..."
docker compose build

echo "→ Arrancando contenedores..."
docker compose up -d

echo "=== Setup completado ==="
echo "→ Web: https://localhost"
echo "→ Mailpit UI: http://localhost:8025"
echo "→ Admin: ${MOODLE_ADMIN_USER:-admin} / ${MOODLE_ADMIN_PASS:-Admin_2026!}"
echo ""
echo "⚠  El primer arranque puede tardar. Ejecuta 'docker compose logs -f' para monitorear."
echo "⚠  Acepta el certificado autofirmado en tu navegador."
```

### 10.2 health.php (endpoint de salud para Nginx)

Este script PHP debe crearse en `moodle/health.php` para que Nginx pueda verificar el estado del sistema:

```php
<?php
// ============================================================
// MoodleFlux - Health Check Endpoint
// Basado en ADR-008: verifica PHP-FPM, Redis, MariaDB, moodledata
// ============================================================
header('Content-Type: application/json');
header('Cache-Control: no-cache, must-revalidate');

$status = 'OK';
$httpCode = 200;
$checks = [];

// 1. Verificar PHP-FPM
$checks['php-fpm'] = [
    'status' => 'healthy',
    'php_version' => PHP_VERSION,
];

// 2. Verificar Redis
try {
    $redis = new Redis();
    $redis->connect(getenv('REDIS_HOST') ?: 'redis', (int)(getenv('REDIS_PORT') ?: 6379), 3);
    $info = $redis->info('stats');
    $checks['redis'] = [
        'status' => 'healthy',
        'connected_clients' => (int)($redis->info('clients')['connected_clients'] ?? 0),
        'hit_rate_pct' => isset($info['keyspace_hits'], $info['keyspace_misses'])
            ? round(($info['keyspace_hits'] / max(1, $info['keyspace_hits'] + $info['keyspace_misses'])) * 100, 1)
            : 0,
    ];
    $redis->close();
} catch (Exception $e) {
    $checks['redis'] = ['status' => 'unhealthy', 'error' => $e->getMessage()];
    $status = 'DEGRADED';
    $httpCode = 503;
}

// 3. Verificar MariaDB
try {
    $mysqli = new mysqli(
        getenv('MOODLE_DB_HOST') ?: 'mariadb',
        getenv('MOODLE_DB_USER') ?: 'moodle',
        getenv('MOODLE_DB_PASS') ?: '',
        getenv('MOODLE_DB_NAME') ?: 'moodle',
        3306
    );
    if ($mysqli->connect_error) {
        throw new Exception($mysqli->connect_error);
    }
    $result = $mysqli->query("SELECT VERSION() as version");
    $row = $result->fetch_assoc();
    $result2 = $mysqli->query("SHOW STATUS LIKE 'Threads_connected'");
    $row2 = $result2->fetch_assoc();
    $checks['mariadb'] = [
        'status' => 'healthy',
        'version' => $row['version'],
        'connections' => (int)$row2['Value'],
    ];
    $mysqli->close();
} catch (Exception $e) {
    $checks['mariadb'] = ['status' => 'unhealthy', 'error' => $e->getMessage()];
    $status = 'DEGRADED';
    $httpCode = 503;
}

// 4. Verificar moodledata
$moodledata = '/var/www/moodledata';
$checks['moodledata'] = [
    'status' => is_dir($moodledata) && is_writable($moodledata) ? 'healthy' : 'unhealthy',
    'disk_usage_pct' => round(disk_free_space($moodledata) / max(1, disk_total_space($moodledata)) * 100, 1),
];

// Respuesta
http_response_code($httpCode);
echo json_encode([
    'status' => $status,
    'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
    'checks' => $checks,
], JSON_PRETTY_PRINT);
```

> Este archivo DEBE ir en `moodle/health.php` (dentro del core de Moodle, pero no es parte del core — es un archivo propio).

---

## 11. Scripts operativos

### 11.1 backup.sh

```bash
#!/bin/bash
# ============================================================
# backup.sh - Backup de base de datos + moodledata
# Uso: bash scripts/backup.sh [output_dir]
# ============================================================
set -euo pipefail

BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/moodle_${TIMESTAMP}"

mkdir -p "${BACKUP_PATH}"

echo "=== MoodleFlux Backup ==="
echo "→ Directorio: ${BACKUP_PATH}"

# 1. Backup de MariaDB
echo "→ Respaldando base de datos..."
source .env 2>/dev/null || true
docker compose exec -T mariadb mariadb-dump \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    -u "${MOODLE_DB_USER:-moodle}" \
    -p"${MOODLE_DB_PASS}" \
    "${MOODLE_DB_NAME:-moodle}" \
    | gzip > "${BACKUP_PATH}/database.sql.gz"
echo "✓ Base de datos respaldada"

# 2. Backup de moodledata
echo "→ Respaldando moodledata..."
# Asumiendo que moodledata está en ./moodledata en el host
docker run --rm -v moodleflux_moodledata:/source -v "${BACKUP_PATH}:/dest" alpine \
    tar czf /dest/moodledata.tar.gz -C /source .
echo "✓ moodledata respaldado"

# 3. Backup de config.php (contiene secrets)
echo "→ Respaldando config.php..."
cp moodle/config.php "${BACKUP_PATH}/config.php" 2>/dev/null || true

# 4. Limpiar backups antiguos (>7 días)
echo "→ Limpiando backups antiguos..."
find "${BACKUP_DIR}" -name "moodle_*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

# 5. Resumen
echo "=== Backup completado ==="
ls -lh "${BACKUP_PATH}/"
```

### 11.2 restore.sh

```bash
#!/bin/bash
# ============================================================
# restore.sh - Restaurar backup de MoodleFlux
# Uso: bash scripts/restore.sh <backup_dir>
# ============================================================
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
echo "→ Restaurando desde: ${BACKUP_PATH}"

source .env 2>/dev/null || true

# 1. Detener servicios que dependen de la BD
echo "→ Deteniendo PHP-FPM..."
docker compose stop php-fpm

# 2. Restaurar base de datos
if [ -f "${BACKUP_PATH}/database.sql.gz" ]; then
    echo "→ Restaurando base de datos..."
    gunzip -c "${BACKUP_PATH}/database.sql.gz" | \
        docker compose exec -T mariadb \
        mariadb -u "${MOODLE_DB_USER:-moodle}" \
        -p"${MOODLE_DB_PASS}" \
        "${MOODLE_DB_NAME:-moodle}"
    echo "✓ Base de datos restaurada"
fi

# 3. Restaurar moodledata
if [ -f "${BACKUP_PATH}/moodledata.tar.gz" ]; then
    echo "→ Restaurando moodledata..."
    docker run --rm -v moodleflux_moodledata:/dest -v "${BACKUP_PATH}:/source" alpine \
        tar xzf /source/moodledata.tar.gz -C /dest
    echo "✓ moodledata restaurado"
fi

# 4. Restaurar config.php
if [ -f "${BACKUP_PATH}/config.php" ]; then
    echo "→ Restaurando config.php..."
    cp "${BACKUP_PATH}/config.php" moodle/config.php
    echo "✓ config.php restaurado"
fi

# 5. Reanudar servicios
echo "→ Reanudando PHP-FPM..."
docker compose start php-fpm

echo "=== Restauración completada ==="
```

### 11.3 Escalado para pruebas de carga

Para ejecutar pruebas de carga con k6 (ADR-002):

```bash
# Escalar a 3 workers PHP-FPM
docker compose up -d --scale php-fpm=3

# Ejecutar prueba de carga (k6 debe estar instalado)
k6 run --vus 50 --duration 60s docs/reference/operations/03-k6-scripts-reference.md

# Monitorear
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

# Volver a 1 worker
docker compose up -d --scale php-fpm=1
```

---

## 12. Instrucciones de uso para el desarrollador

### 12.1 Quick Start

```bash
# 1. Clonar repositorio
git clone https://github.com/Brandon0304/MoodleFlux.git
cd MoodleFlux

# 2. Ejecutar setup (crea .env, clona Moodle, genera certs, arranca)
bash scripts/setup.sh

# 3. Abrir navegador en https://localhost
#    Aceptar certificado autofirmado
#    Usar admin / Admin_2026! (o las credenciales en .env)
```

### 12.2 Comandos diarios

```bash
# Arrancar
docker compose up -d

# Escalar workers (prueba de carga)
docker compose up -d --scale php-fpm=3

# Logs
docker compose logs -f nginx
docker compose logs -f php-fpm

# Health check
curl -sk https://localhost/health | jq .

# Backup
bash scripts/backup.sh

# Restore
bash scripts/restore.sh ./backups/moodle_20260101_120000

# Detener
docker compose down

# Detener y eliminar volúmenes (¡pérdida de datos!)
docker compose down -v
```

### 12.3 Actualizar Moodle

```bash
# 1. Backup
bash scripts/backup.sh

# 2. Detener
docker compose down

# 3. Actualizar código
cd moodle
git fetch origin
git checkout MOODLE_500_STABLE
git pull
cd ..

# 4. Reconstruir y arrancar
docker compose build php-fpm
docker compose up -d

# 5. Ejecutar migración
docker compose exec php-fpm php admin/cli/upgrade.php

# 6. Verificar
docker compose exec php-fpm php admin/cli/checks.php
```

---

## Apéndice A: Checklist de verificación post-implementación

El Build agent debe verificar los siguientes puntos tras implementar todos los archivos:

- [ ] `docker compose config` valida sin errores
- [ ] `docker compose build php-fpm` construye sin errores
- [ ] `docker compose up -d` arranca todos los servicios
- [ ] `docker compose ps` muestra todos los servicios como "healthy"
- [ ] `curl -sk https://localhost/health` devuelve JSON con status "OK"
- [ ] `curl -sk https://localhost` devuelve la página de instalación de Moodle
- [ ] `curl -sk -o /dev/null -w "%{http_code}" https://localhost/health` = 200
- [ ] Mailpit accesible en `http://localhost:8025`
- [ ] Se puede acceder a https://localhost/admin desde el navegador
- [ ] `--scale php-fpm=3` funciona correctamente
- [ ] Backup/restore funcionan
- [ ] Los logs de Nginx están en JSON estructurado

## Apéndice B: Referencias cruzadas con ADRs

| Archivo | ADR(s) aplicados |
|---------|------------------|
| `docker-compose.yml` | ADR-001, ADR-002, ADR-005, ADR-006, ADR-007 |
| `docker/nginx/nginx.conf` | ADR-001, ADR-002, ADR-006, ADR-008 |
| `docker/nginx/conf.d/moodle.conf` | ADR-001, ADR-002, ADR-006 |
| `docker/php-fpm/Dockerfile` | ADR-001, ADR-004 |
| `docker/php-fpm/php.ini` | ADR-001, ADR-002, ADR-004 |
| `docker/php-fpm/www.conf` | ADR-002 |
| `docker/mariadb/my.cnf` | ADR-005 |
| `docker/moodle/config.php.tpl` | ADR-001, ADR-004, ADR-005, ADR-006 |
| `moodle/health.php` | ADR-008 |
| `scripts/setup.sh` | ADR-007 |
| `scripts/backup.sh` | ADR-005, ADR-007 |
| `scripts/restore.sh` | ADR-007 |
| `.env.example` | ADR-006, ADR-007 |

---

*Fin del spec. El Build agent debe implementar todos los archivos descritos aquí, siguiendo las configuraciones exactas y las decisiones arquitectónicas documentadas en los ADRs.*
