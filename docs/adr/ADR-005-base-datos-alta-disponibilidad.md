# ADR-005: Estrategia de Base de Datos y Alta Disponibilidad

## Estado
**Aceptado**

## Contexto
Moodle LMS depende críticamente de su base de datos para almacenar:
- Usuarios, cursos, matriculaciones, calificaciones, configuraciones.
- Contenido de actividades (foros, tareas, quizzes, etc.).
- Logs de actividad, eventos, sesiones (si no se usa Redis).

En una arquitectura reactiva de alta concurrencia, la base de datos es el componente más sensible al cuello de botella. Cada página de Moodle puede generar 10-50 consultas SQL. Con cientos de usuarios concurrentes, la base de datos debe estar optimizada y ser resiliente.

## Opciones consideradas

### Opción A: MariaDB 10.11 (single instance)
- **Pros:**
  - Soportada oficialmente por Moodle desde versiones tempranas.
  - Rendimiento superior a MySQL en consultas concurrentes (optimizador de consultas mejorado).
  - Compatible total con el dialecto SQL de Moodle.
  - Menor consumo de recursos que PostgreSQL en configuraciones por defecto.
  - Docker image oficial y liviana.
- **Contras:**
  - Sin alta disponibilidad incorporada (single point of failure).
  - Las réplicas requieren configuración manual de MariaDB Galera Cluster.
  - La concurrencia extrema puede requerir read replicas.

### Opción B: PostgreSQL 16
- **Pros:**
  - Soportado oficialmente por Moodle.
  - Mejor manejo de consultas complejas y concurrencia (MVCC robusto).
  - Réplicas integradas (streaming replication) más simples que Galera.
  - Mejor rendimiento en cargas de trabajo mixtas (OLTP + analítico).
- **Contras:**
  - Mayor consumo de recursos en configuraciones por defecto.
  - La comunidad Moodle históricamente usa más MySQL/MariaDB.
  - Algunos plugins de terceros pueden tener problemas de compatibilidad.

### Opción C: MariaDB con Galera Cluster (multi-master)
- **Pros:**
  - Alta disponibilidad real: si un nodo cae, los otros siguen.
  - Escritura en múltiples nodos (sin punto único para writes).
  - Sincronización síncrona entre nodos.
- **Contras:**
  - Complejidad operativa significativa para una prueba local.
  - Requiere al menos 3 nodos para split-brain prevention.
  - Mayor latencia de escritura por la replicación síncrona.
  - Consumo de recursos 3x para la prueba local.

## Decisión
Para la **prueba local**, se elige la **Opción A: MariaDB 10.11 en instancia única**, con la configuración de rendimiento optimizada. La alta disponibilidad se aborda a nivel de Docker Compose con health checks y restart policies.

Para una **fase futura de producción**, se evolucionaría a **MariaDB + réplica de lectura** siguiendo el patrón descrito en la sección de evolución.

### Configuración de MariaDB para Alto Rendimiento

```ini
# Fragmento de my.cnf optimizado para Moodle multi-tenant
[mysqld]
# ========== ALMACENAMIENTO ==========
innodb_file_per_table = ON
innodb_buffer_pool_size = 512M        # 50-70% de la RAM disponible
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2    # Equilibrio rendimiento/durabilidad
innodb_flush_method = O_DIRECT

# ========== CONCURRENCIA ==========
max_connections = 200                  # Suficiente para prueba local
thread_cache_size = 16
thread_handling = pool-of-threads     # MariaDB thread pool (mejor que one-thread-per-connection)

# ========== QUERY CACHE ==========
query_cache_type = 0                   # Desactivado en MariaDB 10.11+ (obsoleto, perjudicial en multi-tenant)
query_cache_size = 0

# ========== TEMPORAL ==========
tmp_table_size = 64M
max_heap_table_size = 64M

# ========== MOODLE-SPECIFIC ==========
# Moodle usa transacciones largas en algunas operaciones
innodb_lock_wait_timeout = 120
# Moodle hace muchos COUNT(*) en tablas grandes
optimizer_switch = 'derived_merge=on'
```

### Estrategia de Conexiones desde PHP-FPM

