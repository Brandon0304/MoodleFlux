# ADR-004: Estrategia de Caché, Sesiones y Almacenamiento Distribuido

## Estado
**Aceptado**

## Contexto
Moodle LMS, por defecto, utiliza el sistema de archivos local para:
1. **Sesiones de usuario** → almacenadas como archivos PHP en `/tmp/sessions/`.
2. **Caché de aplicación** → almacenada en archivos dentro de `moodledata/cache/`.
3. **Almacenamiento de archivos** → moodledata contiene todos los archivos subidos (tareas, recursos, etc.).

En una arquitectura reactiva con múltiples workers PHP-FPM, esto es problemático:
- Las sesiones en archivo no se comparten entre workers.
- La caché en archivo se pierde o duplica entre contenedores.
- El moodledata debe ser accesible desde cualquier worker.

Se requiere una estrategia de almacenamiento distribuido que soporte escalado horizontal.

## Opciones consideradas

### Opción A: Sesiones en archivo + caché en archivo (default de Moodle)
- **Pros:** Sin configuración adicional; funciona out-of-the-box.
- **Contras:** No escalable; sesiones atadas al worker que las creó; caché volátil en entornos multi-contenedor.

### Opción B: Redis para sesiones + Redis para caché + NFS para moodledata
- **Pros:**
  - Sesiones centralizadas y accesibles desde cualquier worker.
  - Redis es extremadamente rápido (in-memory, ~microsegundos).
  - Moodle soporta Redis de forma nativa para sesiones y caché.
  - Redis Cluster ofrece alta disponibilidad.
  - NFS permite compartir moodledata entre N workers.
- **Contras:**
  - Redis es un punto único de fallo si no se clusteriza (mitigable con Redis Sentinel/Cluster).
  - NFS introduce latencia de red en operaciones de archivos.
  - Configuración adicional en `config.php` de Moodle (tocar archivo de configuración).

### Opción C: Redis para sesiones + Memcached para caché + S3/MinIO para moodledata
- **Pros:**
  - Memcached es más simple (solo caché, sin persistencia).
  - S3/MinIO ofrece almacenamiento de objetos escalable sin NFS.
- **Contras:**
  - Dos sistemas de caché diferentes aumentan complejidad operativa.
  - Moodle no soporta S3 nativamente para moodledata (requiere plugin `local_aws` o similar).
  - Más latencia que NFS para operaciones de lectura/escritura frecuentes.

## Decisión
Se elige la **Opción B: Redis para sesiones + Redis para caché + NFS/volumen compartido para moodledata**. Redis centraliza tanto sesiones como caché de aplicación, simplificando la arquitectura.

### Estrategia de Caché

#### 1. Sesiones de Usuario (Redis)

```
Config en config.php:
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = 'redis';       // hostname del contenedor Redis
$CFG->session_redis_port = 6379;
$CFG->session_redis_database = 0;          // base de datos Redis 0
$CFG->session_redis_prefix = 'sess_';      // prefijo para identificar sesiones
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;
```

**Comportamiento:**
- Las sesiones se almacenan en Redis en lugar del sistema de archivos.
- Cualquier worker PHP-FPM puede atender cualquier sesión.
- TTL automático: las sesiones expiran tras el tiempo de inactividad configurado.
- Redis Lock garantiza escritura segura en sesiones concurrentes.

#### 2. Caché de Aplicación (Redis)

Moodle soporta múltiples "almacenes de caché" (cache stores). Se configuran 3 stores:

| Store | Propósito | TTL | Redis DB |
|-------|-----------|-----|----------|
| **Cache Store 1** | Caché de curso (course data) | 1 hora | DB 1 |
| **Cache Store 2** | Caché de cadenas/idioma (strings) | 24 horas | DB 2 |
| **Cache Store 3** | Caché de consultas SQL | 30 minutos | DB 3 |

Config en config.php (vía admin UI o directamente):
```
// Definir stores:
$CFG->cache_store_redis_1 = '{"server":"redis:6379","prefix":"cache1_","database":1}';
$CFG->cache_store_redis_2 = '{"server":"redis:6379","prefix":"cache2_","database":2}';
$CFG->cache_store_redis_3 = '{"server":"redis:6379","prefix":"cache3_","database":3}';
```

