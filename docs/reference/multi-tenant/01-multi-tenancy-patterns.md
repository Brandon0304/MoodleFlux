# Referencia: Patrones de Arquitectura Multi-Tenant

## Los 3 Patrones Fundamentales

### 1. Base de Datos Separada por Tenant
```
Tenant A ──→ Base de Datos A
Tenant B ──→ Base de Datos B
Tenant C ──→ Base de Datos C
```
- **Aislamiento**: Físico (máximo)
- **Costo**: Alto (N bases de datos)
- **Complejidad**: Baja
- **Moodle**: Moodle Workplace NO usa este patrón

### 2. Schema Separado por Tenant (misma DB)
```
Base de Datos Única
├── schema_tenant_A (tablas: user, course, grade...)
├── schema_tenant_B (tablas: user, course, grade...)
└── schema_tenant_C (tablas: user, course, grade...)
```
- **Aislamiento**: Alto (lógico por schema)
- **Costo**: Medio
- **Complejidad**: Media
- **Moodle**: No soportado nativamente (requeriría modificar core)

### 3. Tablas Compartidas con Tenant ID (el que usamos)
```
Base de Datos Única
mdl_user (columna: tenant_id)
mdl_course (columna: tenant_id → categoría)
mdl_grade (columna: tenant_id)
```
- **Aislamiento**: Lógico (vía consultas WHERE tenant_id)
- **Costo**: Bajo (una sola DB)
- **Complejidad**: Alta (hay que asegurar filtros en todas las consultas)
- **Moodle**: Se logra vía Categorías + Cohorts + Roles (ADR-003)

## Comparación

| Patrón | Aislamiento | Costo | Escalabilidad | Moodle LMS |
|--------|------------|-------|---------------|------------|
| DB separada | 🔒🔒🔒 | $$$ | Horizontal | ❌ No soportado |
| Schema separado | 🔒🔒 | $$ | Horizontal | ❌ Requiere core hack |
| Tenant ID lógico | 🔒 | $ | Vertical | ✅ Vía config |

## Recomendación para Moodle LMS Clásico

Usar **Patrón 3 (Tenant ID lógico)** implementado con:
- Categorías de cursos como tenant_id
- Cohorts para agrupar usuarios por tenant
- Roles a nivel de categoría para aislar administración

## Referencias
- https://www.gartner.com/en/information-technology/glossary/multitenancy
- https://docs.moodle.org/en/Course_categories
- https://docs.moodle.org/en/Cohorts
- https://docs.moodle.org/en/Roles
