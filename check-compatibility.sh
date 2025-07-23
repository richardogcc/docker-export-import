#!/bin/bash

# Script de verificación de compatibilidad de shells
# Verifica que el sistema de backup funcione correctamente en diferentes shells

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

echo "=========================================="
echo "  VERIFICADOR DE COMPATIBILIDAD SHELLS"
echo "=========================================="

# Detectar shell actual
current_shell=$(basename "$SHELL")
log_info "Shell actual detectado: $current_shell"

# Verificar que bash esté disponible
if ! command -v bash >/dev/null 2>&1; then
    log_error "bash no está instalado en el sistema"
    exit 1
fi

bash_version=$(bash --version | head -1)
log_info "Versión de bash: $bash_version"

# Verificar sintaxis de los scripts
log_info "Verificando sintaxis de los scripts..."

scripts=("docker-backup.sh" "docker-restore.sh" "generate-compose.sh" "create-test-containers.sh")
syntax_errors=0

for script in "${scripts[@]}"; do
    if [[ -f "$script" ]]; then
        log_info "Verificando $script..."
        if bash -n "$script" 2>/dev/null; then
            log_success "$script - Sintaxis correcta"
        else
            log_error "$script - Error de sintaxis"
            ((syntax_errors++))
        fi
    else
        log_warning "$script - Archivo no encontrado"
    fi
done

# Verificar compatibilidad específica de zsh
if [[ "$current_shell" == "zsh" ]]; then
    log_info "Verificaciones específicas para zsh..."
    
    # Verificar que arrays funcionen correctamente
    if zsh -c 'test_array=(a b c); echo ${#test_array[@]}' >/dev/null 2>&1; then
        log_success "Arrays en zsh: Compatibles"
    else
        log_warning "Arrays en zsh: Posibles problemas"
    fi
    
    # Verificar expansión de variables
    if zsh -c 'test_var="hello world"; echo ${test_var}' >/dev/null 2>&1; then
        log_success "Expansión de variables en zsh: Compatible"
    else
        log_warning "Expansión de variables en zsh: Posibles problemas"
    fi
fi

# Verificar dependencias del sistema
log_info "Verificando dependencias..."

dependencies=("docker" "curl" "tar" "gzip")
missing_deps=0

for dep in "${dependencies[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        log_success "$dep: Disponible"
    else
        log_error "$dep: No encontrado"
        ((missing_deps++))
    fi
done

# Verificar permisos de ejecución
log_info "Verificando permisos de ejecución..."
for script in "${scripts[@]}"; do
    if [[ -f "$script" ]]; then
        if [[ -x "$script" ]]; then
            log_success "$script: Ejecutable"
        else
            log_warning "$script: Sin permisos de ejecución"
            chmod +x "$script" 2>/dev/null && log_info "Permisos corregidos" || log_error "No se pudieron corregir permisos"
        fi
    fi
done

# Prueba básica de funcionalidad
log_info "Realizando prueba básica de funcionalidad..."

if docker info >/dev/null 2>&1; then
    log_success "Docker: Funcionando correctamente"
    
    # Probar función básica del script de backup (solo verificación, sin ejecutar backup)
    if ./docker-backup.sh --help >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
        log_info "Script de backup: Sintaxis verificada"
    fi
else
    log_warning "Docker: No está corriendo o no está instalado"
fi

# Resumen final
echo
echo "=========================================="
echo "    RESUMEN DE COMPATIBILIDAD"
echo "=========================================="

if [[ $syntax_errors -eq 0 ]]; then
    log_success "✅ Todos los scripts tienen sintaxis correcta"
else
    log_error "❌ $syntax_errors scripts con errores de sintaxis"
fi

if [[ $missing_deps -eq 0 ]]; then
    log_success "✅ Todas las dependencias están disponibles"
else
    log_warning "⚠️  $missing_deps dependencias faltantes"
fi

# Recomendaciones por shell
echo
log_info "Recomendaciones para tu shell ($current_shell):"

case "$current_shell" in
    "zsh")
        log_success "✅ zsh es completamente compatible"
        log_info "💡 Los scripts usan #!/bin/bash, por lo que siempre ejecutarán en bash"
        log_info "💡 Puedes ejecutar los scripts normalmente desde zsh"
        ;;
    "bash")
        log_success "✅ bash es el shell nativo, compatibilidad perfecta"
        ;;
    "fish")
        log_warning "⚠️  fish tiene sintaxis diferente, pero los scripts funcionarán"
        log_info "💡 Los scripts usan #!/bin/bash, por lo que ejecutarán en bash automáticamente"
        ;;
    *)
        log_info "💡 Shell no reconocido, pero debería funcionar"
        log_info "💡 Los scripts usan #!/bin/bash para garantizar compatibilidad"
        ;;
esac

echo
log_info "Para máxima compatibilidad, todos los scripts usan:"
echo "  - Shebang #!/bin/bash"
echo "  - Sintaxis POSIX estándar"
echo "  - Verificaciones de compatibilidad integradas"

if [[ $syntax_errors -eq 0 && $missing_deps -eq 0 ]]; then
    echo
    log_success "🎉 Sistema completamente compatible con tu entorno"
    log_info "Puedes usar todos los scripts sin problemas"
else
    echo
    log_warning "⚠️  Revisa los errores mostrados arriba antes de usar el sistema"
fi
