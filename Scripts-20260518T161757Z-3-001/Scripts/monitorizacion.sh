#!/bin/bash
set -euo pipefail

# ============================
#   CARGAR BOT DE TELEGRAM
# ============================

source /home/proyecto/Proyecto_Vpn_Seguridad_Perimetral/Scripts/alertas_telegram.sh

# ============================
#   VARIABLES
# ============================

LOG=/opt/monitorizacion/logs/monitorizacion.log
HOST=$(hostname)

CRITICAL_SERVICES=("sshd" "fail2ban" "docker" "cron")

write_log() {
    local DATE=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$DATE - $1" >> "$LOG"
}

# ============================
#   ESTADO DEL SISTEMA
# ============================

CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')
RAM_USAGE=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')

SYSTEM_STATUS="💻 --- ESTADO DEL SISTEMA ---
CPU (1,5,15 min): $CPU_LOAD
RAM usada: $RAM_USAGE
Disco / usado: $DISK_USAGE"

write_log "Estado del sistema recopilado"

# ============================
#   SERVICIOS CRÍTICOS
# ============================

SERVICES_STATUS="🛠️ --- SERVICIOS CRÍTICOS ---"

for svc in "${CRITICAL_SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        SERVICES_STATUS+="
- $svc: Activo"
    else
        SERVICES_STATUS+="
- $svc: Inactivo ❌"
    fi
done

# WireGuard
if wg show wg0 >/dev/null 2>&1; then
    SERVICES_STATUS+="
- WireGuard (wg0): Activo"
else
    SERVICES_STATUS+="
- WireGuard (wg0): Inactivo ❌"
fi

# ============================
#   SEGURIDAD
# ============================

SSH_FAILS=$(journalctl -u sshd --since "12 hours ago" | grep -c "Failed password" || true)
BANS=$(fail2ban-client status sshd | grep "Currently banned" | awk '{print $4}')
BANS=${BANS:-0}

SECURITY_STATUS="🔒 --- SEGURIDAD ---
Intentos SSH fallidos (últimas 12h): $SSH_FAILS
Fail2ban IPs bloqueadas: $BANS"

# ============================
#   ACTUALIZACIONES
# ============================

apt update -y >/dev/null 2>&1
UPGRADES=$(apt list --upgradable 2>/dev/null | grep -vc Listing)

UPDATE_STATUS="🆕 --- ACTUALIZACIONES ---
Paquetes pendientes: $UPGRADES"

write_log "Actualizaciones revisadas"

# ============================
#   DOCKER
# ============================

if systemctl is-active --quiet docker; then
    DOCKER_STATUS=$(docker ps --format "• {{.Names}} ({{.Status}})")
    DOCKER_STATUS=${DOCKER_STATUS:-"No hay contenedores en ejecución"}
else
    DOCKER_STATUS="Docker no está activo ❌"
fi

DOCKER_SECTION="🐳 --- DOCKER ---
$DOCKER_STATUS"

# ============================
#   MENSAJE FINAL
# ============================

SUMMARY="$SYSTEM_STATUS

$SERVICES_STATUS

$SECURITY_STATUS

$UPDATE_STATUS

$DOCKER_SECTION"

# ============================
#   ENVÍO A TELEGRAM
# ============================

send_msg "$SUMMARY"

write_log "Monitorización completada"

