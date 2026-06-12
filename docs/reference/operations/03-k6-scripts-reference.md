# Referencia: Pruebas de Carga con k6

## ¿Qué es k6?

k6 es una herramienta de pruebas de carga open source. Se usa para simular tráfico concurrente y medir cómo responde el sistema.

## Instalación

```bash
# Linux / macOS / WSL
curl -fsSL https://k6.io/install.sh | bash

# O con Docker
docker run --rm -i grafana/k6 run - <script.js
```

## Estructura de un Script de Carga

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

// Configuración de la prueba
export const options = {
  stages: [
    { duration: '30s', target: 50 },    // Subida gradual
    { duration: '2m', target: 50 },     // Mantener
    { duration: '30s', target: 200 },   // Pico
    { duration: '1m', target: 200 },    // Sostener pico
    { duration: '30s', target: 0 },     // Bajada
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],   // 95% de requests < 500ms
    http_req_failed: ['rate<0.01'],     // < 1% de errores
  },
};

export default function () {
  // 1. Login
  const loginRes = http.post('https://localhost/login/index.php', {
    username: 'estudiante',
    password: 'password',
  });
  check(loginRes, { 'login ok': (r) => r.status === 200 });

  // 2. Navegar a un curso
  const courseRes = http.get('https://localhost/course/view.php?id=2');
  check(courseRes, { 'course loaded': (r) => r.status === 200 });

  // 3. Pausa entre acciones (simula lectura)
  sleep(Math.random() * 5 + 2);  // 2-7 segundos
}
```

## Escenarios de Prueba Recomendados

### Escenario 1: Navegación de Estudiantes (el más importante)
```javascript
// Simula N estudiantes viendo cursos, recursos y actividades
export const options = {
  stages: [
    { duration: '1m', target: 50 },    // 50 estudiantes simultáneos
    { duration: '3m', target: 50 },    // Mantener
    { duration: '1m', target: 100 },   // Subir a 100
    { duration: '3m', target: 100 },   // Mantener
    { duration: '1m', target: 0 },     // Bajada
  ],
};
```

### Escenario 2: Pico de Acceso (inicio de clases)
```javascript
// Simula todos los estudiantes entrando al mismo tiempo
export const options = {
  stages: [
    { duration: '10s', target: 200 },  // 200 estudiantes en 10s
    { duration: '5m', target: 200 },   // Mantener
    { duration: '1m', target: 0 },
  ],
};
```

### Escenario 3: Subida de Archivos (entrega de tareas)
```javascript
// Simula estudiantes subiendo tareas simultáneamente
export default function () {
  const file = http.file('/path/to/tarea.pdf', 'application/pdf');
  const res = http.post('https://localhost/mod/assign/view.php?id=5&action=editsubmission', {
    file: file,
  });
}
```

## Métricas a Monitorear

| Métrica k6 | Traduce a | Objetivo |
|------------|-----------|----------|
| `http_req_duration` | Tiempo de respuesta | p95 < 500ms |
| `http_req_failed` | Tasa de error | < 1% |
| `http_reqs` | Throughput (requests/s) | > 100 req/s |
| `vus` | Usuarios concurrentes | Hasta 200 |
| `iterations` | Operaciones completadas | Mínimo 1000 |

## Dashboard de Resultados

```bash
# Ver resultados en tiempo real
k6 run --vus 50 --duration 2m script.js

# Exportar resumen
k6 run --summary-export=resultados.json script.js

# Con dashboard web (k6 + influxdb + grafana)
k6 run --out influxdb=http://localhost:8086/k6 script.js
```

## Correlación con Recursos del Sistema

Mientras k6 genera carga, monitorear en paralelo:

```bash
# Recursos de contenedores
docker stats

# Logs de Nginx (tiempos de respuesta)
docker compose logs --tail=100 nginx

# Redis (operaciones por segundo)
docker exec redis redis-cli info stats | grep instantaneous_ops_per_sec

# MariaDB (consultas lentas)
docker compose exec mariadb mariadb-admin status
```

## Referencias
- https://k6.io/docs/
- https://k6.io/docs/using-k6/k6-options/
- https://k6.io/docs/javascript-api/
- https://grafana.com/docs/grafana/latest/datasources/influxdb/
