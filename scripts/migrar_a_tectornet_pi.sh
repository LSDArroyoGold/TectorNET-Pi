#!/bin/bash
#
# migrar_a_tectornet_pi.sh - Instala y activa TectorNET-Pi en un dispositivo
# LSD-Tector que todavia corre BirdNET-Pi stock, disparado por el ciclo
# de auto-actualizacion normal del dispositivo (inicio_amanecer.sh /
# inicio_atardecer.sh) -- pensado para correr desatendido, en un
# dispositivo en el campo sin acceso SSH mientras corre.
#
# Uso: migrar_a_tectornet_pi.sh <DRIVE_PATH> <DRIVE_SUBCARPETA>
#   DRIVE_PATH: carpeta de Drive del dispositivo (ej. "Laboratorio 6" o
#     "LSD-Tector"), la misma que ya usan sus scripts de sincronizacion.
#   DRIVE_SUBCARPETA: subcarpeta de detecciones dentro de DRIVE_PATH que
#     el dispositivo ya viene usando (ej. "BirdNET_Detecciones" o
#     "Detecciones") -- para no partir su historial en dos lugares.
#
# Principio rector: NUNCA dejar al dispositivo sin motor de deteccion.
# BirdNET-Pi stock sigue activo en todo momento hasta que
# TectorNET-Pi.service se confirma sano (activo Y con arecord realmente
# capturando audio) -- recien ahi se hace el swap. Si cualquier paso
# falla, se aborta sin tocar nada mas: BirdNET-Pi sigue andando como si
# esto nunca hubiera corrido, y el proximo ciclo (siguiente ventana)
# reintenta desde cero (idempotente: git pull en vez de clone si ya
# existe, instalar.sh se saltea si el venv ya esta armado).
#
# Una vez que la migracion se completa OK, no se vuelve a intentar (marca
# con /home/lsd/.tectornet_pi_migrado) -- correrlo de nuevo despues de eso
# no hace nada.
#
# 7/9/2026: script (y repo) renombrado de birdnet-lsd a TectorNET-Pi.
# Este script sigue siendo SOLO para la migracion inicial desde
# BirdNET-Pi stock (nunca instalado el motor propio todavia) -- un
# dispositivo que YA tiene birdnet-lsd instalado y corriendo bajo el
# nombre viejo (marca .birdnet_lsd_migrado presente) usa en cambio
# renombrar_a_tectornet_pi.sh, que hace el rename en el lugar sin
# reinstalar nada desde cero.

set -uo pipefail  # sin -e a proposito: cada paso se chequea a mano para poder abortar limpio

DRIVE_PATH="${1:?Uso: migrar_a_tectornet_pi.sh <DRIVE_PATH> <DRIVE_SUBCARPETA>}"
DRIVE_SUBCARPETA="${2:?Uso: migrar_a_tectornet_pi.sh <DRIVE_PATH> <DRIVE_SUBCARPETA>}"

MARCA_MIGRADO="/home/lsd/.tectornet_pi_migrado"
BIRDNET_CONF="/home/lsd/BirdNET-Pi/birdnet.conf"
TECTORNET_PI_DIR="/home/lsd/TectorNET-Pi"

log() {
	python3 /home/lsd/log_sistema.py MSG "TectorNET-Pi: $1" 2>/dev/null \
		|| python3 /home/lsd/python/log_sistema.py MSG "TectorNET-Pi: $1" 2>/dev/null \
		|| echo "TectorNET-Pi: $1"
}

abortar() {
	log "migracion abortada -- $1. BirdNET-Pi stock sigue activo, sin cambios."
	exit 1
}

if [ -f "$MARCA_MIGRADO" ]; then
	exit 0
fi

[ -f "$BIRDNET_CONF" ] || abortar "no se encontro $BIRDNET_CONF (BirdNET-Pi no esta instalado)"

BIRDWEATHER_ID=$(awk -F= '/^BIRDWEATHER_ID=/{print $2}' "$BIRDNET_CONF" | tr -d ' \r')
LATITUDE=$(awk -F= '/^LATITUDE=/{print $2}' "$BIRDNET_CONF" | tr -d ' \r')
LONGITUDE=$(awk -F= '/^LONGITUDE=/{print $2}' "$BIRDNET_CONF" | tr -d ' \r')
REC_CARD=$(awk -F= '/^REC_CARD=/{print $2}' "$BIRDNET_CONF" | tr -d ' \r')
CHANNELS=$(awk -F= '/^CHANNELS=/{print $2}' "$BIRDNET_CONF" | tr -d ' \r')

