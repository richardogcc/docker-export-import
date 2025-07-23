#!/bin/bash

# Docker Restore Script
# Restaura contenedores, imágenes, volúmenes y bind mounts desde backups
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
    echo "Selecciona el backup a restaurar (1-$backup_count):"
    read -r backup_choice
    
    if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [[ "$backup_choice" -lt 1 ]] || [[ "$backup_choice" -gt "$backup_count" ]]; then
        log_error "Selección inválida"
        exit 1
    fi
    
    echo "$backup_list" | sed -n "${backup_choice}p"
}

# Detectar contenedores en el backup
detect_containers_in_backup() {
    local backup_dir="$1"
    
    if [[ ! -d "$backup_dir/containers" ]]; then
        log_error "No se encontró directorio de contenedores en el backup"
        exit 1
    fi
    
    find "$backup_dir/containers" -name "*.tar" -exec basename {} .tar \;
}

# Restaurar imagen
restore_image() {
    local container_name="$1"
    local backup_dir="$2"
    
    log_info "Restaurando imagen para $container_name..."
    
    # Buscar archivo de imagen
    local image_file
    image_file=$(find "$backup_dir/images" -name "*.tar" | head -1)
    
    if [[ ! -f "$image_file" ]]; then
        log_error "No se encontró archivo de imagen para $container_name"
        return 1
    fi
    
    # Cargar imagen
    docker load < "$image_file" || {
        log_error "Error cargando imagen desde $image_file"
        return 1
    }
    
    log_success "Imagen restaurada exitosamente"
}

