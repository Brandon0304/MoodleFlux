# Arquitectura General del Sistema — Moodle LMS Reactivo Multi-Tenant

## Visión General

Este documento describe la arquitectura del sistema a nivel C4 (Contexto y Contenedores) para el despliegue local de Moodle LMS con capacidad reactiva y multi-tenencia.

---

## Nivel 1: Diagrama de Contexto (C4)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SISTEMA MOODLE LMS                           │
│               (Sistema de Gestión de Aprendizaje)                    │
│                                                                      │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐        │
│  │Estudiante│   │ Profesor │   │   Admin  │   │  Tenant  │        │
│  │          │   │          │   │  Global  │   │  Admin   │        │
│  └─────┬────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘        │
│        │             │              │              │               │
│        └─────────────┼──────────────┼──────────────┘               │
│                      │              │                              │
│              ┌───────▼──────────────▼───────┐                      │
│              │     Moodle LMS (Web App)     │                      │
│              │  (https://localhost:443)      │                      │
│              └───────────────┬───────────────┘                      │
│                              │                                      │
│              ┌───────────────▼───────────────┐                      │
│              │   Servicios Externos          │                      │
│              │  - SMTP (Mailpit)            │                      │
│              │  - LDAP (opcional)           │                      │
│              └───────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Actores del Sistema

| Actor | Descripción |
|-------|-------------|
| **Estudiante** | Usuario final que consume cursos, realiza actividades, ve calificaciones. Pertenece a un tenant específico. |
| **Profesor** | Crea y gestiona contenido educativo dentro de su(s) curso(s). Puede ver solo los estudiantes de sus cursos. |
| **Admin Global** | Administrador del sistema completo. Gestiona tenants, configuración global, seguridad. |
| **Tenant Admin** | Administrador delegado de una institución específica. Gestiona usuarios, cursos y configuración de su tenant. |

---

## Nivel 2: Diagrama de Contenedores (C4)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      MOODLE LMS - CONTENEDORES (Docker)                       │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐    │
│  │                       RED INTERNA (bridge)                            │    │
│  │                                                                       │    │
│  │  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐   │    │
│  │  │   Nginx       │────▶ PHP-FPM Pool     │────▶ MariaDB 10.11   │   │    │
│  │  │   :443/80     │    │ (workers x N)    │    │ :3306            │   │    │
│  │  │   (reverse    │    │                  │    │                  │   │    │
│  │  │    proxy)     │    │ moodle code      │    │ moodle db       │   │    │
│  │  └──────┬───────┘    └────────┬─────────┘    └──────────────────┘   │    │
│  │         │                     │                                      │    │
│  │         │              ┌──────▼─────────┐    ┌──────────────────┐   │    │
│  │         │              │   Redis 7       │    │   Mailpit        │   │    │
│  │         │              │   :6379         │    │   :1025/8025     │   │    │
│  │         │              │                 │    │   (SMTP Catch)   │   │    │
│  │         │              │ - Sesiones      │    └──────────────────┘   │    │
│  │         │              │ - Cache         │                           │    │
│  │         │              │ - Locks         │                           │    │
│  │         │              └─────────────────┘                           │    │
│  │         │                                                            │    │
│  │         └──────────────────────┐                                     │    │
│  │                                ▼                                     │    │
│  │  ┌────────────────────────────────────────────────────────────┐     │    │
│  │  │              moodledata (Volumen Compartido)                │     │    │
│  │  │  /var/www/moodledata/                                      │     │    │
│  │  │    ├── filedir/     (archivos subidos)                     │     │    │
│  │  │    ├── temp/        (archivos temporales)                   │     │    │
│  │  │    ├── trashdir/    (papelera)                              │     │    │
│  │  │    └── lang/        (paquetes de idioma)                    │     │    │
│  │  └────────────────────────────────────────────────────────────┘     │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                               │
│  ┌────────────────────────────────────────────┐                              │
│  │         VOLUMES DOCKER                      │                              │
│  │  - mariadb-data:/var/lib/mysql             │                              │
│  │  - redis-data:/data                        │                              │
│  │  - moodledata:/var/www/moodledata          │                              │
│  └────────────────────────────────────────────┘                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Resumen de Componentes y Responsabilidades

### 1. Nginx (Reverse Proxy + Load Balancer)
| Atributo | Valor |
|----------|-------|
| Imagen | `nginx:1.27-alpine` |
| Puerto | 443 (HTTPS) / 80 (HTTP) |
| Rol | Proxy inverso, balanceo de carga, terminación SSL, archivos estáticos |
| Config | `worker_processes auto; worker_connections 4096;` |
| Health | `GET /health` → verifica PHP-FPM |

### 2. PHP-FPM (Workers de aplicación)
| Atributo | Valor |
|----------|-------|
| Imagen | Construida desde `php:8.3-fpm-alpine` con extensiones Moodle |
| Workers | `pm = dynamic; pm.max_children = 50; pm.start_servers = 5` |
| Escalado | `docker compose up -d --scale php-fpm=N` |
| Rol | Ejecutar el código PHP de Moodle |
| Dependencias | Redis, MariaDB, moodledata |

### 3. Redis (Caché + Sesiones + Locks)
| Atributo | Valor |
|----------|-------|
| Imagen | `redis:7-alpine` |
| Puerto | 6379 |
| Persistencia | AOF + RDB (híbrida) |
| Bases | DB0=sesiones, DB1-3=caché, DB4=locks |

### 4. MariaDB (Base de Datos)
| Atributo | Valor |
|----------|-------|
| Imagen | `mariadb:10.11` |
| Puerto | 3306 |
| Engine | InnoDB |
| Pool | Max connections: 200 |

### 5. Mailpit (SMTP de prueba)
| Atributo | Valor |
|----------|-------|
| Imagen | `axllent/mailpit` |
| Puertos | 1025 (SMTP), 8025 (Web UI) |
| Rol | Capturar correos enviados por Moodle |

---

## Flujo de una Solicitud Típica

```
1. Estudiante abre https://localhost/login
2. Nginx recibe la solicitud (worker conexión)
3. Nginx pasa a PHP-FPM (fastcgi a worker disponible)
4. PHP-FPM ejecuta Moodle:
   a. Lee sesión desde Redis
   b. Verifica autenticación contra MariaDB
   c. Obtiene datos del curso (caché Redis o DB)
   d. Renderiza HTML
5. Nginx sirve archivos estáticos (JS/CSS/images) sin pasar por PHP
6. Respuesta al navegador
```

### Bajo Alta Carga (simulación con k6)
```
k6 run --vus 200 --duration 60s carga.js

- Nginx distribuye entre 5 workers PHP-FPM
- Sesiones en Redis (no bloquean workers)
- Caché reduce hits a DB en ~60%
- Si un worker falla, Nginx redirige a otro
- MariaDB maneja hasta 200 conexiones simultáneas
```

---

## Estrategia de Multi-Tenencia (Lógica)

Ver ADR-003 para detalle completo. Resumen:

| Tenant | Categoría | Cohorte | Admin | Theme |
|--------|-----------|---------|-------|-------|
| Universidad Nacional | `/U.Nacional/` | `cohorte_unacional` | admin@unacional.edu | boost_uni |
| Empresa X | `/EmpresaX/` | `cohorte_empx` | admin@empx.com | boost_corp |
| Colegio Y | `/ColegioY/` | `cohorte_colegioy` | admin@colegioy.edu | boost_school |

---

## Prueba de Carga (Conceptual)

### Herramienta recomendada: k6
```javascript
// Fragmento conceptual de script k6
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },   // Subida gradual a 50 usuarios
    { duration: '1m', target: 50 },     // Mantener 50 usuarios
    { duration: '30s', target: 200 },   // Pico a 200 usuarios
    { duration: '1m', target: 200 },    // Mantener pico
    { duration: '30s', target: 0 },     // Bajada
  ],
};

export default function () {
  const res = http.get('https://localhost/login');
  check(res, { 'status 200': (r) => r.status === 200 });
}
```

### Lo que se medirá
| Métrica | Objetivo |
|---------|----------|
| Tiempo de respuesta promedio | < 500ms |
| Tasa de error | < 1% |
| Sesiones activas concurrentes | > 200 |
| CPU/RAM de contenedores | Sin throttling |

---

## Referencias Cruzadas

| Documento | Descripción |
|-----------|-------------|
| `docs/adr/ADR-001-stack-tecnologico-y-contenerizacion.md` | Stack y estrategia de contenedores |
| `docs/adr/ADR-002-arquitectura-reactiva-concurrencia-resiliencia.md` | Patrones reactivos y concurrencia |
| `docs/adr/ADR-003-estrategia-multi-tenencia.md` | Multi-tenencia lógica |
| `docs/adr/ADR-004-cache-sesiones-almacenamiento.md` | Redis, sesiones, moodledata |
| `docs/adr/ADR-005-base-datos-alta-disponibilidad.md` | MariaDB, rendimiento, HA futura |