[ -n "$LATITUDE" ] && [ -n "$LONGITUDE" ] || abortar "no se pudieron leer LATITUDE/LONGITUDE de $BIRDNET_CONF"
[ -n "$REC_CARD" ] || REC_CARD="default"
[ -n "$CHANNELS" ] || CHANNELS="2"

# --- clonar/actualizar TectorNET-Pi ---
if [ ! -d "$TECTORNET_PI_DIR" ]; then
	git clone https://github.com/LSDArroyoGold/TectorNET-Pi.git "$TECTORNET_PI_DIR" \
		|| abortar "fallo el clone de TectorNET-Pi"
else
	git -C "$TECTORNET_PI_DIR" pull origin main || abortar "fallo git pull de TectorNET-Pi"
fi

cd "$TECTORNET_PI_DIR" || abortar "no se pudo entrar a $TECTORNET_PI_DIR"

# --- instalar (venv + modelo + sesgo), solo si todavia no esta ---
# Chequea el ultimo archivo que instalar.sh deja (no solo la carpeta
# venv/): si una corrida anterior fallo a mitad de camino (ej. se corto
# la red bajando el modelo), venv/ ya existiria pero incompleto, y
# saltear instalar.sh de nuevo lo dejaria asi para siempre.
if [ ! -f modelo/stock_regional_meta.json ]; then
	bash instalar.sh || abortar "fallo instalar.sh"
fi

# --- configs especificas de este dispositivo, derivadas de birdnet.conf ---
cat > config/config_birdweather.txt <<EOF
BIRDWEATHER_ID = $BIRDWEATHER_ID
LATITUDE = $LATITUDE
LONGITUDE = $LONGITUDE
EOF
chmod 600 config/config_birdweather.txt

cat > config/config_sincronizacion.txt <<EOF
RCLONE_CONFIG = /home/lsd/.config/rclone/rclone.conf
DRIVE_REMOTE = gdrive
DRIVE_PATH = $DRIVE_PATH
DRIVE_SUBCARPETA = $DRIVE_SUBCARPETA
AUDIO_ROOT = /home/lsd/BirdSongs/Extracted
REC_CARD = $REC_CARD
CHANNELS = $CHANNELS
EOF
chmod 600 config/config_sincronizacion.txt

# --- servicio systemd (y logrotate, linger) ---
bash instalar_servicio.sh || abortar "fallo instalar_servicio.sh"

sudo systemctl restart TectorNET-Pi.service || abortar "no arranco TectorNET-Pi.service"

# --- verificacion de salud ANTES de tocar BirdNET-Pi ---
# Tiempo generoso: carga de TensorFlow + modelo puede tardar en hardware
# mas viejo/lento que el que se uso para desarrollar esto.
sleep 40

if ! systemctl is-active --quiet TectorNET-Pi.service; then
	abortar "TectorNET-Pi.service no quedo activo despues de arrancar"
fi

# No alcanza con que el proceso este activo -- confirmar que arecord
# realmente esta capturando audio (el bug de XDG_RUNTIME_DIR/PulseAudio
# encontrado el 23/08 en tector2 dejaba el proceso "activo" pero
# reintentando arecord en loop, sin audio real).
if ! pgrep -f "arecord -f S16_LE" > /dev/null; then
	sudo systemctl stop TectorNET-Pi.service
	abortar "TectorNET-Pi.service esta activo pero arecord no esta corriendo (problema de audio/microfono)"
fi

# --- swap: recien ahora se apaga BirdNET-Pi stock ---
sudo systemctl stop birdnet_recording.service birdnet_analysis.service 2>/dev/null
sudo systemctl disable birdnet_recording.service birdnet_analysis.service 2>/dev/null

touch "$MARCA_MIGRADO"
log "migracion a TectorNET-Pi completada OK (BirdWeather=$BIRDWEATHER_ID, card=$REC_CARD, canales=$CHANNELS)"
