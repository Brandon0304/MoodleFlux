# Matriz de Riesgos Arquitectónicos

## Metodología
Cada riesgo se evalúa con:
- **Probabilidad**: Baja / Media / Alta
- **Impacto**: Bajo / Medio / Alto / Crítico
- **Severidad**: = Probabilidad × Impacto

## Matriz de Riesgos

### 1. Riesgos de Infraestructura

| # | Riesgo | Probabilidad | Impacto | Severidad | Mitigación | Contingencia |
|---|--------|:-----------:|:-------:|:---------:|------------|--------------|
| R1 | **Caída de MariaDB** | Baja | Crítico | 🔴 Alta | Health checks + restart policy (ADR-002). Réplica de lectura planeada (ADR-005) | Restaurar desde backup. En producción, promover réplica |
| R2 | **Caída de Redis** | Baja | Alto | 🟡 Media | Redis persistencia AOF+RDB. Health check cada 10s. Fallback a archivos locales (ADR-004) | El sistema funciona en modo degradado. Redis se recupera solo |
| R3 | **Disco lleno (moodledata)** | Media | Alto | 🟡 Media | Alerta al 85% de uso. Backup diario libera espacio. Límite de tamaño por tenant | Migrar archivos viejos a almacenamiento frío. Expandir volumen |
| R4 | **Caída del host Docker** | Baja | Crítico | 🔴 Alta | Volúmenes persistentes en disco (no en contenedor). Backups externos | Restaurar en otro host con `docker compose up` + restore de backups |
| R5 | **Pérdida de red interna** | Baja | Alto | 🟡 Media | Redes definidas en docker-compose, no creadas manualmente | `docker compose down && docker compose up -d` recrea las redes |

### 2. Riesgos de Seguridad

| # | Riesgo | Probabilidad | Impacto | Severidad | Mitigación | Contingencia |
|---|--------|:-----------:|:-------:|:---------:|------------|--------------|
| R6 | **Fuga de datos entre tenants** | Baja | Crítico | 🔴 Alta | Aislamiento lógico con categorías + cohorts + roles (ADR-003). Plugin de aislamiento opcional | Rotar credenciales del tenant afectado. Auditar logs de acceso |
| R7 | **Acceso no autorizado a admin** | Media | Crítico | 🔴 Alta | HTTPS + contraseñas seguras + bloqueo por intentos. MFA opcional | Revocar sesiones activas. Cambiar contraseñas. Auditar actividad |
| R8 | **Exposición de secrets en Git** | Media | Alto | 🟡 Alta | `.env` en `.gitignore`. Secrets vía variables de entorno. Auditoría periódica | Rotar TODAS las contraseñas expuestas. Eliminar del historial Git |
| R9 | **Inyección SQL / XSS** | Baja | Alto | 🟡 Media | Moodle usa prepared statements y output escaping. Validación de entrada en formularios | Actualizar Moodle al último parche de seguridad |
| R10 | **Incumplimiento Ley 1581** | Media | Alto | 🟡 Alta | Aviso de privacidad, consentimiento, derechos ARCO implementados | Designar oficial de cumplimiento. Notificar a autoridades si hay violación |

### 3. Riesgos de Rendimiento

| # | Riesgo | Probabilidad | Impacto | Severidad | Mitigación | Contingencia |
|---|--------|:-----------:|:-------:|:---------:|------------|--------------|
| R11 | **Pico de estudiantes concurrentes** | Media | Alto | 🟡 Alta | Pool dinámico PHP-FPM + Redis caché + Nginx cola (ADR-002). Pruebas de carga con k6 | Escalar workers: `--scale php-fpm=N`. Si persiste, aumentar recursos del host |
| R12 | **Degradación de Redis por tamaño de caché** | Baja | Medio | 🟢 Baja | `maxmemory` configurado con política `allkeys-lru`. Monitoreo de hit rate | Aumentar `maxmemory` o reducir TTL de ciertos stores |
| R13 | **Slow queries en MariaDB** | Media | Medio | 🟡 Media | Índices optimizados para Moodle. Buffer pool configurado. Slow query log activo | Optimizar consultas. Agregar índices. En producción, réplica de lectura |
| R14 | **Overflow de moodledata por archivos temporales** | Media | Bajo | 🟢 Baja | `localcachedir` por worker se limpia periódicamente. `trashdir` con purgado automático | Limpieza manual de `temp/` y `trashdir/` |

