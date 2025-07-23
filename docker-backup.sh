#!/bin/bash

# Docker Backup Script
# Exporta contenedores, imágenes, volúmenes y bind mounts
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

# Verificar que Docker esté corriendo
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker no está corriendo o no está instalado"
        exit 1
    fi
}

# Detectar OS y descargar jq si no existe
install_jq() {
    if command -v jq >/dev/null 2>&1; then
        log_info "jq ya está instalado"
        return 0
    fi

    log_warning "jq no está instalado. Descargando..."
    
    local os_type
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="linux64"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="osx-amd64"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        os_type="win64"
    else
        log_error "Sistema operativo no soportado para descarga automática de jq"
        log_info "Por favor instala jq manualmente desde: https://stedolan.github.io/jq/"
        exit 1
    fi

    local jq_url="https://github.com/stedolan/jq/releases/latest/download/jq-${os_type}"
    if [[ "$os_type" == "win64" ]]; then
        jq_url="${jq_url}.exe"
    fi

    local jq_path="./jq"
    if [[ "$os_type" == "win64" ]]; then
        jq_path="./jq.exe"
    fi

    if curl -L -o "$jq_path" "$jq_url" 2>/dev/null; then
        chmod +x "$jq_path"
        export PATH=".:$PATH"
        log_success "jq descargado exitosamente"
    else
        log_error "Error descargando jq"
        exit 1
    fi
}

# Obtener lista de contenedores corriendo
get_running_containers() {
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | tail -n +2
}

# Obtener información detallada del contenedor
get_container_info() {
    local container_name="$1"
    docker inspect "$container_name"
}

# Exportar bind mounts
export_bind_mounts() {
    local container_name="$1"
    local backup_dir="$2"
    local bind_mounts_dir="$backup_dir/bind_mounts/$container_name"
    
    log_info "Exportando bind mounts para $container_name..."
    
    # Crear directorio para bind mounts
    mkdir -p "$bind_mounts_dir"
    
    # Obtener bind mounts usando jq
    local mounts
    mounts=$(docker inspect "$container_name" | jq -r '.[0].Mounts[] | select(.Type == "bind") | "\(.Source)|\(.Destination)"')
    
    if [[ -z "$mounts" ]]; then
        log_info "No se encontraron bind mounts para $container_name"
        return 0
    fi
    
    local mount_count=0
    while IFS='|' read -r source dest; do
        if [[ -n "$source" && -n "$dest" ]]; then
            log_info "Copiando bind mount: $source -> $dest"
            
            # Crear estructura de directorios
            local target_dir="$bind_mounts_dir$(dirname "$dest")"
            mkdir -p "$target_dir"
            
            # Copiar preservando permisos y estructura
            if [[ -d "$source" ]]; then
                cp -rp "$source" "$bind_mounts_dir$dest" 2>/dev/null || {
                    log_warning "No se pudo copiar completamente: $source"
                }
            elif [[ -f "$source" ]]; then
                cp -p "$source" "$bind_mounts_dir$dest" 2>/dev/null || {
                    log_warning "No se pudo copiar: $source"
                }
            fi
            
            ((mount_count++))
        fi
    done <<< "$mounts"
    
    log_success "Exportados $mount_count bind mounts para $container_name"
}

# Exportar volúmenes
export_volumes() {
    local container_name="$1"
    local backup_dir="$2"
    local volumes_dir="$backup_dir/volumes/$container_name"
    
    log_info "Exportando volúmenes para $container_name..."
    
    # Crear directorio para volúmenes
    mkdir -p "$volumes_dir"
    
    # Obtener volúmenes usando jq
    local volumes
    volumes=$(docker inspect "$container_name" | jq -r '.[0].Mounts[] | select(.Type == "volume") | "\(.Name)|\(.Destination)"')
    
    if [[ -z "$volumes" ]]; then
        log_info "No se encontraron volúmenes para $container_name"
        return 0
    fi
    
    local volume_count=0
    while IFS='|' read -r volume_name dest; do
        if [[ -n "$volume_name" && -n "$dest" ]]; then
            log_info "Exportando volumen: $volume_name -> $dest"
            
            # Crear archivo tar del volumen
            local volume_tar="$volumes_dir/${volume_name}.tar"
            
            # Usar contenedor temporal para extraer contenido del volumen
            docker run --rm \
                -v "$volume_name:/source:ro" \
                -v "$volumes_dir:/backup" \
                alpine \
                tar czf "/backup/${volume_name}.tar.gz" -C /source . 2>/dev/null || {
                log_warning "Error exportando volumen: $volume_name"
            }
            
            ((volume_count++))
        fi
    done <<< "$volumes"
    
    log_success "Exportados $volume_count volúmenes para $container_name"
}

