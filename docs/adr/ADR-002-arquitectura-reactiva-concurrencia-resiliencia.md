# ADR-002: Arquitectura Reactiva — Estrategia de Concurrencia y Resiliencia

## Estado
**Aceptado**

## Contexto
Moodle LMS es una aplicación PHP monolitica que, por defecto, maneja las solicitudes de forma síncrona: cada petición ocupa un proceso PHP hasta que finaliza. En escenarios de alta demanda (cientos o miles de estudiantes concurrentes), este modelo presenta problemas:

- Agotamiento del pool de procesos PHP.
- Sesiones almacenadas en archivos locales (imposible compartir entre workers).
- Bloqueo de la base de datos bajo consultas concurrentes.
- Sin mecanismos de recuperación automática ante fallos.

Se requiere una arquitectura reactiva que cumpla con los principios del [Manifiesto Reactivo](https://www.reactivemanifesto.org/):
1. **Responsive**: responder rápidamente bajo carga.
2. **Resilient**: auto-recuperarse ante fallos parciales.
3. **Elastic**: escalar horizontalmente según demanda.
4. **Message-driven**: comunicación asíncrona entre componentes vía eventos/colas.

## Opciones consideradas

### Opción A: Escalado vertical (monolito grande)
- **Pros:** Simple de configurar, sin cambios arquitectónicos.
- **Contras:** Límite de recursos de una máquina; punto único de fallo; no hay elasticidad real; sesiones en archivo no escalan.

### Opción B: Arquitectura reactiva multi-capa con Nginx + PHP-FPM pool + Redis + health checks + autoescalado
- **Pros:**
  - Nginx maneja concurrencia con modelo event-loop (no bloqueante).
  - PHP-FPM con `pm = dynamic` ajusta workers según demanda.
  - Redis centraliza sesiones: cualquier worker atiende cualquier sesión.
  - Health checks permiten recuperación automática de contenedores.
  - Escalado horizontal: añadir más réplicas de PHP-FPM.
- **Contras:**
  - Complejidad operativa mayor.
  - Se requiere volumen compartido para moodledata (NFS o similar).
  - Las tareas largas (ej. backups, generación de reportes) deben delegarse a colas asíncronas.

### Opción C: Moodle con RoadRunner / Swoole (PHP persistente)
- **Pros:** PHP en memoria (no arranca/finaliza en cada request); rendimiento extremo.
- **Contras:** Incompatible con Moodle sin modificaciones profundas del core; Moodle usa muchas variables globales/estáticas que asumen ciclo request-response.

## Decisión
Se elige la **Opción B: Arquitectura reactiva multi-capa**, implementada con los siguientes patrones:

### 1. Estrategia de Concurrencia

| Capa | Mecanismo | Configuración clave |
|------|-----------|---------------------|
| **Nginx** | Proxy inverso event-driven | `worker_processes auto; worker_connections 4096;` |
| **PHP-FPM** | Pool dinámico de workers | `pm = dynamic; pm.max_children = 50; pm.start_servers = 5; pm.max_spare_servers = 10` |
| **Redis** | Sesiones + Caché persistente | `timeout 300; tcp-keepalive 60` |
| **MariaDB** | Pool de conexiones + query cache | `max_connections = 200; thread_cache_size = 8` |

### 2. Patrones de Resiliencia

```
┌────────────┐     health check     ┌──────────────┐
│  Cliente   │─────:80/health─────▶  │   Nginx      │
└────────────┘     (liveness)        │  (active)    │
                                     └──────┬───────┘
                                            │
                                     ┌──────▼───────┐
                                     │  PHP-FPM     │
                                     │  Pool (xN)   │
                                     └──────┬───────┘
                                            │
                          ┌─────────────────┼─────────────────┐
                          ▼                 ▼                  ▼
                    ┌──────────┐     ┌──────────┐      ┌──────────┐
                    │  Redis   │     │ MariaDB  │      │ moodle   │
                    │ (cluster)│     │ (primary)│      │  data    │
                    └──────────┘     └──────────┘      │ (shared) │
                                                        └──────────┘
```

#### a) Health checks automáticos
- **Liveness probe:** Nginx expone `GET /health` → PHP-FPM verifica conexión a DB y Redis.
- **Readiness probe:** Nginx verifica que PHP-FPM acepte conexiones antes de enviarle tráfico.
- Docker Compose `restart: unless-stopped` con `healthcheck` en cada servicio.

#### b) Circuit Breaker para servicios externos
- Si Redis no responde → Moodle cae a caché de archivos temporal.
- Si MariaDB falla → Moodle muestra página de error transitorio (503).
- Tiempo de espera (timeout) configurado en cada conexión externa.

#### c) Timeouts explícitos
- Nginx: `proxy_read_timeout 120s; proxy_connect_timeout 10s;`
- PHP-FPM: `request_terminate_timeout 120s`
- Redis: `timeout 300`

### 3. Estrategia de Escalado Local

Para la prueba local con Docker Compose, el escalado se logra mediante:

```yaml
# Fragmento conceptual de docker-compose.yml
services:
  nginx:
    image: nginx:1.27-alpine
    ports: ["443:443"]
    depends_on: [php-fpm]

  php-fpm:
    build: ./docker/php-fpm
    # Escalar con: docker compose up -d --scale php-fpm=3
    volumes:
      - moodledata:/var/www/moodledata

  redis:
    image: redis:7-alpine

  mariadb:
    image: mariadb:10.11
```

Para simular alta demanda localmente:
- Ejecutar con `docker compose up -d --scale php-fpm=3` (3 workers).
- Usar **k6** o **Artillery** para generar carga sintética.
- Monitorear con `docker stats` y logs.

### 4. Manejo de Fallos Parciales (Graceful Degradation)

| Falla | Comportamiento esperado |
|-------|------------------------|
| Redis caído | Moodle usa caché de archivos temporal; sesiones vuelven a archivos |
| MariaDB caída | Nginx devuelve 503; Docker reinicia el contenedor |
| Worker PHP-FPM saturado | Nginx pone requests en cola (proxy_next_upstream) |
| Disco lleno (moodledata) | Moodle muestra advertencia, operaciones de escritura fallan |
| Un worker falla | Los demás workers siguen atendiendo sin interrupción |

## Consecuencias

### Positivas
- El sistema responde bajo carga gracias a Nginx + pool dinámico de workers.
- La resiliencia es automática: health checks + restart policies + degradación graceful.
- Las sesiones distribuidas en Redis permiten escalado horizontal real.
- Se puede simular alta demanda localmente con `--scale` y herramientas de carga.
- Base sólida para migrar a orquestación tipo Kubernetes en el futuro.

### Negativas
- La configuración de PHP-FPM debe ajustarse según los recursos de la máquina local.
- El almacenamiento compartido (moodledata) sigue siendo un punto de contención.
- Moodle no está diseñado para async puro; las tareas largas requieren soluciones externas (cron + colas).
- Las pruebas de carga locales están limitadas por el hardware de la máquina anfitriona.

## Referencias
- [The Reactive Manifesto](https://www.reactivemanifesto.org/)
- [Nginx PHP-FPM tuning](https://www.nginx.com/blog/nginx-php-fpm-process-management/)
- [Moodle Performance Recommendations](https://docs.moodle.org/en/Performance_recommendations)
- [Moodle Redis session handler](https://docs.moodle.org/en/Redis_cache_store)
- [k6 Load Testing](https://k6.io/)
