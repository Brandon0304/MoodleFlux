# Referencia: Estrategia de Backups y Recuperación

## 1. ¿Qué Hay que Respaldar?

| Componente | Qué | Frecuencia | Tamaño estimado |
|------------|-----|:----------:|:---------------:|
| **MariaDB** | Base de datos completa | Diario | 100 MB - 10 GB |
| **moodledata** | Archivos subidos, temp | Diario | 1 GB - 100 GB |
| **config.php** | Configuración de Moodle | Por cambio | ~2 KB |
| **Plugins** | Código de plugins instalados | Por cambio | ~50 MB |

## 2. Estrategia de Backup

### 2.1 Base de Datos (MariaDB)

```bash
# Backup completo (todos los tenants)
docker exec mariadb sh -c \
  'mariadb-dump --all-databases \
   --single-transaction \
   --routines \
   --triggers \
   -u root -p"$MYSQL_ROOT_PASSWORD"' \
  > /backups/moodle_db_$(date +%Y%m%d_%H%M%S).sql

# Comprimir
gzip /backups/moodle_db_*.sql
```

**Recomendaciones**:
- Usar `--single-transaction` para no bloquear tablas durante el dump
- Ejecutar en horario de baja actividad
- Retención: 7 backups diarios + 4 semanales + 3 mensuales
- Probar restore al menos una vez al mes

### 2.2 moodledata (Archivos)

```bash
# Backup de archivos (rsync + hard links para eficiencia)
rsync -av --link-dest=/backups/moodledata_daily_1 \
  /var/www/moodledata/ \
  /backups/moodledata_daily_$(date +%Y%m%d)
```

**Alternativa futura**: Si se migra a S3/MinIO (plugin `local_objectfs`), moodledata ya estaría respaldado por el proveedor de almacenamiento de objetos.

### 2.3 Backup Automatizado (Cron del Host)

```bash
# /etc/cron.d/moodle-backup
# Backup de BD - 3:00 AM todos los días
0 3 * * * root docker exec mariadb mariadb-dump --all-databases --single-transaction -u root -p"password" | gzip > /backups/db/moodle_$(date +\%Y\%m\%d).sql.gz

# Backup de moodledata - 4:00 AM todos los días
0 4 * * * root rsync -aq /var/www/moodledata/ /backups/moodledata/$(date +\%Y\%m\%d)/

# Limpieza - mantener últimos 7 días
0 5 * * * root find /backups/db/ -name "*.sql.gz" -mtime +7 -delete
```

## 3. Estrategia de Restore

### 3.1 Restore de Base de Datos

```bash
# 1. Detener Moodle (o ponerlo en modo mantenimiento)
docker compose exec php-fpm php admin/cli/maintenance.php --enable

# 2. Restaurar BD
gunzip < /backups/db/moodle_20260101.sql.gz | \
  docker exec -i mariadb sh -c \
  'mariadb -u root -p"$MYSQL_ROOT_PASSWORD"'

# 3. Reanudar Moodle
docker compose exec php-fpm php admin/cli/maintenance.php --disable
```

### 3.2 Restore de moodledata

```bash
# Restaurar archivos
rsync -av /backups/moodledata/20260101/ /var/www/moodledata/
```

### 3.3 Restore Completo (desastre total)

```bash
# 1. Recrear contenedores
docker compose up -d

# 2. Restaurar BD
gunzip < /backups/db/moodle_latest.sql.gz | \
  docker exec -i mariadb mariadb -u root -p"password" moodle

# 3. Restaurar moodledata
rsync -av /backups/moodledata/latest/ /var/www/moodledata/

# 4. Verificar integridad
docker compose exec php-fpm php admin/cli/checks.php
```

## 4. Política de Retención

| Tipo | Diario | Semanal | Mensual | Anual |
|------|:------:|:-------:|:-------:|:-----:|
| BD | 7 días | 4 semanas | 3 meses | 1 año |
| moodledata | 7 días | 4 semanas | 3 meses | 1 año |
| config.php | Git | Git | Git | Git |

## 5. Verificación de Backups

- [ ] **Diario**: Verificar que el backup se generó y tiene tamaño > 0
- [ ] **Semanal**: Restore en entorno de prueba y verificar integridad
- [ ] **Mensual**: Prueba de restore completa (BD + moodledata)
- [ ] **Trimestral**: Simulación de desastre total

## 6. Notas sobre Multi-Tenencia

- El backup de BD contiene TODOS los tenants (es una sola BD)
- No es posible (fácilmente) restaurar un solo tenant sin afectar otros
- Para restore selectivo por tenant: extraer registros del SQL filtrados por tenant_id/categoría
- Alternativa: mantener backups específicos por tenant (scripts separados con `--where`)

## Referencias
- https://docs.moodle.org/en/Site_backup
- https://mariadb.com/kb/en/backup-and-restore-overview/
- https://rsync.samba.org/
