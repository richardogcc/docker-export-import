#!/bin/bash

# Docker Compose Generator
# Genera un docker-compose.yml basado en un backup existente
# Compatible con Linux/macOS/WSL/Windows Git Bash

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logs con colores
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

# Detectar OS y usar jq
setup_jq() {
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi
    
    # Buscar jq descargado por el script de backup
    if [[ -f "./jq" ]]; then
        export PATH=".:$PATH"
        return 0
    elif [[ -f "./jq.exe" ]]; then
        export PATH=".:$PATH"
        return 0
    fi
    
    log_error "jq no encontrado. Ejecuta primero docker-backup.sh o instala jq manualmente"
    exit 1
}

# Detectar backups disponibles
detect_backups() {
    local backup_dirs
    backup_dirs=$(find . -maxdepth 1 -type d -name "docker_backup_*" | sort -r)
    
    if [[ -z "$backup_dirs" ]]; then
        log_error "No se encontraron directorios de backup"
        exit 1
    fi
    
    echo "Backups disponibles:"
    local i=1
    while IFS= read -r dir; do
        local backup_date
        backup_date=$(echo "$dir" | sed 's/.*docker_backup_//' | sed 's/_/ /')
        echo "$i) $dir (${backup_date})"
        ((i++))
    done <<< "$backup_dirs"
    
    echo "$backup_dirs"
}

# Seleccionar backup
select_backup() {
    local backup_list="$1"
    local backup_count
    backup_count=$(echo "$backup_list" | wc -l)
    
    echo
    echo "Selecciona el backup para generar docker-compose.yml (1-$backup_count):"
    read -r backup_choice
    
    if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [[ "$backup_choice" -lt 1 ]] || [[ "$backup_choice" -gt "$backup_count" ]]; then
        log_error "Selección inválida"
        exit 1
    fi
    
    echo "$backup_list" | sed -n "${backup_choice}p"
}