#### 3. Caché Local (archivos temporales por pod)

Cada worker PHP-FPM necesita un directorio de caché local para archivos temporales:

```
$CFG->localcachedir = '/tmp/moodle_localcache';
```

Este directorio NO se comparte entre workers. Contiene:
- Plantillas compiladas (mustache).
- Archivos CSS/JS combinados.
- Datos de sesión temporales.

### Estrategia de Almacenamiento de Archivos (moodledata)

#### Volumen Compartido

```
moodledata/              ← Volumen Docker compartido entre todos los workers
├── filedir/             ← Archivos subidos (organizados por hash)
├── cache/               ← NO USAR (desactivado, se usa Redis)
├── sessions/            ← NO USAR (desactivado, se usa Redis)
├── temp/                ← Archivos temporales compartidos
│   └── backup/          ← Backups de cursos
├── trashdir/            ← Archivos eliminados (en cuarentena)
├── repository/          ← Archivos del repositorio
└── lang/                ← Paquetes de idioma descargados
```

**Recomendación de almacenamiento local (Docker):**
- Usar un **volumen Docker con driver local** montado en `moodledata`.
- Para la prueba local, un bind mount a un directorio del host.

**Mirando hacia futuro (escalado real):**
- Para entornos multi-nodo, reemplazar el volumen local por **NFS** o **EFS (AWS)**.
- Evaluar plugins como `local_objectfs` para migrar a S3/MinIO en fases posteriores.

### Configuración completa de Redis

```yaml
# Configuración conceptual de Redis
redis:
  image: redis:7-alpine
  command: >
    redis-server
    --appendonly yes
    --appendfsync everysec
    --save 900 1
    --save 300 10
    --save 60 10000
    --maxmemory 256mb
    --maxmemory-policy allkeys-lru
    --timeout 300
    --tcp-keepalive 60
  volumes:
    - redis-data:/data
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
    interval: 10s
    timeout: 3s
    retries: 5
```

### Configuración del config.php de Moodle (secciones relevantes)

```php
// ========== SESIONES (Redis) ==========
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = 'redis';
$CFG->session_redis_port = 6379;
$CFG->session_redis_database = 0;
$CFG->session_redis_prefix = 'MOODLE_SESSION_';

// ========== CACHÉ (Redis) ==========
$CFG->cache_types = [
    'redis' => [
        'server' => 'redis:6379',
        'prefix' => 'cache_',
        'database' => 1,
    ],
];

// ========== ALMACENAMIENTO LOCAL ==========
$CFG->localcachedir = '/tmp/moodle_localcache';
$CFG->dataroot = '/var/www/moodledata';

// ========== BLOQUEO DE ARCHIVOS ==========
// Usar Redis para bloqueo de archivos en lugar del sistema de archivos
$CFG->lock_factory = '\\core\\lock\\redis_lock_factory';
$CFG->lock_redis_host = 'redis';
$CFG->lock_redis_port = 6379;
$CFG->lock_redis_database = 4;
```

## Consecuencias

### Positivas
- Sesiones distribuidas: cualquier worker atiende cualquier request.
- Caché ultrarrápida (Redis in-memory) vs disco.
- Configuración unificada: un solo sistema para sesiones, caché y locks.
- Tolerancia a fallos de workers individuales.
- Base para escalado horizontal real.

### Negativas
- Redis se convierte en dependencia crítica (sin Redis, Moodle no funciona correctamente).
- Consumo de memoria RAM para Redis (estimado: ~256 MB para la prueba).
- La configuración del `config.php` debe mantenerse sincronizada entre despliegues.
- NFS/moodledata compartido tiene latencia de red en operaciones de archivos.
- Para entornos multi-región, Redis debe clusterizarse (complejidad adicional).

## Referencias
- [Moodle Redis session handler docs](https://docs.moodle.org/en/Redis_cache_store)
- [Moodle Session handling](https://docs.moodle.org/en/Session_handling)
- [Moodle Performance recommendations - Caching](https://docs.moodle.org/en/Performance_recommendations#Caching)
- [Redis Persistence](https://redis.io/docs/management/persistence/)
- [Moodle lock factories](https://docs.moodle.org/en/Lock_factories)
