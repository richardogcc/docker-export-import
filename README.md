# Docker Backup & Restore System

Un sistema completo de backup y restauración para Docker que funciona en Linux, macOS, WSL y Windows con Git Bash. Permite exportar y restaurar contenedores, imágenes, volúmenes y bind mounts de forma automatizada.

## 🚀 Características

- **Backup completo**: Exporta contenedores, imágenes, volúmenes y bind mounts
- **Restauración inteligente**: Restaura todo de forma automatizada con opciones flexibles
- **Multiplataforma**: Compatible con Linux, macOS, WSL y Windows (Git Bash)
- **Informes detallados**: Genera reportes completos de backup y restauración
- **Docker Compose**: Genera automáticamente archivos docker-compose.yml desde backups
- **Instalación automática de dependencias**: Descarga jq automáticamente si no está disponible
- **Manejo seguro de espacios**: Funciona correctamente con nombres y rutas que contienen espacios

## 📁 Estructura del proyecto

```
docker-backup-system/
├── docker-backup.sh          # Script principal de backup
├── docker-restore.sh         # Script principal de restauración  
├── generate-compose.sh       # Generador de docker-compose.yml
├── create-test-containers.sh # Creador de contenedores de prueba
├── check-compatibility.sh    # Verificador de compatibilidad de shells
├── config.conf              # Archivo de configuración
├── README.md                 # Este archivo
└── docker_backup_YYYYMMDD_HHMMSS/    # Directorios de backup generados
    ├── containers/           # Archivos .tar de contenedores
    ├── images/              # Archivos .tar de imágenes
    ├── volumes/             # Archivos .tar.gz de volúmenes
    ├── bind_mounts/         # Copia de bind mounts
    ├── backup_report_*.txt  # Reportes de backup por contenedor
    ├── restore_report.txt   # Reporte de restauración (generado al restaurar)
    ├── docker-compose.yml   # Docker Compose generado (opcional)
    ├── setup-compose.sh     # Script de preparación para compose
    └── README-compose.md    # Documentación específica del compose
```

## 🛠 Requisitos

### Requisitos básicos
- **Docker**: Instalado y funcionando
- **Bash**: Shell compatible (incluido en Git Bash para Windows)
- **Permisos**: El usuario debe tener permisos para ejecutar comandos Docker

### Dependencias automáticas
- **jq**: Se descarga automáticamente si no está instalado
- **curl**: Para descargar jq (generalmente preinstalado)

### Sistemas soportados
- ✅ Linux (todas las distribuciones con bash)
- ✅ macOS
- ✅ Windows WSL (Windows Subsystem for Linux)
- ✅ Windows con Git Bash