# Generar docker-compose.yml
generate_docker_compose() {
    local backup_dir="$1"
    local compose_file="$backup_dir/docker-compose.yml"
    
    log_info "Generando docker-compose.yml..."
    
    # Crear encabezado del docker-compose.yml
    cat > "$compose_file" << EOF
version: '3.8'

# Docker Compose generado automáticamente desde backup
# Backup: $backup_dir
# Generado: $(date)

services:
EOF

    # Detectar contenedores en el backup
    local containers
    containers=$(find "$backup_dir/containers" -name "*.tar" -exec basename {} .tar \; 2>/dev/null || true)
    
    if [[ -z "$containers" ]]; then
        log_error "No se encontraron contenedores en el backup"
        return 1
    fi
    
    local service_count=0
    
    # Generar configuración para cada contenedor
    for container in $containers; do
        log_info "Procesando contenedor: $container"
        
        local report_file="$backup_dir/backup_report_$container.txt"
        
        # Inicio de la configuración del servicio
        cat >> "$compose_file" << EOF

  $container:
    container_name: ${container}_restored
    image: ${container}:restored
    restart: unless-stopped
EOF
        
        # Procesar volúmenes si existen
        local volumes_dir="$backup_dir/volumes/$container"
        if [[ -d "$volumes_dir" ]] && [[ -n "$(ls -A "$volumes_dir" 2>/dev/null)" ]]; then
            echo "    volumes:" >> "$compose_file"
            
            for volume_file in "$volumes_dir"/*.tar.gz; do
                if [[ -f "$volume_file" ]]; then
                    local volume_name
                    volume_name=$(basename "$volume_file" .tar.gz)
                    
                    # Obtener punto de montaje desde el reporte
                    local mount_point
                    if [[ -f "$report_file" ]]; then
                        mount_point=$(grep "Volumen: $volume_name ->" "$report_file" | sed "s/.*-> //" || echo "/data")
                    else
                        mount_point="/data"
                    fi
                    
                    echo "      - ${volume_name}:${mount_point}" >> "$compose_file"
                fi
            done
        fi
        
        # Procesar bind mounts si existen
        local bind_mounts_dir="$backup_dir/bind_mounts/$container"
        if [[ -d "$bind_mounts_dir" ]] && [[ -n "$(ls -A "$bind_mounts_dir" 2>/dev/null)" ]]; then
            if [[ -f "$report_file" ]]; then
                # Leer bind mounts desde el reporte
                while IFS= read -r line; do
                    if [[ "$line" =~ ^Bind\ Mount:\ (.*)\ -\>\ (.*) ]]; then
                        local source_path="${BASH_REMATCH[1]}"
                        local dest_path="${BASH_REMATCH[2]}"
                        
                        # Si no hay sección volumes, añadirla
                        if ! grep -q "volumes:" "$compose_file"; then
                            echo "    volumes:" >> "$compose_file"
                        fi
                        
                        echo "      - \"${source_path}:${dest_path}\"" >> "$compose_file"
                    fi
                done < "$report_file"
            fi
        fi
        
        # Añadir configuración de red
        echo "    networks:" >> "$compose_file"
        echo "      - backup_network" >> "$compose_file"
        
        # Añadir comentarios útiles
        cat >> "$compose_file" << EOF
    # NOTAS:
    # - Ajusta las variables de entorno según sea necesario
    # - Configura los puertos expuestos si es requerido
    # - Verifica las dependencias entre servicios
EOF
        
        ((service_count++))
    done
    
    # Añadir sección de volúmenes
    echo "" >> "$compose_file"
    echo "volumes:" >> "$compose_file"
    
    for container in $containers; do
        local volumes_dir="$backup_dir/volumes/$container"
        if [[ -d "$volumes_dir" ]] && [[ -n "$(ls -A "$volumes_dir" 2>/dev/null)" ]]; then
            for volume_file in "$volumes_dir"/*.tar.gz; do
                if [[ -f "$volume_file" ]]; then
                    local volume_name
                    volume_name=$(basename "$volume_file" .tar.gz)
                    echo "  ${volume_name}:" >> "$compose_file"
                    echo "    external: false" >> "$compose_file"
                fi
            done
        fi
    done
    
    # Añadir sección de redes
    cat >> "$compose_file" << EOF

networks:
  backup_network:
    driver: bridge
EOF
    
    log_success "docker-compose.yml generado: $compose_file"
    log_success "Servicios generados: $service_count"
    
    # Generar script de preparación
    local setup_script="$backup_dir/setup-compose.sh"
    cat > "$setup_script" << 'EOF'
#!/bin/bash

# Script de preparación para docker-compose
# Restaura imágenes y volúmenes antes de ejecutar docker-compose

set -e

echo "Preparando entorno para docker-compose..."

# Restaurar imágenes
echo "Restaurando imágenes..."
for image_file in images/*.tar; do
    if [[ -f "$image_file" ]]; then
        echo "Cargando imagen: $image_file"
        docker load < "$image_file"
    fi
done

# Restaurar volúmenes
echo "Restaurando volúmenes..."
for container_dir in volumes/*/; do
    if [[ -d "$container_dir" ]]; then
        container_name=$(basename "$container_dir")
        echo "Procesando volúmenes para: $container_name"
        
        for volume_file in "$container_dir"/*.tar.gz; do
            if [[ -f "$volume_file" ]]; then
                volume_name=$(basename "$volume_file" .tar.gz)
                echo "Restaurando volumen: $volume_name"
                
                # Crear volumen si no existe
                docker volume create "$volume_name" >/dev/null 2>&1 || true
                
                # Restaurar contenido
                docker run --rm \
                    -v "$volume_name:/target" \
                    -v "$(pwd)/volumes/$container_name:/backup:ro" \
                    alpine \
                    sh -c "cd /target && tar xzf /backup/${volume_name}.tar.gz" || {
                    echo "Advertencia: Error restaurando volumen $volume_name"
                }
            fi
        done
    fi
done

echo "Preparación completada."
echo "Ahora puedes ejecutar: docker-compose up -d"
EOF
    
    chmod +x "$setup_script"
    log_success "Script de preparación generado: $setup_script"
    
    # Generar README específico para el compose
    local compose_readme="$backup_dir/README-compose.md"
    cat > "$compose_readme" << EOF
# Docker Compose desde Backup

Este directorio contiene una configuración de Docker Compose generada automáticamente desde un backup.

## Archivos generados

- \`docker-compose.yml\`: Configuración principal de Docker Compose
- \`setup-compose.sh\`: Script para preparar el entorno antes de ejecutar compose
- \`README-compose.md\`: Este archivo

## Uso

### 1. Preparar el entorno
\`\`\`bash
chmod +x setup-compose.sh
./setup-compose.sh
\`\`\`

### 2. Ejecutar los servicios
\`\`\`bash
docker-compose up -d
\`\`\`

### 3. Verificar el estado
\`\`\`bash
docker-compose ps
docker-compose logs
\`\`\`

## Notas importantes

1. **Configuración manual**: Es posible que necesites ajustar:
   - Variables de entorno
   - Puertos expuestos
   - Dependencias entre servicios
   - Configuración de red

2. **Bind mounts**: Los bind mounts están incluidos en el compose, pero asegúrate de que las rutas del host existan.

3. **Volúmenes**: Los volúmenes se restauran automáticamente con el script \`setup-compose.sh\`.

4. **Imágenes**: Las imágenes se cargan automáticamente con el script de preparación.

## Comandos útiles

\`\`\`bash
# Ver logs de un servicio específico
docker-compose logs [nombre_servicio]

# Reiniciar un servicio
docker-compose restart [nombre_servicio]

# Detener todos los servicios
docker-compose down

# Detener y eliminar volúmenes
docker-compose down -v
\`\`\`

## Personalización

Edita el archivo \`docker-compose.yml\` según tus necesidades antes de ejecutar los servicios.
EOF
    
    log_success "README específico generado: $compose_readme"
}

# Función principal
main() {
    echo "=========================================="
    echo "  DOCKER COMPOSE GENERATOR v1.0"
    echo "=========================================="
    echo
    
    # Verificaciones iniciales
    setup_jq
    
    # Detectar backups
    local backup_list
    backup_list=$(detect_backups)
    
    # Seleccionar backup
    local selected_backup
    selected_backup=$(select_backup "$backup_list")
    
    log_info "Backup seleccionado: $selected_backup"
    
    # Generar docker-compose.yml
    generate_docker_compose "$selected_backup"
    
    echo
    echo "=========================================="
    echo "    GENERACIÓN COMPLETADA"
    echo "=========================================="
    log_success "Docker Compose generado en: $selected_backup"
    echo
    log_info "Para usar el docker-compose:"
    echo "1. cd $selected_backup"
    echo "2. ./setup-compose.sh"
    echo "3. docker-compose up -d"
    echo
    log_warning "Recuerda revisar y ajustar la configuración según tus necesidades"
}

# Ejecutar función principal
main "$@"
