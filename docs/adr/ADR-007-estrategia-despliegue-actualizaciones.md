# ADR-007: Estrategia de Despliegue y Actualizaciones

## Estado
**Aceptado**

## Contexto
Moodle LMS se actualiza frecuentemente con parches de seguridad, correcciones de errores y nuevas funcionalidades. Además, la configuración del sistema (`config.php`, plugins, temas) debe gestionarse de forma ordenada entre el entorno local de pruebas y un posible entorno productivo futuro. Se requiere:

1. Un flujo de actualización de Moodle que no rompa la configuración personalizada.
2. Gestión de configuraciones específicas por entorno (local vs producción).
3. Control de versiones de la infraestructura (Docker, configs).
4. Mecanismo para probar actualizaciones antes de aplicarlas.

## Opciones consideradas

### Opción A: Actualización manual in-place
- **Pros:** Simple, sin herramientas adicionales.
- **Contras:** Sin posibilidad de rollback, riesgo de romper la instancia, no reproducible.

### Opción B: Estrategia Git + Docker + entornos (seleccionada)
- **Pros:**
  - Infraestructura versionada en Git (Dockerfiles, docker-compose, configs).
  - Código de Moodle separado de la configuración (no versionar el core).
  - Rollback posible: `git revert` + `docker compose down && up`.
  - Probado en local antes de aplicar a producción.
- **Contras:** Mayor complejidad inicial, requiere disciplina en el flujo Git.

## Decisión
Se implementa una **estrategia Git + Docker + entornos** con las siguientes decisiones:

### 1. Estructura de Repositorio

```
moodle-lms/
├── .agents/                         ← Reglas del agente (no tocar)
├── docs/                            ← Documentación arquitectónica
├── docker/                          ← Configuración Docker (versionado)
│   ├── nginx/
│   │   ├── conf.d/moodle.conf
│   │   └── nginx.conf
│   ├── php-fpm/
│   │   ├── Dockerfile
│   │   ├── php.ini
│   │   └── www.conf
│   └── mariadb/
│       └── init.sql
├── moodle/                          ← Código fuente de Moodle (NO versionado)
│   ├── config.php                   ← Template (config.php.tpl versionado)
│   └── ... (core de Moodle)
├── .env.example                     ← Template de variables de entorno
├── .gitignore
├── docker-compose.yml               ← Versionado
└── README.md
```

### 2. Flujo de Actualización de Moodle

```bash
# 1. Respaldar antes de actualizar
./scripts/backup.sh

# 2. Detener contenedores
docker compose down

# 3. Actualizar código fuente de Moodle
cd moodle
git fetch origin
git checkout MOODLE_500_STABLE   # Rama de versión estable
git pull origin MOODLE_500_STABLE

# 4. Reconstruir y arrancar
cd ..
docker compose build php-fpm    # Reconstruir si hay cambios en extensiones PHP
docker compose up -d

# 5. Ejecutar migración de Moodle
docker compose exec php-fpm php admin/cli/upgrade.php

# 6. Verificar
docker compose exec php-fpm php admin/cli/checks.php
```

### 3. Gestión de Configuración por Entorno

| Variable | Local (dev) | Producción | ¿En Git? |
|----------|------------|------------|:--------:|
| `COMPOSE_PROJECT_NAME` | `moodle-dev` | `moodle-prod` | ❌ `.env` |
| `MOODLE_DOCKER_WEB_PORT` | `443` | `443` | ❌ `.env` |
| `MYSQL_ROOT_PASSWORD` | `root123` | (secreto) | ❌ `.env` |
| `MYSQL_PASSWORD` | `moodle123` | (secreto) | ❌ `.env` |
| `PHP_MEMORY_LIMIT` | `256M` | `512M` | ❌ `.env` |
| `PHP_MAX_CHILDREN` | `10` | `50` | ❌ `.env` |

**Regla:** El archivo `.env` NO se versiona. Solo existe `.env.example` como template.

### 4. Estrategia de Branching

```text
main                  → Estable, lista para deploy
├── develop           → Integración de cambios
│   ├── feature/xxx   → Nuevas configuraciones
│   └── fix/xxx       → Correcciones
└── release/x.y.z     → Versiones preparadas para producción
```

**Política:**
- `main` siempre debe funcionar con `docker compose up -d`
- Los cambios en `docker/`, `docker-compose.yml` y `.env.example` pasan por PR
- El código de Moodle (`moodle/`) NO se versiona en este repo (se descarga aparte)

### 5. Rollback

```bash
# Si una actualización falla:
# Opción 1: Revertir código de Moodle
cd moodle
git checkout <commit-anterior>

# Opción 2: Restaurar backup
./scripts/restore.sh /backups/moodle_20260101.sql.gz

# Opción 3: Revertir infraestructura
git revert HEAD
docker compose down
docker compose up -d
```

### 6. Estrategia de Plugins

- Los plugins se instalan en directorios dentro de `moodle/` (local/, mod/, block/, theme/)
- Los plugins críticos se documentan en `docs/reference/multi-tenant/02-moodle-plugins-catalogue.md`
- Antes de actualizar Moodle: verificar compatibilidad de plugins con la nueva versión
- Plugins del core (estándar) se actualizan junto con Moodle
- Plugins de terceros: actualizar antes de actualizar Moodle

## Consecuencias

### Positivas
- Actualizaciones de Moodle probadas localmente antes de producción.
- Rollback posible en 3 niveles (código, backup, infraestructura).
- Configuración por entorno sin exponer secrets en Git.
- Infraestructura reproducible desde cero con `git clone + docker compose up`.

### Negativas
- El código de Moodle (~500MB) se descarga aparte, no está en el repo.
- Requiere disciplina en el flujo Git y en no versionar `.env`.
- Los plugins de terceros pueden retrasar actualizaciones de Moodle.
- El script de backup/restore debe mantenerse actualizado.

## Referencias
- [Moodle Upgrade docs](https://docs.moodle.org/en/Upgrading)
- [Docker Compose CLI](https://docs.docker.com/compose/reference/)
- [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow)
- `docs/reference/operations/01-backup-strategy.md`