# Restaurar volúmenes
restore_volumes() {
    local container_name="$1"
    local backup_dir="$2"
    
    local volumes_dir="$backup_dir/volumes/$container_name"
    
    if [[ ! -d "$volumes_dir" ]]; then
        log_info "No hay volúmenes para restaurar en $container_name"
        return 0
    fi
    
    log_info "Restaurando volúmenes para $container_name..."
    
    local volume_count=0
    for volume_file in "$volumes_dir"/*.tar.gz; do
        if [[ -f "$volume_file" ]]; then
            local volume_name
            volume_name=$(basename "$volume_file" .tar.gz)
            
            log_info "Restaurando volumen: $volume_name"
            
            # Crear volumen si no existe
            docker volume create "$volume_name" >/dev/null 2>&1 || true
            
            # Restaurar contenido del volumen
            docker run --rm \
                -v "$volume_name:/target" \
                -v "$volumes_dir:/backup:ro" \
                alpine \
                sh -c "cd /target && tar xzf /backup/${volume_name}.tar.gz" || {
                log_warning "Error restaurando volumen: $volume_name"
                continue
            }
            
            ((volume_count++))
        fi
    done
    
    log_success "Restaurados $volume_count volúmenes para $container_name"
}

# Restaurar bind mounts
restore_bind_mounts() {
    local container_name="$1"
    local backup_dir="$2"
    
    local bind_mounts_dir="$backup_dir/bind_mounts/$container_name"
    
    if [[ ! -d "$bind_mounts_dir" ]]; then
        log_info "No hay bind mounts para restaurar en $container_name"
        return 0
    fi
    
    log_warning "Se detectaron bind mounts para $container_name"
    echo "¿Deseas restaurar los bind mounts? (esto copiará archivos al sistema host)"
    echo "1) Sí, restaurar bind mounts"
    echo "2) No, solo mostrar ubicaciones"
    echo "3) Omitir bind mounts"
    read -r bind_choice
    
    case $bind_choice in
        1)
            log_info "Restaurando bind mounts para $container_name..."
            
            # Leer el reporte para obtener las rutas originales
            local report_file="$backup_dir/backup_report_$container_name.txt"
            if [[ -f "$report_file" ]]; then
                local mount_count=0
                while IFS= read -r line; do
                    if [[ "$line" =~ ^Bind\ Mount:\ (.*)\ -\>\ (.*) ]]; then
                        local source_path="${BASH_REMATCH[1]}"
                        local dest_path="${BASH_REMATCH[2]}"
                        
                        log_info "Restaurando: $source_path"
                        
                        # Crear directorio padre si no existe
                        mkdir -p "$(dirname "$source_path")"
                        
                        # Copiar desde backup
                        if [[ -d "$bind_mounts_dir$dest_path" ]]; then
                            cp -rp "$bind_mounts_dir$dest_path" "$source_path" 2>/dev/null || {
                                log_warning "No se pudo restaurar completamente: $source_path"
                            }
                        elif [[ -f "$bind_mounts_dir$dest_path" ]]; then
                            cp -p "$bind_mounts_dir$dest_path" "$source_path" 2>/dev/null || {
                                log_warning "No se pudo restaurar: $source_path"
                            }
                        fi
                        
                        ((mount_count++))
                    fi
                done < "$report_file"
                
                log_success "Restaurados $mount_count bind mounts"
            else
                log_warning "No se encontró reporte de backup, no se pueden restaurar bind mounts automáticamente"
            fi
            ;;
        2)
            log_info "Bind mounts disponibles en: $bind_mounts_dir"
            log_info "Puedes copiarlos manualmente según sea necesario"
            ;;
        3)
            log_info "Bind mounts omitidos"
            ;;
        *)
            log_warning "Opción inválida, omitiendo bind mounts"
            ;;
    esac
}

# Restaurar contenedor
restore_container() {
    local container_name="$1"
    local backup_dir="$2"
    
    log_info "=== Restaurando contenedor $container_name ==="
    
    local container_file="$backup_dir/containers/${container_name}.tar"
    
    if [[ ! -f "$container_file" ]]; then
        log_error "No se encontró archivo de contenedor: $container_file"
        return 1
    fi
    
    # Verificar si el contenedor ya existe
    if docker inspect "$container_name" >/dev/null 2>&1; then
        log_warning "El contenedor '$container_name' ya existe"
        echo "¿Qué deseas hacer?"
        echo "1) Detener y eliminar el existente, luego restaurar"
        echo "2) Restaurar con un nuevo nombre"
        echo "3) Omitir este contenedor"
        read -r container_choice
        
        case $container_choice in
            1)
                log_info "Eliminando contenedor existente..."
                docker stop "$container_name" 2>/dev/null || true
                docker rm "$container_name" 2>/dev/null || true
                ;;
            2)
                echo "Ingresa el nuevo nombre para el contenedor:"
                read -r new_container_name
                if [[ -n "$new_container_name" ]]; then
                    container_name="$new_container_name"
                else
                    log_error "Nombre inválido"
                    return 1
                fi
                ;;
            3)
                log_info "Omitiendo $container_name"
                return 0
                ;;
            *)
                log_warning "Opción inválida, omitiendo contenedor"
                return 1
                ;;
        esac
    fi
    
    # Restaurar imagen primero
    restore_image "$container_name" "$backup_dir"
    
    # Restaurar volúmenes
    restore_volumes "$container_name" "$backup_dir"
    
    # Restaurar bind mounts
    restore_bind_mounts "$container_name" "$backup_dir"
    
    # Importar contenedor
    log_info "Importando contenedor $container_name..."
    docker import "$container_file" "${container_name}:restored" || {
        log_error "Error importando contenedor desde $container_file"
        return 1
    }
    
    log_success "Contenedor $container_name restaurado como imagen ${container_name}:restored"
    log_info "Para crear un nuevo contenedor, usa: docker run -it ${container_name}:restored"
    log_warning "Nota: Es posible que necesites recrear el contenedor con la configuración específica (puertos, variables de entorno, etc.)"
    
    return 0
}

# Generar reporte de restauración
generate_restore_report() {
    local backup_dir="$1"
    local restored_containers="$2"
    local report_file="$backup_dir/restore_report.txt"
    
    log_info "Generando reporte de restauración..."
    
    cat > "$report_file" << EOF
=== REPORTE DE RESTAURACIÓN ===
Fecha: $(date)
Backup utilizado: $backup_dir

=== CONTENEDORES RESTAURADOS ===
EOF
    
    for container in $restored_containers; do
        echo "- $container" >> "$report_file"
    done
    
    echo "" >> "$report_file"
    echo "=== NOTAS ===" >> "$report_file"
    echo "- Las imágenes fueron restauradas con éxito" >> "$report_file"
    echo "- Los volúmenes fueron recreados con su contenido original" >> "$report_file"
    echo "- Los bind mounts pueden requerir configuración manual" >> "$report_file"
    echo "- Es posible que necesites recrear los contenedores con su configuración específica" >> "$report_file"
    
    log_success "Reporte de restauración generado: $report_file"
}

# Función principal
main() {
    echo "=========================================="
    echo "    DOCKER RESTORE SYSTEM v1.0"
    echo "=========================================="
    echo
    
    # Verificaciones iniciales
    check_docker
    setup_jq
    
    # Detectar backups
    local backup_list
    backup_list=$(detect_backups)
    
    # Seleccionar backup
    local selected_backup
    selected_backup=$(select_backup "$backup_list")
    
    log_info "Backup seleccionado: $selected_backup"
    
    # Detectar contenedores en el backup
    local containers_in_backup
    containers_in_backup=$(detect_containers_in_backup "$selected_backup")
    
    if [[ -z "$containers_in_backup" ]]; then
        log_error "No se encontraron contenedores en el backup"
        exit 1
    fi
    
    echo
    log_info "Contenedores disponibles en el backup:"
    echo "$containers_in_backup"
    echo
    
    # Seleccionar contenedores a restaurar
    echo "Ingresa los nombres de los contenedores a restaurar (separados por espacios):"
    echo "O presiona Enter para restaurar TODOS los contenedores del backup:"
    read -r containers_input
    
    local containers_to_restore
    if [[ -z "$containers_input" ]]; then
        containers_to_restore="$containers_in_backup"
    else
        containers_to_restore="$containers_input"
    fi
    
    # Restaurar cada contenedor
    local total_containers=0
    local successful_restores=0
    local restored_list=""
    
    for container in $containers_to_restore; do
        ((total_containers++))
        
        # Verificar que el contenedor existe en el backup
        if echo "$containers_in_backup" | grep -q "^$container$"; then
            if restore_container "$container" "$selected_backup"; then
                ((successful_restores++))
                restored_list="$restored_list $container"
            fi
        else
            log_error "Contenedor '$container' no encontrado en el backup"
        fi
        
        echo
    done
    
    # Generar reporte de restauración
    if [[ $successful_restores -gt 0 ]]; then
        generate_restore_report "$selected_backup" "$restored_list"
    fi
    
    # Resumen final
    echo "=========================================="
    echo "    RESUMEN DE LA RESTAURACIÓN"
    echo "=========================================="
    log_info "Total de contenedores procesados: $total_containers"
    log_success "Restauraciones exitosas: $successful_restores"
    
    if [[ $successful_restores -gt 0 ]]; then
        log_success "Restauración completada desde: $selected_backup"
        log_info "Contenedores restaurados:$restored_list"
        echo
        log_warning "IMPORTANTE: Los contenedores han sido importados como imágenes."
        log_warning "Usa 'docker run' para crear nuevos contenedores con la configuración deseada."
        log_info "Consulta el reporte de backup original para ver la configuración previa."
    fi
}

# Ejecutar función principal
main "$@"
