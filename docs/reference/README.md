# Documentación de Referencia

## Estructura

```
reference/
├── README.md                              ← Este archivo
├── enlaces-utiles.md                      ← Repositorio de enlaces
├── matriz-riesgos-arquitectonicos.md      🆕 ← 20 riesgos evaluados con mitigación
│
├── stack/                                 ← Stack tecnológico
│   ├── 01-moodle-requirements.md
│   ├── 02-redis-moodle-config.md
│   ├── 03-nginx-php-fpm-tuning.md
│   └── 04-docker-compose-reference.md
│
├── security/                              
│   └── 01-seguridad-checklist.md
│
├── operations/                            
│   ├── 01-backup-strategy.md
│   ├── 02-monitoring-setup.md
│   └── 03-k6-scripts-reference.md
│
└── multi-tenant/                          
    ├── 01-multi-tenancy-patterns.md
    └── 02-moodle-plugins-catalogue.md
```

## Mapa ADR → Referencias

| ADR | Documentos Relacionados |
|-----|------------------------|
| ADR-001 (Stack) | `stack/01-moodle-requirements.md`, `stack/04-docker-compose-reference.md` |
| ADR-002 (Reactiva) | `stack/03-nginx-php-fpm-tuning.md`, `operations/03-k6-scripts-reference.md`, `operations/02-monitoring-setup.md` |
| ADR-003 (Multi-Tenencia) | `multi-tenant/01-multi-tenancy-patterns.md`, `multi-tenant/02-moodle-plugins-catalogue.md` |
| ADR-004 (Caché) | `stack/02-redis-moodle-config.md` |
| ADR-005 (Base de Datos) | `operations/01-backup-strategy.md` |
| ADR-006 (Seguridad) | `security/01-seguridad-checklist.md` |
| ADR-007 (Despliegue) | `stack/04-docker-compose-reference.md` |
| ADR-008 (Observabilidad) | `operations/02-monitoring-setup.md`, `operations/03-k6-scripts-reference.md` |
| Todos | `matriz-riesgos-arquitectonicos.md`, `enlaces-utiles.md` |
