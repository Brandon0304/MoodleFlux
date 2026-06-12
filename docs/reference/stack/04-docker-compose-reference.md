# Referencia: Docker Compose para Moodle LMS

## Estructura Conceptual de Servicios

La arquitectura definida en ADR-001 y ADR-002 se traduce en estos servicios Docker:

```
Servicios:
├── nginx          (proxy inverso, balanceo de carga)
├── php-fpm        (workers de aplicación Moodle)
├── redis          (caché, sesiones, locks)
├── mariadb        (base de datos)
└── mailpit        (SMTP de prueba)
```

## Redes

```yaml
# Conceptual - 2 redes aisladas
networks:
  frontend_net:    # Expuesta al host
    driver: bridge
  backend_net:     # Solo comunicación interna
    driver: bridge
    internal: true  # Sin acceso externo
```

| Red | Acceso desde host | Contenedores |
|-----|:-----------------:|--------------|
| `frontend_net` | ✅ Sí (puertos 443, 80) | nginx |
| `backend_net` | ❌ No | php-fpm, redis, mariadb, mailpit |

## Puertos

| Servicio | Puerto Interno | Puerto Host | Red | Propósito |
|----------|:-------------:|:-----------:|:---:|-----------|
| nginx | 443 | 443 | frontend | HTTPS |
| nginx | 80 | 80 | frontend | HTTP (redirección) |
| php-fpm | 9000 | — | backend | FastCGI interno |
| redis | 6379 | — | backend | Cache/sesiones interno |
| mariadb | 3306 | — | backend | Base de datos interna |
| mailpit | 1025 | — | backend | SMTP interno |
| mailpit | 8025 | — | backend | Web UI interna |

## Volúmenes

| Volumen | Monta en | Propósito |
|---------|----------|-----------|
| `moodle-code` | `/var/www/html` | Código fuente de Moodle (descargado del repo oficial) |
| `moodledata` | `/var/www/moodledata` | Archivos subidos, caché temporal, idiomas |
| `mariadb-data` | `/var/lib/mysql` | Datos persistentes de MariaDB |
| `redis-data` | `/data` | Persistencia de Redis (AOF + RDB) |

## Escalado

### Escalado Horizontal de PHP-FPM

```bash
# Escalar a N workers
docker compose up -d --scale php-fpm=5

# Verificar workers activos
docker compose ps

# Ver logs de todos los workers
docker compose logs --tail=50 php-fpm
```

### Límite de Recursos por Contenedor

```yaml
# Recomendado para evitar que un contenedor consuma todo el host
services:
  mariadb:
    mem_limit: 1g
    cpus: 2
  redis:
    mem_limit: 256m
    cpus: 1
  php-fpm:
    mem_limit: 512m
    cpus: 2
```

## Orden de Arranque (Dependencias)

```
nginx ──→ php-fpm ──→ mariadb
                 ──→ redis
                 ──→ mailpit
```

MariaDB y Redis deben estar listos antes que PHP-FPM. Implementar:

```yaml
# Dependencias
services:
  php-fpm:
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_healthy
```

## Health Checks

```yaml
services:
  mariadb:
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  php-fpm:
    healthcheck:
      test: ["CMD", "php-fpm-healthcheck"]
      interval: 15s
      timeout: 5s
      retries: 3
```

## Ciclo de Vida

```bash
# Iniciar
docker compose up -d

# Ver estado
docker compose ps
docker compose top

# Ver logs en tiempo real
docker compose logs -f

# Escalar workers
docker compose up -d --scale php-fpm=5

# Reiniciar un servicio (ej: después de cambiar config.php)
docker compose restart php-fpm

# Detener (conserva datos)
docker compose stop

# Destruir (pierde datos de contenedores, no volúmenes)
docker compose down

# Destruir todo (incluye volúmenes)
docker compose down -v
```

## Modo Producción vs Desarrollo

| Aspecto | Desarrollo | Producción |
|---------|-----------|------------|
| Volumen código | Bind mount (`./moodle:/var/www/html`) | Copia en imagen |
| Certificado SSL | Autofirmado | Let's Encrypt |
| Límites de recursos | Sin límite | Configurados |
| Logs | stdout interactivo | Rotación de logs |
| Redis persistencia | RDB | AOF + RDB |
| MariaDB | Sin cifrado | Cifrado en reposo |

## Referencias
- https://docs.docker.com/compose/
- https://docs.docker.com/compose/compose-file/
- https://docs.moodle.org/en/Installing_Moodle#Installing_Moodle_with_Docker
