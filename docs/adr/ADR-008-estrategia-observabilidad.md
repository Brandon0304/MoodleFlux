# ADR-008: Estrategia de Observabilidad y Alertas

## Estado
**Aceptado**

## Contexto
En una arquitectura reactiva (ADR-002), la observabilidad no es opcional: es el mecanismo que permite detectar degradación, validar que los patrones de resiliencia funcionan, y tomar decisiones de escalado informadas. Se requiere:

1. Saber en todo momento si el sistema está operativo (health).
2. Detectar cuellos de botella antes de que afecten a usuarios.
3. Verificar que los mecanismos de resiliencia (ADR-002) se activan correctamente.
4. Tener trazabilidad de eventos para debugging.

## Opciones consideradas

### Opción A: Solo logs de Docker (sin métricas estructuradas)
- **Pros:** Cero configuración adicional, `docker logs` funciona out-of-the-box.
- **Contras:** No hay métricas históricas, no hay alertas proactivas, difícil correlacionar eventos entre servicios.

### Opción B: Stack completo Prometheus + Grafana + Alertmanager
- **Pros:** Métricas históricas, dashboards visuales, alertas configurables, correlación entre servicios.
- **Contras:** Sobrecarga operativa para una prueba de concepto local; Prometheus y Grafana consumen recursos.

### Opción C: Observabilidad híbrida por fases (seleccionada)
Fase 1 (local/PoC): Logs estructurados + health check endpoint + Docker stats
Fase 2 (futuro): Prometheus + Grafana + Alertmanager
- **Pros:** Progresivo, sin sobrecarga inicial, escalable cuando se necesite.
- **Contras:** La Fase 1 no da métricas históricas; requiere trabajo manual para detectar tendencias.

## Decisión
Se implementa la **Opción C: Observabilidad híbrida por fases**.

### Fase 1: Local / Prueba de Concepto (AHORA)

#### 1.1 Health Check Endpoint
Se implementa un endpoint `GET /health` en Nginx que verifica:

```json
{
  "status": "OK",
  "timestamp": "2026-06-12T12:00:00Z",
  "checks": {
    "php-fpm": { "status": "healthy", "workers_active": 12, "workers_idle": 8 },
    "redis": { "status": "healthy", "connected_clients": 5, "hit_rate_pct": 92 },
    "mariadb": { "status": "healthy", "connections": 15, "uptime": 3600 },
    "moodledata": { "status": "healthy", "disk_usage_pct": 42 }
  }
}
```

#### 1.2 Comandos de Monitoreo en Tiempo Real

```bash
# Comandos rápidos para el operador:
alias m-stats='docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"'
alias m-nginx='docker compose logs --tail=20 nginx'
alias m-php='docker compose logs --tail=20 php-fpm'
alias m-db='docker compose exec mariadb mariadb-admin status'
alias m-redis='docker compose exec redis redis-cli info stats | grep instantaneous'
alias m-health='curl -s https://localhost/health | jq .'
```

#### 1.3 Métricas Clave a Monitorear Manualmente

| Métrica | Comando | Frecuencia | Alarma si... |
|---------|---------|:----------:|--------------|
| Workers PHP activos | `m-php \| grep "active"` | Cada 30s en prueba de carga | > 80% de max_children |
| Conexiones MariaDB | `m-db \| grep Connections` | Cada 60s | > 150 |
| Hit rate Redis | `m-redis` | Cada 60s | < 80% |
| Disco moodledata | `df -h /var/www/moodledata` | Diario | > 85% |
| CPU/RAM contenedores | `m-stats` | Cada 30s en prueba de carga | CPU > 80% sostenido |
| Status 5xx Nginx | `m-nginx \| grep " 5[0-9][0-9]"` | Cada 30s | Cualquier 5xx |

### Fase 2: Producción (FUTURO)

```
                    ┌──────────────────────┐
                    │      Moodle LMS       │
                    └──────────┬───────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                 ▼
        ┌──────────┐    ┌──────────┐     ┌──────────┐
        │  Nginx   │    │  Redis   │     │ MariaDB  │
        │  stub    │    │  INFO    │     │  EXPORT  │
        │  status  │    │  stats   │     │          │
        └────┬─────┘    └────┬─────┘     └────┬─────┘
             │               │                │
             ▼               ▼                ▼
        ┌──────────────────────────────────────────┐
        │           Prometheus (métricas)           │
        └────────────────────┬─────────────────────┘
                             │
                             ▼
              ┌─────────────────────────────┐
              │          Grafana             │
              │  Dashboard: Resumen Moodle  │
              │  Dashboard: Rendimiento Web │
              │  Dashboard: Base de Datos   │
              │  Dashboard: Redis           │
              └──────────────┬──────────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  Alertmanager    │
                    │  → Slack/Email   │
                    └──────────────────┘
```

### Decisiones de Configuración

| Aspecto | Decisión |
|---------|----------|
| Formato de logs | JSON estructurado (Nginx access log) |
| Rotación de logs | Logrotate diario, retención 7 días |
| Health check endpoint | `GET /health` en Nginx, verifica todos los servicios |
| Frecuencia de health checks | Cada 10s (Docker health check) |
| Alertas fase 1 | Sin alertas automáticas (monitoreo manual) |
| Alertas fase 2 | Alertmanager: Slack para warnings, Email para críticas |
| Dashboard fase 1 | No hay dashboard gráfico (comandos CLI) |
| Dashboard fase 2 | Grafana con 4 dashboards predefinidos |

### Umbrales de Alerta (para cuando se implemente Fase 2)

| Alerta | Condición | Severidad | Tiempo para escalar |
|--------|-----------|:---------:|:-------------------:|
| MariaDB caído | Health check falla 3x seguidas | 🔴 Crítica | 5 min → email |
| Redis caído | Health check falla 3x seguidas | 🔴 Crítica | 5 min → email |
| PHP pool agotado | max_children_reached > 0 | 🟡 Alta | 10 min → Slack |
| HTTP 5xx > 5% | 5xx / total requests > 5% en 5 min | 🟡 Alta | 10 min → Slack |
| Disco lleno | moodledata > 85% | 🟡 Alta | 1 hora → email |
| Hit rate bajo | Redis hit_rate < 70% en 10 min | 🟢 Media | 30 min → Slack |
| Slow queries | > 10 slow queries/min en 5 min | 🟢 Media | 30 min → Slack |

## Consecuencias

### Positivas
- En fase 1, cero sobrecarga operativa adicional (solo comandos manuales).
- En fase 2, observabilidad completa y profesional.
- Health check endpoint permite a Docker y k6 verificar el estado del sistema.
- Transición gradual: se empieza con CLI y se migra a dashboards sin cambios arquitectónicos.

### Negativas
- Fase 1 no tiene métricas históricas ni alertas automáticas.
- El monitoreo manual durante pruebas de carga requiere atención constante.
- La implementación de Fase 2 (Prometheus + Grafana) requiere contenedores adicionales.
- Los dashboards de Grafana requieren configuración y mantenimiento.

## Referencias
- [ADR-002](./ADR-002-arquitectura-reactiva-concurrencia-resiliencia.md) — Resiliencia y health checks
- [Prometheus](https://prometheus.io/docs/introduction/overview/)
- [Grafana](https://grafana.com/docs/grafana/latest/)
- [Nginx stub status](https://nginx.org/en/docs/http/ngx_http_stub_status_module.html)
- `docs/reference/operations/02-monitoring-setup.md`
- `docs/reference/operations/03-k6-scripts-reference.md`
