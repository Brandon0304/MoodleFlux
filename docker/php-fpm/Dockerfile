# =============================================================================
# Dockerfile para PHP-FPM con Moodle LMS
# Basado en: ADR-001 (PHP 8.3), ADR-004 (Redis)
# =============================================================================

FROM php:8.3-fpm-alpine AS base

LABEL maintainer="MoodleFlux Architecture"
LABEL description="PHP-FPM container for Moodle LMS with Redis, intl, and database extensions"

ARG WWW_DATA_UID=1000

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
        gettext \
        mariadb-client \
        openssl \
    ;

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
    pecl install redis; \
    docker-php-ext-enable redis; \
    apk del .build-deps; \
    rm -rf /var/cache/apk/* /tmp/*

COPY php.ini /usr/local/etc/php/conf.d/moodle-php.ini
COPY www.conf /usr/local/etc/php-fpm.d/www.conf

RUN set -eux; \
    mkdir -p /var/www/moodledata /var/www/html /var/log/php; \
    chown -R www-data:www-data /var/www; \
    chmod 755 /var/www

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
