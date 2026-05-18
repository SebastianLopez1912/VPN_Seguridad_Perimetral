#!/bin/bash

# ============================
#   CARGAR BOT DE TELEGRAM
# ============================

source /home/proyecto/Proyecto_Vpn_Seguridad_Perimetral/Scripts/alertas_telegram.sh

type send_msg >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: La función send_msg NO está cargada desde alertas_telegram.sh"
    exit 1
fi

# ============================
#   ALIAS DE PEERS POR IP
# ============================

declare -A ALIAS

ALIAS["10.10.0.2"]="Root"
ALIAS["10.10.0.3"]="Operador"
ALIAS["10.10.0.4"]="Cliente"
ALIAS["10.10.0.5"]="Admin1"
ALIAS["10.10.0.6"]="Admin2"
ALIAS["10.10.0.7"]="Admin3"
ALIAS["10.10.0.8"]="Admin4"

# ============================
#   COMPROBAR INTERFAZ WG0
# ============================

ip link show wg0 >/dev/null 2>&1
if [ $? -ne 0 ]; then
    send_msg "⚠️ *ALERTA*: La interfaz *wg0* NO está levantada"
    exit 1
fi

# ============================
#   AUDITORÍA DE WIREGUARD
# ============================

PEERS=$(wg show wg0 peers)
NUM_PEERS=$(echo "$PEERS" | wc -l)

DETALLE=""

# ============================
#   DETALLE POR PEER (ALIAS + ESTADO)
# ============================

for PEER in $PEERS; do
    PEER_CLEAN=$(echo "$PEER" | tr -d ' ')

    IP=$(wg show wg0 allowed-ips | grep "$PEER_CLEAN" | awk '{print $2}' | cut -d'/' -f1)

    NOMBRE="${ALIAS[$IP]:-$PEER}"

    HANDSHAKE_RAW=$(wg show wg0 latest-handshakes | grep "$PEER_CLEAN" | awk '{print $2}')

    AHORA=$(date +%s)

    if [ "$HANDSHAKE_RAW" = "0" ] || [ -z "$HANDSHAKE_RAW" ]; then
        ESTADO="Desconectado ❌"
        HANDSHAKE_HUMANO="Sin actividad registrada"
    else
        DIFERENCIA=$((AHORA - HANDSHAKE_RAW))

        if [ "$DIFERENCIA" -gt 43200 ]; then
            ESTADO="Desconectado ❌"
        else
            ESTADO="Conectado (últimas 12h) ✅"
        fi

        HANDSHAKE_HUMANO="$(date -d @$HANDSHAKE_RAW '+%Y-%m-%d %H:%M:%S')"
    fi

    DETALLE+="🔹 *Peer:* *$NOMBRE*
   • *IP:* $IP
   • *Estado:* $ESTADO
   • *Último handshake:* $HANDSHAKE_HUMANO

"
done

# ============================
#   ERRORES TÉCNICOS (ÚLTIMAS 24H)
# ============================

FALLIDOS=$(journalctl -k --since "24 hours ago" | grep -Ei "wg0|wireguard|handshake|peer|fail")

if [ -z "$FALLIDOS" ]; then
    FALLIDOS="Sin errores técnicos detectados"
fi

# ============================
#   ACCESOS ÚLTIMAS 24H
# ============================

ACCESOS=$(wg show wg0 latest-handshakes | awk '$2 != 0' | wc -l)

# ============================
#   ESTADO GENERAL (SEGURO)
# ============================

ESTADO_VPN="📡 *Estado general de la VPN:*
• Interfaz wg0 activa
• Peers configurados: $NUM_PEERS
• Peers con actividad en las últimas 24h: $ACCESOS"

# ============================
#   MENSAJE FINAL BONITO
# ============================

MENSAJE="🔐 *AUDITORÍA DE WIREGUARD*

$ESTADO_VPN

👥 *Detalle por peer:*
$DETALLE

❌ *Errores técnicos del sistema en WireGuard (últimas 24h):*
\`\`\`
$FALLIDOS
\`\`\`
"

send_msg "$MENSAJE"