### 4. Riesgos de Multi-Tenencia

| # | Riesgo | Probabilidad | Impacto | Severidad | Mitigación | Contingencia |
|---|--------|:-----------:|:-------:|:---------:|------------|--------------|
| R15 | **Un tenant consume todos los recursos** | Media | Alto | 🟡 Alta | Límites de recursos por contenedor. PHP-FPM pool compartido pero con `pm.max_requests` | Identificar tenant problemático. En producción, evaluar instancias separadas |
| R16 | **Admin de tenant escala privilegios** | Baja | Crítico | 🔴 Alta | Roles personalizados con ámbito de categoría. Auditoría de acciones de admin | Revocar rol. Auditar logs. Restaurar configuraciones del tenant |
| R17 | **Corrupción de datos de un tenant** | Baja | Alto | 🟡 Media | Backups diarios. Aislamiento lógico evita contaminación cruzada | Restore del tenant desde backup. Si no es posible, restore completo |

### 5. Riesgos de Actualización

| # | Riesgo | Probabilidad | Impacto | Severidad | Mitigación | Contingencia |
|---|--------|:-----------:|:-------:|:---------:|------------|--------------|
| R18 | **Actualización de Moodle rompe plugins** | Media | Alto | 🟡 Alta | Verificar compatibilidad antes de actualizar. Probar en entorno local primero | Rollback de Moodle + plugins. Esperar actualización del plugin |
| R19 | **Actualización rompe config.php** | Baja | Medio | 🟢 Baja | `.env` separado del código. Config.php versionado como template. Probar en staging | Restaurar config.php desde backup. Verificar variables de entorno |
| R20 | **Plugin de terceros abandonado** | Media | Medio | 🟡 Media | Solo usar plugins del directorio oficial con mantenimiento activo | Buscar alternativa. Evaluar desarrollo propio |

## Plan de Acción por Severidad

| Severidad | Acción | Responsable | Plazo |
|:---------:|--------|-------------|:-----:|
| 🔴 Crítica | Mitigación inmediata. Implementar control antes de pasar a producción | Arquitecto | 1 semana |
| 🟡 Alta | Mitigación planificada. Incluir en el roadmap | Arquitecto / Build | 1 mes |
| 🟢 Baja | Monitorear. Mitigar solo si la probabilidad o impacto aumentan | Operaciones | Continuo |

## Top 5 Riesgos a Mitigar Antes de Producción

| Prioridad | Riesgo | Acción Inmediata |
|:---------:|--------|------------------|
| 1 | **R6: Fuga entre tenants** | Implementar plugin de aislamiento + auditoría de roles |
| 2 | **R7: Acceso no autorizado** | Forzar HTTPS + contraseñas seguras + bloqueo de cuenta |
| 3 | **R8: Secrets en Git** | Configurar `.gitignore` + auditoría de commits pasados |
| 4 | **R1: Caída de DB** | Verificar health checks + backups automáticos |
| 5 | **R11: Pico de concurrencia** | Realizar prueba de carga con k6 antes del lanzamiento |

## Referencias
- [ADR-002](../adr/ADR-002-arquitectura-reactiva-concurrencia-resiliencia.md) — Resiliencia
- [ADR-006](../adr/ADR-006-estrategia-seguridad.md) — Seguridad
- [ADR-007](../adr/ADR-007-estrategia-despliegue-actualizaciones.md) — Despliegue
- `docs/reference/operations/01-backup-strategy.md`
- `docs/reference/operations/03-k6-scripts-reference.md`
