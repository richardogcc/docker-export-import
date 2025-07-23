#!/bin/bash

# Script de prueba para el sistema de backup y restauración de Docker
# Crea contenedores de prueba para testear el sistema

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar que Docker esté corriendo
if ! docker info >/dev/null 2>&1; then
    log_error "Docker no está corriendo"
    exit 1
fi

echo "=========================================="
echo "  CREADOR DE CONTENEDORES DE PRUEBA"
echo "=========================================="

log_info "Creando contenedores de prueba para testear el sistema de backup..."

# Crear directorios de prueba para bind mounts
mkdir -p ./test_data/nginx_html
mkdir -p ./test_data/nginx_config
mkdir -p ./test_data/postgres_data

# Crear contenido de prueba
cat > ./test_data/nginx_html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Test Nginx</title>
</head>
<body>
    <h1>¡Contenedor de prueba funcionando!</h1>
    <p>Este es un archivo de prueba para el sistema de backup de Docker.</p>
    <p>Fecha de creación: <script>document.write(new Date());</script></p>
</body>
</html>
EOF

cat > ./test_data/nginx_config/default.conf << 'EOF'
server {
    listen 80;
    server_name localhost;
    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
}
EOF

# 1. Contenedor Nginx con bind mounts y volumen
log_info "Creando contenedor Nginx de prueba..."
docker run -d \
    --name test-nginx \
    -p 8080:80 \
    -v "$(pwd)/test_data/nginx_html:/usr/share/nginx/html:ro" \
    -v "$(pwd)/test_data/nginx_config:/etc/nginx/conf.d:ro" \
    -v test_nginx_logs:/var/log/nginx \
    nginx:alpine

# 2. Contenedor Redis con volumen
log_info "Creando contenedor Redis de prueba..."
docker run -d \
    --name test-redis \
    -p 6379:6379 \
    -v test_redis_data:/data \
    redis:alpine \
    redis-server --appendonly yes

# 3. Contenedor PostgreSQL con volumen y variables de entorno
log_info "Creando contenedor PostgreSQL de prueba..."
docker run -d \
    --name test-postgres \
    -e POSTGRES_DB=testdb \
    -e POSTGRES_USER=testuser \
    -e POSTGRES_PASSWORD=testpass \
    -p 5432:5432 \
    -v test_postgres_data:/var/lib/postgresql/data \
    postgres:13-alpine

# 4. Contenedor simple sin volúmenes (para pruebas básicas)
log_info "Creando contenedor Alpine de prueba..."
docker run -d \
    --name test-alpine \
    alpine:latest \
    sh -c 'while true; do echo "Test container running: $(date)"; sleep 60; done'

# Esperar a que los contenedores se inicien
log_info "Esperando que los contenedores se inicien..."
sleep 5

# Añadir datos de prueba a Redis
log_info "Añadiendo datos de prueba a Redis..."
docker exec test-redis redis-cli set "test:key1" "Valor de prueba 1"
docker exec test-redis redis-cli set "test:key2" "Valor de prueba 2"
docker exec test-redis redis-cli lpush "test:lista" "Elemento 1" "Elemento 2" "Elemento 3"

# Añadir datos de prueba a PostgreSQL
log_info "Añadiendo datos de prueba a PostgreSQL..."
sleep 10  # Esperar a que PostgreSQL esté listo

docker exec test-postgres psql -U testuser -d testdb -c "
CREATE TABLE IF NOT EXISTS pruebas (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100),
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO pruebas (nombre) VALUES 
    ('Test 1'),
    ('Test 2'),
    ('Test 3');
"

# Verificar que todos los contenedores están corriendo
log_info "Verificando estado de los contenedores..."
echo
echo "Contenedores creados:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo
log_success "¡Contenedores de prueba creados exitosamente!"
echo
log_info "Puedes probar el sistema de backup ejecutando:"
echo "  ./docker-backup.sh"
echo
log_info "Servicios disponibles:"
echo "  - Nginx: http://localhost:8080"
echo "  - Redis: localhost:6379"
echo "  - PostgreSQL: localhost:5432 (usuario: testuser, password: testpass)"
echo
log_warning "Para limpiar los contenedores de prueba después, ejecuta:"
echo "  ./cleanup-test.sh"

# Crear script de limpieza
cat > ./cleanup-test.sh << 'EOF'
#!/bin/bash

echo "Limpiando contenedores de prueba..."

# Detener y eliminar contenedores
docker stop test-nginx test-redis test-postgres test-alpine 2>/dev/null || true
docker rm test-nginx test-redis test-postgres test-alpine 2>/dev/null || true

# Eliminar volúmenes
docker volume rm test_nginx_logs test_redis_data test_postgres_data 2>/dev/null || true

# Eliminar directorio de datos de prueba
rm -rf ./test_data

echo "Limpieza completada."
EOF

chmod +x ./cleanup-test.sh

log_success "Script de limpieza creado: ./cleanup-test.sh"
