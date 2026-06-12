# Referencia: Observabilidad, Logs y Métricas

## 1. Estrategia de Observabilidad para Moodle LMS

La observabilidad se divide en 3 pilares:

```
Observabilidad
├── 📝 Logs      → Eventos discretos (errores, accesos, advertencias)
├── 📊 Métricas  → Valores numéricos en el tiempo (CPU, RAM, requests/s)
└── 🔍 Trazas    → Recorrido de una solicitud entre servicios
```

Para una arquitectura reactiva (ADR-002), estos 3 pilares son críticos para:
- Detectar fallos antes de que afecten a usuarios
- Identificar cuellos de botella bajo carga
- Verificar que los mecanismos de resiliencia funcionan

## 2. Logs

### 2.1 Fuentes de Logs

| Fuente | Dónde está | Qué contiene |
|--------|-----------|--------------|
| Nginx access | `docker logs nginx` | IP, ruta, status code, tiempo de respuesta, user agent |
| Nginx error | `docker logs nginx` | Errores de conexión, timeouts, upstream failures |
| PHP-FPM | `docker logs php-fpm` | Errores PHP, slow logs, pool saturation |
| Moodle app | Admin → Reports → Logs | Actividad de usuarios, eventos, errores de plugin |
| Moodle cron | Admin → Reports → Cron | Tareas programadas, errores de ejecución |
| MariaDB | `docker logs mariadb` | Errores de conexión, slow queries, deadlocks |
| MariaDB slow | `docker logs mariadb` | Consultas que exceden `long_query_time` |
| Redis | `docker logs redis` | Errores de conexión, OOM, keyspace events |

### 2.2 Logs Estructurados (Recomendación)

Para facilitar la búsqueda y análisis, usar formato JSON en los logs:

```nginx
# Nginx - Formato JSON
log_format json_log escape=json '{'
  '"time":"$time_iso8601",'
  '"remote_addr":"$remote_addr",'
  '"request":"$request",'
  '"status":$status,'
  '"body_bytes":$body_bytes_sent,'
  '"request_time":$request_time,'
  '"upstream_addr":"$upstream_addr",'
  '"upstream_response_time":"$upstream_response_time",'
  '"http_user_agent":"$http_user_agent"'
  '}';

access_log /var/log/nginx/access.log json_log;
```

### 2.3 Rotación de Logs

```bash
# logrotate configuration (host)
cat > /etc/logrotate.d/moodle-docker << 'EOF'
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

## 3. Métricas

### 3.1 Métricas Clave por Servicio

#### Nginx
| Métrica | Qué mide | Umbral de alerta |
|---------|----------|:----------------:|
| `nginx_connections_active` | Conexiones activas totales | > 1024 |
| `nginx_requests_per_second` | Throughput | > 500 |
| `nginx_upstream_status_5xx` | Errores del backend | > 1% |
| `nginx_upstream_response_time` | Tiempo de respuesta PHP-FPM | p99 > 2s |

#### PHP-FPM
| Métrica | Qué mide | Umbral de alerta |
|---------|----------|:----------------:|
| `php_fpm_active_connections` | Workers ocupados | > 80% de max_children |
| `php_fpm_max_children_reached` | Workers agotados (pico) | > 0 |
| `php_fpm_slow_requests` | Requests lentos | > 10/min |

#### MariaDB
| Métrica | Qué mide | Umbral de alerta |
|---------|----------|:----------------:|
| `mysql_connections_active` | Conexiones activas | > 150 |
| `mysql_slow_queries` | Queries lentas | > 5/min |
| `mysql_innodb_deadlocks` | Deadlocks | > 0 |
| `mysql_questions_per_second` | Throughput de queries | N/A (referencia) |

#### Redis
| Métrica | Qué mide | Umbral de alerta |
|---------|----------|:----------------:|
| `redis_used_memory` | Memoria usada | > 80% de maxmemory |
| `redis_hit_rate` | Tasa de aciertos de caché | < 80% |
| `redis_connected_clients` | Clientes conectados | > 50 |
| `redis_keyspace_misses` | Fallos de caché | > 100/s |

#### Docker
| Métrica | Qué mide | Umbral de alerta |
|---------|----------|:----------------:|
| `docker_container_cpu` | CPU por contenedor | > 80% sostenido |
| `docker_container_memory` | RAM por contenedor | > 90% de mem_limit |
| `docker_container_restarts` | Reinicios de contenedor | > 3/hora |

### 3.2 Stack de Métricas (Recomendación Futura)

```
Moodle ──→ Nginx ──→ PHP-FPM ──→ Redis ──→ MariaDB
                                    │
                    ┌───────────────┴────────────────┐
                    ▼                                ▼
              Prometheus (métricas)            Grafana (dashboard)
                    │
                    ▼
              Alertmanager → Slack/Email