### Shells compatibles
- ✅ **bash** (nativo, compatibilidad perfecta)
- ✅ **zsh** (completamente compatible - macOS por defecto)
- ✅ **fish** (funciona a través del shebang #!/bin/bash)
- ✅ Otros shells POSIX (ejecutan en bash automáticamente)

## 🚀 Instalación

1. **Clonar o descargar** los scripts:
```bash
git clone <repository-url>
cd docker-backup-system
```

2. **Dar permisos de ejecución**:
```bash
chmod +x docker-backup.sh
chmod +x docker-restore.sh  
chmod +x generate-compose.sh
```

3. **Verificar que Docker esté funcionando**:
```bash
docker info
```

4. **Verificar compatibilidad** (opcional):
```bash
./check-compatibility.sh
```

## 📖 Uso

### 1. Realizar Backup

```bash
./docker-backup.sh
```

El script te guiará a través del proceso:

1. **Muestra contenedores corriendo**: Lista todos los contenedores activos
2. **Selección de contenedores**: Puedes elegir contenedores específicos o respaldar todos
3. **Proceso automático**: 
   - Exporta cada contenedor como `.tar`
   - Exporta las imágenes usadas
   - Exporta volúmenes con su contenido
   - Copia bind mounts preservando estructura
   - Genera reportes detallados
4. **Resultado**: Carpeta `docker_backup_YYYYMMDD_HHMMSS` con todo el contenido

#### Ejemplo de uso del backup:
```bash
$ ./docker-backup.sh

==========================================
    DOCKER BACKUP SYSTEM v1.0
==========================================

[INFO] Docker está funcionando correctamente
[INFO] jq ya está instalado
[INFO] Contenedores corriendo:

nginx-web        nginx:latest    Up 2 hours
mysql-db         mysql:8.0       Up 1 hour
redis-cache      redis:alpine    Up 30 minutes

Ingresa los nombres de los contenedores a respaldar (separados por espacios):
O presiona Enter para respaldar TODOS los contenedores corriendo:
nginx-web mysql-db

[INFO] Directorio de backup creado: docker_backup_20250723_143052
[INFO] === Iniciando backup de nginx-web ===
[INFO] Exportando contenedor nginx-web...
[SUCCESS] Contenedor exportado: nginx-web.tar
[INFO] Exportando imagen nginx:latest...
[SUCCESS] Imagen exportada: nginx_latest.tar
[INFO] Exportando volúmenes para nginx-web...
[SUCCESS] Exportados 1 volúmenes para nginx-web
[INFO] Exportando bind mounts para nginx-web...
[SUCCESS] Exportados 2 bind mounts para nginx-web
[SUCCESS] === Backup de nginx-web completado ===
```

### 2. Restaurar desde Backup

```bash
./docker-restore.sh
```

El script de restauración:

1. **Detecta backups disponibles**: Muestra todos los directorios de backup
2. **Selección de backup**: Elige qué backup restaurar
3. **Selección de contenedores**: Elige qué contenedores restaurar del backup
4. **Proceso de restauración**:
   - Restaura imágenes con `docker load`
   - Recrea volúmenes con su contenido original
   - Maneja conflictos de nombres de contenedores
   - Ofrece opciones para bind mounts
   - Genera reporte de restauración

#### Ejemplo de restauración:
```bash
$ ./docker-restore.sh

==========================================
    DOCKER RESTORE SYSTEM v1.0
==========================================

Backups disponibles:
1) ./docker_backup_20250723_143052 (20250723 143052)
2) ./docker_backup_20250722_091030 (20250722 091030)

Selecciona el backup a restaurar (1-2): 1

[INFO] Backup seleccionado: ./docker_backup_20250723_143052
[INFO] Contenedores disponibles en el backup:
nginx-web
mysql-db

Ingresa los nombres de los contenedores a restaurar (separados por espacios):
O presiona Enter para restaurar TODOS los contenedores del backup:
nginx-web

[INFO] === Restaurando contenedor nginx-web ===
[INFO] Restaurando imagen para nginx-web...
[SUCCESS] Imagen restaurada exitosamente
[INFO] Restaurando volúmenes para nginx-web...
[SUCCESS] Restaurados 1 volúmenes para nginx-web
[SUCCESS] Contenedor nginx-web restaurado como imagen nginx-web:restored
```

### 3. Generar Docker Compose

```bash
./generate-compose.sh
```

Este script:

1. **Selecciona un backup**: Elige de los backups disponibles
2. **Genera docker-compose.yml**: Crea configuración basada en el backup
3. **Crea script de preparación**: `setup-compose.sh` para restaurar imágenes y volúmenes
4. **Genera documentación**: README específico para el compose

#### Uso del Docker Compose generado:
```bash
# Ir al directorio del backup
cd docker_backup_20250723_143052

# Preparar el entorno (restaurar imágenes y volúmenes)
./setup-compose.sh

# Levantar los servicios
docker-compose up -d

# Verificar estado
docker-compose ps
```

## 📊 Informes Generados

### Reporte de Backup (`backup_report_[contenedor].txt`)
```
=== REPORTE DE BACKUP ===
Fecha: Thu Jul 23 14:30:52 UTC 2025
Contenedor: nginx-web
ID del Contenedor: a1b2c3d4e5f6...
Imagen: nginx:latest
ID de la Imagen: sha256:abc123...

=== VOLÚMENES ===
Volumen: nginx_data -> /var/www/html
Volumen: nginx_logs -> /var/log/nginx

=== BIND MOUNTS ===
Bind Mount: /home/user/web -> /usr/share/nginx/html
Bind Mount: /home/user/config -> /etc/nginx/conf.d

=== CONFIGURACIÓN DEL CONTENEDOR ===
Estado: running
Reinicio: unless-stopped
Puertos: 80/tcp, 443/tcp
```

### Reporte de Restauración (`restore_report.txt`)
```
=== REPORTE DE RESTAURACIÓN ===
Fecha: Thu Jul 23 15:45:20 UTC 2025
Backup utilizado: ./docker_backup_20250723_143052

=== CONTENEDORES RESTAURADOS ===
- nginx-web
- mysql-db

=== NOTAS ===
- Las imágenes fueron restauradas con éxito
- Los volúmenes fueron recreados con su contenido original
- Los bind mounts pueden requerir configuración manual
- Es posible que necesites recrear los contenedores con su configuración específica
```

## 🔧 Funcionalidades Avanzadas

### Manejo de Conflictos

**Contenedores existentes**: Al restaurar, si un contenedor ya existe:
- Opción 1: Eliminar el existente y restaurar
- Opción 2: Restaurar con nuevo nombre
- Opción 3: Omitir

**Bind Mounts**: Durante la restauración:
- Opción 1: Restaurar automáticamente
- Opción 2: Solo mostrar ubicaciones para copia manual
- Opción 3: Omitir completamente

### Compatibilidad con Espacios

Los scripts manejan correctamente:
- Nombres de contenedores con espacios
- Rutas de bind mounts con espacios
- Nombres de volúmenes con caracteres especiales

### Instalación Automática de jq

El sistema detecta automáticamente el SO y descarga la versión correcta de `jq`:
- Linux: `jq-linux64`
- macOS: `jq-osx-amd64`  
- Windows: `jq-win64.exe`

## 🐛 Solución de Problemas

### Error: "Docker no está corriendo"
```bash
# Iniciar Docker
sudo systemctl start docker  # Linux
open -a Docker              # macOS
```

### Error: "jq no encontrado"
```bash
# El script descarga jq automáticamente, pero puedes instalarlo manualmente:

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq

# macOS
brew install jq

# Windows (Chocolatey)
choco install jq
```

### Problemas con zsh
```bash
# Si tienes problemas específicos con zsh, ejecuta:
./check-compatibility.sh

# O fuerza el uso de bash:
bash ./docker-backup.sh
```

### Error: "Permisos insuficientes"
```bash
# Añadir usuario al grupo docker (Linux)
sudo usermod -aG docker $USER
# Luego reiniciar sesión

# O ejecutar con sudo (no recomendado)
sudo ./docker-backup.sh
```

### Backup muy grande
- Los volúmenes se comprimen automáticamente (`.tar.gz`)
- Los bind mounts se copian tal como están
- Para ahorrar espacio, considera excluir contenedores no esenciales

### Restauración lenta
- Los volúmenes grandes pueden tardar en restaurarse
- Los bind mounts se copian preservando permisos (puede ser lento)
- Considera restaurar contenedores uno por uno para diagnosticar problemas

## 🛡 Consideraciones de Seguridad

1. **Permisos**: Los scripts preservan permisos de archivos y directorios
2. **Bind Mounts**: Se copian de forma segura sin sobrescribir archivos existentes
3. **Credenciales**: Los backups pueden contener información sensible, almacénalos de forma segura
4. **Volúmenes**: El contenido de volúmenes se exporta completo, incluyendo posibles datos sensibles

## 🤝 Contribuir

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit tus cambios (`git commit -am 'Añadir nueva funcionalidad'`)
4. Push a la rama (`git push origin feature/nueva-funcionalidad`)
5. Crea un Pull Request

## 📝 Changelog

### v1.0.0
- ✅ Sistema completo de backup y restauración
- ✅ Soporte para contenedores, imágenes, volúmenes y bind mounts
- ✅ Generación de docker-compose.yml automática
- ✅ Compatibilidad multiplataforma
- ✅ Instalación automática de dependencias
- ✅ Informes detallados de backup y restauración
- ✅ Manejo seguro de espacios en nombres y rutas

## 📄 Licencia

Este proyecto está bajo la Licencia MIT. Ver el archivo `LICENSE` para más detalles.

## 🙏 Agradecimientos

- Comunidad Docker por la excelente documentación
- Desarrolladores de jq por la herramienta de procesamiento JSON
- Contribuidores y testers del proyecto

---

**¿Necesitas ayuda?** Abre un issue en el repositorio o consulta la documentación de Docker oficial.