```
PHP-FPM Worker → MariaDB
     (pool)
  Worker 1 ──────┐
  Worker 2 ──────┤
  Worker 3 ──────┼──▶ MariaDB (max_connections=200)
  Worker 4 ──────┤
  Worker N ──────┘

Regla: max_connections(MariaDB) >= max_children(PHP-FPM) + 20 (margen)
Ejemplo: max_children=50 → max_connections=70+
```

### Estrategia de Persistencia y Backups

#### Volumen de Datos
```yaml
services:
  mariadb:
    volumes:
      - mariadb-data:/var/lib/mysql   # Datos persistentes
      - ./docker/mariadb/init.sql:/docker-entrypoint-initdb.d/init.sql  # Seed inicial
```

#### Backup (programado vía cron del host o contenedor separado)
```bash
# Backup diario (conceptual)
docker exec mariadb sh -c 'mariadb-dump --all-databases -u root -p"$MYSQL_ROOT_PASSWORD"' > /backups/moodle_$(date +%Y%m%d).sql
```

#### Restore
```bash
# Restore (conceptual)
cat /backups/moodle_20260101.sql | docker exec -i mariadb sh -c 'mariadb -u root -p"$MYSQL_ROOT_PASSWORD"'
```

### Evolución hacia Alta Disponibilidad (Futuro)

Para cuando se requiera alta disponibilidad real, la arquitectura evolucionaría a:

```
                    ┌──────────────┐
                    │  PHP-FPM     │
                    │  Workers xN  │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ MariaDB  │ │ MariaDB  │ │ MariaDB  │
        │ Primary  │ │ Replica 1│ │ Replica 2│
        │ (Write)  │ │ (Read)   │ │ (Read)   │
        └──────────┘ └──────────┘ └──────────┘
              │
              ▼
        ┌──────────┐
        │ MaxScale │ (balanceador de conexiones)
        └──────────┘
              │
        Read/Write Splitting:
        - Escrituras → Primary
        - Lecturas → Replicas (round-robin)
```

**Configuración de Moodle para réplicas (futuro):**
```php
// config.php para read/write splitting
$CFG->dboptions['readonly'] = [
    'instance' => [
        'moodle_replica_1' => [
            'dbhost' => 'mariadb-replica-1',
            'dbport' => 3306,
            'dbuser' => 'moodle',
            'dbpass' => 'password',
        ],
        'moodle_replica_2' => [
            'dbhost' => 'mariadb-replica-2',
            'dbport' => 3306,
            'dbuser' => 'moodle',
            'dbpass' => 'password',
        ],
    ],
];
```

### Variables de Entorno (Docker Compose)

```yaml
mariadb:
  image: mariadb:10.11
  environment:
    MYSQL_ROOT_PASSWORD: root_password_seguro
    MYSQL_DATABASE: moodle
    MYSQL_USER: moodle
    MYSQL_PASSWORD: moodle_password_seguro
  volumes:
    - mariadb-data:/var/lib/mysql
  healthcheck:
    test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 30s
```

## Consecuencias

### Positivas
- MariaDB 10.11 es estable, rápida y 100% compatible con Moodle.
- La configuración de rendimiento permite manejar cientos de conexiones concurrentes.
- Thread pool de MariaDB evita el overhead de un hilo por conexión.
- Health checks + restart policy proporcionan recuperación automática básica.
- La evolución a réplicas está documentada y lista para implementar.

### Negativas
- Instancia única de base de datos = punto único de fallo (para la fase local es aceptable).
- El buffer pool de 512MB puede ser insuficiente si la base de datos crece mucho.
- La configuración `innodb_flush_log_at_trx_commit=2` sacrifica durabilidad inmediata por rendimiento.
- Sin un balanceador de conexiones (como MaxScale o ProxySQL), el read/write splitting futuro requiere cambios en config.php.

## Referencias
- [Moodle DB requirements](https://docs.moodle.org/en/Installing_Moodle#Database)
- [MariaDB Performance Tuning](https://mariadb.com/kb/en/server-system-variables/)
- [Moodle Performance recommendations - Database](https://docs.moodle.org/en/Performance_recommendations#Database_server)
- [MariaDB Thread Pool](https://mariadb.com/kb/en/thread-pool/)
- [Moodle Read/Write DB connections](https://docs.moodle.org/en/Read_only_databases)
