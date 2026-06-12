# ADR-001: Stack Tecnológico y Estrategia de Contenerización de Moodle LMS

## Estado
**Aceptado**

## Contexto
Se necesita desplegar Moodle LMS (versión clásica gratuita y open source) en un entorno local basado en contenedores Docker, que sirva como base para:
1. Una prueba de concepto funcional del ecosistema Moodle.
2. Una arquitectura reactiva, resiliente y de alta concurrencia.
3. Un modelo multi-institucional (multi-tenencia) sobre una misma instancia.

Moodle es una aplicación escrita en PHP que tradicionalmente se despliega con Apache + MySQL/MariaDB. Sin embargo, para lograr un comportamiento reactivo y escalable, se requiere repensar cada componente del stack.

## Opciones consideradas

### Opción A: Usar la imagen oficial `moodlehq/moodle-docker` (desarrollo)
- **Pros:**
  - Mantenida por Moodle HQ.
  - Soporte para múltiples bases de datos (PostgreSQL, MariaDB, MySQL, MSSQL, Oracle).
  - Configuración zero-touch para desarrollo.
  - Incluye config.php template para Docker.
- **Contras:**
  - Orientada a desarrollo/pruebas, no a producción.
  - Apache como servidor web (no óptimo para alta concurrencia).
  - Sin Redis preconfigurado para sesiones/caché.
  - Sin capacidad de escalado horizontal de workers.
  - Sin balanceador de carga.

### Opción B: Stack personalizado con Nginx + PHP-FPM + Redis + MariaDB
- **Pros:**
  - Nginx como reverse proxy: manejo eficiente de conexiones concurrentes (event-driven).
  - PHP-FPM permite múltiples workers hijos (pm.max_children configurables).
  - Redis para sesiones distribuidas y caché de aplicación.
  - Separación de contenedores por responsabilidad (single concern).
  - Escalable: se pueden lanzar N réplicas del contenedor webserver.
- **Contras:**
  - Mayor complejidad inicial de configuración.
  - Se debe configurar manualmente el config.php de Moodle para Redis y sesiones.
  - Se requiere un volumen compartido (NFS/S3) para moodledata al escalar horizontalmente.

### Opción C: Bitnami Moodle (imagen empaquetada)
- **Pros:**
  - Imagen todo-en-uno con versiones probadas.
  - Fácil de arrancar con docker-compose Bitnami.
  - Incluye soporte para Redis y MariaDB.
- **Contras:**
  - Personalización limitada del stack interno.
  - Dependencia de un tercero (Bitnami) para actualizaciones.
  - Estructura de directorios diferente a la oficial de Moodle.
  - Overhead de capas innecesarias.

## Decisión
Se elige la **Opción B: Stack personalizado con Nginx + PHP-FPM + Redis + MariaDB**, con los siguientes componentes:

| Componente | Tecnología | Propósito |
|-----------|------------|-----------|
| **Reverse Proxy / Load Balancer** | Nginx | Recibir tráfico HTTP, distribuir entre workers, servir estáticos |
| **App Server** | PHP-FPM (múltiples workers) | Ejecutar el código PHP de Moodle |
| **Cache / Sesiones** | Redis (cluster) | Caché de aplicación, sesiones distribuidas, cola de tareas |
| **Base de Datos** | MariaDB 10.11+ | Persistencia principal de Moodle |
| **Almacenamiento** | Volumen Docker compartido (NFS-ready) | moodledata, archivos subidos, temp |
| **Orquestación** | Docker Compose (local) | Definición y gestión de contenedores |

### Arquitectura de contenedores propuesta

```
┌─────────────────────────────────────────────────────┐
│                    Red Interna                       │
│                                                      │
│  ┌──────────┐   ┌──────────────┐   ┌────────────┐  │
│  │  nginx    │──▶│ php-fpm      │──▶│ mariadb    │  │
│  │  :443     │   │ (workers xN) │   │ :3306      │  │
│  └──────────┘   └──────┬───────┘   └────────────┘  │
│                        │                            │
│                 ┌──────▼───────┐   ┌────────────┐  │
│                 │   redis      │   │  mailpit   │  │
│                 │  :6379       │   │  (SMTP)    │  │
│                 └──────────────┘   └────────────┘  │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │         shared-volume (moodledata)           │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Estrategia de versionado
- Moodle branch: `MOODLE_500_STABLE` (última versión estable del core).
- PHP: 8.3 o 8.4 (soportado oficialmente por Moodle).
- MariaDB: 10.11 LTS.
- Redis: 7.x estable.
- Nginx: 1.27+ estable.

## Consecuencias

### Positivas
- Separación clara de responsabilidades por contenedor.
- Capacidad de escalar horizontalmente los workers PHP-FPM.
- Sesiones centralizadas en Redis (no dependen del worker que atiende).
- Nginx maneja eficientemente múltiples conexiones simultáneas (hilos vs eventos).
- Compatibilidad total con Moodle LMS (PHP puro).
- Base para implementar patrones reactivos (salud, circuit breaker, autoescalado).

### Negativas
- Mayor complejidad de configuración que una imagen todo-en-uno.
- Se requiere configurar manualmente el archivo `config.php` de Moodle para Redis.
- El volumen compartido (moodledata) es un punto único de fallo si no se replica.
- La prueba local requiere puertos específicos libres (443, 3306, 6379).

## Referencias
- [Moodle Docker oficial (moodlehq)](https://github.com/moodlehq/moodle-docker)
- [Moodle PHP version requirements](https://docs.moodle.org/dev/PHP)
- [Nginx como proxy para PHP-FPM](https://www.nginx.com/resources/wiki/start/topics/recipes/wordpress/)
- [Redis cache store en Moodle](https://docs.moodle.org/en/Redis_cache_store)
- [Arquitectura de referencia Moodle en AWS](https://d1.awsstatic.com/architecture-diagrams/ArchitectureDiagrams/moodle-learning-management-system-on-aws-ra.pdf)
