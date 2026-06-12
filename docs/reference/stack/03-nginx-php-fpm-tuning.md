# Referencia: Tuning de Nginx + PHP-FPM para Moodle

## Arquitectura de Procesos

```
Nginx (master)
  └── Nginx (worker 1) ── conexiones concurrentes (event-loop)
  └── Nginx (worker N) ── worker_processes = auto (≈ núcleos CPU)

PHP-FPM (master)
  └── PHP-FPM (pool www)
       └── child 1 ── atiende 1 request (bloqueante)
       └── child N ── pm.max_children configurables
```

## Configuración de Nginx

```nginx
# /etc/nginx/nginx.conf
worker_processes auto;
worker_connections 4096;
use epoll;  # Linux: event-driven, no bloqueante

# /etc/nginx/conf.d/moodle.conf
server {
    listen 443 ssl http2;
    server_name localhost;

    # Tamaño máximo de subida (tareas, recursos)
    client_max_body_size 100M;
    
    # Timeouts
    proxy_read_timeout 120s;
    proxy_connect_timeout 10s;
    proxy_send_timeout 10s;

    # Compresión
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    # Caché de archivos estáticos
    location ~ \.(js|css|png|jpg|gif|ico|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Proxy a PHP-FPM
    location ~ \.php$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```

## Configuración de PHP-FPM

```ini
# /usr/local/etc/php-fpm.d/www.conf
[www]
pm = dynamic                          # Ajuste dinámico de workers
pm.max_children = 50                  # Máximo de workers (≈ 50 requests concurrentes)
pm.start_servers = 5                  # Workers al arrancar
pm.min_spare_servers = 3              # Workers inactivos mínimos
pm.max_spare_servers = 10             # Workers inactivos máximos
pm.max_requests = 500                 # Reiniciar worker tras 500 requests (previene memory leak)

; Timeouts
request_terminate_timeout = 120s      # Matar worker si excede
request_slowlog_timeout = 30s         # Log si tarda > 30s
slowlog = /var/log/php-slow.log
```

## Fórmula de Dimensionamiento

```
RAM disponible para PHP ≈ RAM total - RAM de MariaDB - RAM de Redis - RAM del sistema

max_children = RAM para PHP / (memoria por proceso PHP)

Ejemplo (8 GB RAM total):
- MariaDB: 1 GB
- Redis: 512 MB
- Sistema: 1 GB
- PHP disponible: ~5.5 GB
- Memoria por worker PHP en Moodle: ~64 MB promedio
- max_children = 5500 / 64 ≈ 85
- Máximo seguro: 50 (dejando margen)
```

## Cómo Simular Alta Carga Localmente

```bash
# Escalar workers
docker compose up -d --scale php-fpm=5

# Probar con k6
k6 run --vus 100 --duration 60s carga.js
```

## Referencias
- https://www.nginx.com/blog/nginx-php-fpm-process-management/
- https://docs.moodle.org/en/Performance_recommendations
- https://mariadb.com/kb/en/server-system-variables/
