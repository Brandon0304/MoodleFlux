# Referencia: Configuración de Redis para Moodle

## Sesiones en Redis

```php
// En config.php
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = 'redis';              // Hostname del contenedor
$CFG->session_redis_port = 6379;
$CFG->session_redis_database = 0;                 // Base de datos Redis
$CFG->session_redis_prefix = 'MOODLE_SESSION_';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;
```

## Caché de Aplicación en Redis

Moodle maneja múltiples "almacenes de caché". Para Redis se configuran:

```
Admin → Plugins → Caching → Configuration → Redis → Add instance
```

Recomendación de bases de datos Redis dedicadas:

| Propósito | DB Redis | TTL | Prefijo |
|-----------|----------|-----|---------|
| Sesiones | 0 | 2h | `MOODLE_SESSION_` |
| Caché general | 1 | 24h | `cache_` |
| Caché de curso | 2 | 1h | `cache_course_` |
| Locks | 4 | N/A | `lock_` |

## Locks en Redis

```php
// En config.php
$CFG->lock_factory = '\core\lock\redis_lock_factory';
$CFG->lock_redis_host = 'redis';
$CFG->lock_redis_port = 6379;
$CFG->lock_redis_database = 4;
```

## Comandos Útiles de Redis

```bash
# Monitorear sesiones activas
redis-cli keys 'MOODLE_SESSION_*' | wc -l

# Ver TTL de una sesión
redis-cli ttl MOODLE_SESSION_abc123

# Limpiar toda la caché (NO en producción sin cuidado)
redis-cli -n 1 flushdb

# Monitorear comandos en tiempo real
redis-cli monitor

# Ver uso de memoria
redis-cli info memory
```

## Redis Cluster (para alta disponibilidad futura)

Moodle soporta Redis Cluster desde la versión 4.x. Configuración:

```php
// Para Redis Cluster
$CFG->session_redis_host = 'redis-node-1:6379,redis-node-2:6379,redis-node-3:6379';
$CFG->session_redis_port = 6379;  // No usado en cluster
$CFG->session_redis_type = 'cluster';
```

## Referencias
- https://docs.moodle.org/en/Redis_cache_store
- https://docs.moodle.org/en/Session_handling
- https://redis.io/docs/management/persistence/