# Generar reporte de backup
generate_backup_report() {
    local container_name="$1"
    local backup_dir="$2"
    local report_file="$backup_dir/backup_report_$container_name.txt"
    
    log_info "Generando reporte para $container_name..."
    
    local container_info
    container_info=$(docker inspect "$container_name")
    
    local container_id
    container_id=$(echo "$container_info" | jq -r '.[0].Id')
    
    local image_name
    image_name=$(echo "$container_info" | jq -r '.[0].Config.Image')
    
    local image_id
    image_id=$(echo "$container_info" | jq -r '.[0].Image')
    
    # Crear reporte
    cat > "$report_file" << EOF
=== REPORTE DE BACKUP ===
Fecha: $(date)
Contenedor: $container_name
ID del Contenedor: $container_id
Imagen: $image_name
ID de la Imagen: $image_id

=== VOLÚMENES ===
EOF
    
    # Añadir información de volúmenes
    local volumes
    volumes=$(echo "$container_info" | jq -r '.[0].Mounts[] | select(.Type == "volume") | "Volumen: \(.Name) -> \(.Destination)"')
    if [[ -n "$volumes" ]]; then
        echo "$volumes" >> "$report_file"
    else
        echo "No se encontraron volúmenes tipo 'volume'" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "=== BIND MOUNTS ===" >> "$report_file"
    
    # Añadir información de bind mounts
    local bind_mounts
    bind_mounts=$(echo "$container_info" | jq -r '.[0].Mounts[] | select(.Type == "bind") | "Bind Mount: \(.Source) -> \(.Destination)"')
    if [[ -n "$bind_mounts" ]]; then
        echo "$bind_mounts" >> "$report_file"
    else
        echo "No se encontraron bind mounts" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "=== CONFIGURACIÓN DEL CONTENEDOR ===" >> "$report_file"
    echo "Estado: $(docker inspect "$container_name" | jq -r '.[0].State.Status')" >> "$report_file"
    echo "Reinicio: $(docker inspect "$container_name" | jq -r '.[0].HostConfig.RestartPolicy.Name')" >> "$report_file"
    echo "Puertos: $(docker inspect "$container_name" | jq -r '.[0].NetworkSettings.Ports | keys[]?' 2>/dev/null || echo "No hay puertos expuestos")" >> "$report_file"
    
    log_success "Reporte generado: $report_file"
}

# Función principal de backup
backup_container() {
    local container_name="$1"
    local backup_dir="$2"
    
    log_info "=== Iniciando backup de $container_name ==="
    
    # Crear directorios necesarios
    mkdir -p "$backup_dir/containers"
    mkdir -p "$backup_dir/images"
    
    # Obtener información del contenedor
    local image_name
    image_name=$(docker inspect "$container_name" | jq -r '.[0].Config.Image')
    
    # Exportar contenedor
    log_info "Exportando contenedor $container_name..."
    docker export "$container_name" > "$backup_dir/containers/${container_name}.tar" || {
        log_error "Error exportando contenedor $container_name"
        return 1
    }
    log_success "Contenedor exportado: ${container_name}.tar"
    
    # Exportar imagen
    log_info "Exportando imagen $image_name..."
    local safe_image_name
    safe_image_name=$(echo "$image_name" | tr '/' '_' | tr ':' '_')
    docker save "$image_name" > "$backup_dir/images/${safe_image_name}.tar" || {
        log_error "Error exportando imagen $image_name"
        return 1
    }
    log_success "Imagen exportada: ${safe_image_name}.tar"
    
    # Exportar volúmenes
    export_volumes "$container_name" "$backup_dir"
    
    # Exportar bind mounts
    export_bind_mounts "$container_name" "$backup_dir"
    
    # Generar reporte
    generate_backup_report "$container_name" "$backup_dir"
    
    log_success "=== Backup de $container_name completado ==="
}

# Función principal
main() {
    echo "=========================================="
    echo "    DOCKER BACKUP SYSTEM v1.0"
    echo "=========================================="
    echo
    
    # Verificaciones iniciales
    check_docker
    install_jq
    
    # Mostrar contenedores disponibles
    log_info "Contenedores corriendo:"
    echo
    get_running_containers
    echo
    
    # Solicitar contenedores a respaldar
    echo "Ingresa los nombres de los contenedores a respaldar (separados por espacios):"
    echo "O presiona Enter para respaldar TODOS los contenedores corriendo:"
    read -r containers_input
    
    local containers_to_backup
    if [[ -z "$containers_input" ]]; then
        # Obtener todos los contenedores corriendo
        containers_to_backup=$(docker ps --format "{{.Names}}")
    else
        containers_to_backup="$containers_input"
    fi
    
    if [[ -z "$containers_to_backup" ]]; then
        log_warning "No hay contenedores para respaldar"
        exit 0
    fi
    
    # Crear directorio de backup con timestamp
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_dir="docker_backup_$timestamp"
    
    mkdir -p "$backup_dir"
    log_info "Directorio de backup creado: $backup_dir"
    
    # Backup de cada contenedor
    local total_containers=0
    local successful_backups=0
    
    for container in $containers_to_backup; do
        ((total_containers++))
        
        # Verificar que el contenedor existe
        if docker inspect "$container" >/dev/null 2>&1; then
            if backup_container "$container" "$backup_dir"; then
                ((successful_backups++))
            fi
        else
            log_error "Contenedor '$container' no existe"
        fi
    done
    
    # Resumen final
    echo
    echo "=========================================="
    echo "    RESUMEN DEL BACKUP"
    echo "=========================================="
    log_info "Total de contenedores procesados: $total_containers"
    log_success "Backups exitosos: $successful_backups"
    
    if [[ $successful_backups -gt 0 ]]; then
        log_success "Backup completo guardado en: $backup_dir"
        log_info "Tamaño total del backup: $(du -sh "$backup_dir" | cut -f1)"
    fi
    
    echo
    log_info "Para restaurar, usa: ./docker-restore.sh"
}

# Ejecutar función principal
main "$@"