```

Para la prueba local, el monitoreo se hace con:

```bash
# Comandos manuales
docker stats                              # CPU/RAM de todos los contenedores
docker compose logs --tail=50 -f php-fpm  # Logs en tiempo real
redis-cli info stats                      # Métricas de Redis
mariadb-admin status                      # Estado de MariaDB
```

## 4. Alertas Recomendadas

| Alerta | Condición | Canal | Prioridad |
|--------|-----------|-------|:---------:|
| MariaDB caído | Health check falla 3 veces | Email + Slack | 🔴 Crítica |
| Redis caído | Health check falla 3 veces | Email + Slack | 🔴 Crítica |
| PHP-FPM pool agotado | max_children_reached > 0 | Slack | 🟡 Alta |
| Disco moodledata lleno | Uso > 85% | Email | 🟡 Alta |
| Tasa de error HTTP > 5% | Status 5xx > 5% en 5 min | Slack | 🟡 Alta |
| Slow queries | > 10 slow queries/min | Slack | 🟢 Media |
| Caché Redis hit rate bajo | hit_rate < 70% | Slack | 🟢 Media |

## 5. Salud del Sistema (Health Check Endpoints)

### Endpoint Propuesto: `GET /health`

```json
{
  "status": "OK",
  "timestamp": "2026-06-12T12:00:00Z",
  "checks": {
    "nginx": "healthy",
    "php-fpm": {
      "status": "healthy",
      "workers_active": 12,
      "workers_idle": 8,
      "max_children": 50
    },
    "redis": {
      "status": "healthy",
      "connected_clients": 5,
      "used_memory_mb": 45,
      "hit_rate_pct": 92
    },
    "mariadb": {
      "status": "healthy",
      "connections": 15,
      "uptime_seconds": 3600
    },
    "moodledata": {
      "status": "healthy",
      "disk_usage_pct": 42
    }
  },
  "version": "1.0.0"
}
```

Este endpoint permite a Docker Compose (health checks), k6 (pre-test check) y cualquier monitor externo verificar que el sistema está operativo.

## 6. Dashboard Recomendado (Grafana)

Cuando se implemente Prometheus + Grafana, las pantallas recomendadas son:

| Dashboard | Propósito |
|-----------|-----------|
| **Resumen Moodle** | Estado general: todos los servicios OK/FAIL, uptime, alerts activas |
| **Rendimiento Web** | Tiempo de respuesta Nginx, throughput, errores HTTP |
| **PHP-FPM Pool** | Workers activos/idle, max_children, slow requests |
| **Base de Datos** | Conexiones, slow queries, deadlocks, tamaño de BD |
| **Redis** | Hit rate, memoria usada, keys por DB, clientes |
| **Multi-Tenant** | Usuarios/curso/actividad por tenant (desde Moodle DB) |

## Referencias
- https://prometheus.io/docs/introduction/overview/
- https://grafana.com/docs/grafana/latest/
- https://docs.docker.com/config/daemon/prometheus/
- https://nginx.org/en/docs/http/ngx_http_stub_status_module.html
- https://mariadb.com/kb/en/mariadb-documentation/
