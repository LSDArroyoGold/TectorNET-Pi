#!/bin/bash
#
# renombrar_a_tectornet_pi.sh - Renombra EN EL LUGAR una instalacion de
# birdnet-lsd que ya esta migrada y corriendo (marca .birdnet_lsd_migrado
# presente) al nombre nuevo, TectorNET-Pi (7/9/2026) -- sin reinstalar
# nada desde cero. Distinto de migrar_a_tectornet_pi.sh, que es solo para
# un dispositivo que TODAVIA corre BirdNET-Pi stock y nunca tuvo el motor
# propio instalado.
#
# Uso: renombrar_a_tectornet_pi.sh (sin argumentos -- todo se deriva del
# estado ya presente en el dispositivo).
#
# Disparado por el mismo ciclo de auto-actualizacion normal
# (inicio_amanecer.sh/inicio_atardecer.sh) que dispara
# migrar_a_tectornet_pi.sh, en el dispositivo que corresponda segun cual
# marca este presente.
#
# Principio rector, igual que el resto de estos scripts: NUNCA dejar al
# dispositivo sin motor de deteccion. El directorio y el servicio VIEJOS
# (birdnet-lsd / birdnet-lsd.service) siguen activos hasta confirmar que
# los NUEVOS (TectorNET-Pi / TectorNET-Pi.service) estan sanos -- recien
# ahi se desactiva y se borra lo viejo. Si cualquier paso falla, se
# aborta sin tocar nada mas: el servicio viejo sigue andando, y el
# proximo ciclo reintenta desde cero (idempotente: si el directorio
# nuevo ya existe se asume que un intento anterior ya movio los
# archivos, y el script sigue desde el paso de systemd en adelante en
# vez de repetir el mv).
#
# Una vez que el renombrado se completa OK, no se vuelve a intentar
# (marca con /home/lsd/.tectornet_pi_migrado, la MISMA marca que usa
# migrar_a_tectornet_pi.sh para el caso de instalacion fresca -- una vez
# renombrado, este dispositivo queda en un estado indistinguible de uno
# que se instalo directo con el nombre nuevo, asi que reutiliza la misma
# marca en vez de una tercera distinta).

set -uo pipefail  # sin -e a proposito: cada paso se chequea a mano para poder abortar limpio

MARCA_VIEJA="/home/lsd/.birdnet_lsd_migrado"
MARCA_NUEVA="/home/lsd/.tectornet_pi_migrado"
DIR_VIEJO="/home/lsd/birdnet-lsd"
DIR_NUEVO="/home/lsd/TectorNET-Pi"
UNIDAD_VIEJA="birdnet-lsd.service"
UNIDAD_NUEVA="TectorNET-Pi.service"

log() {
	python3 /home/lsd/log_sistema.py MSG "TectorNET-Pi: $1" 2>/dev/null \
		|| python3 /home/lsd/python/log_sistema.py MSG "TectorNET-Pi: $1" 2>/dev/null \
		|| echo "TectorNET-Pi: $1"
}

abortar() {
	log "renombrado abortado -- $1. birdnet-lsd (nombre viejo) sigue activo, sin cambios."
	exit 1
}

# Ya renombrado (por esta corrida o por una instalacion fresca directa
# con el nombre nuevo) -- nada que hacer.
[ -f "$MARCA_NUEVA" ] && exit 0

# Nunca migrado a birdnet-lsd en primer lugar (todavia en BirdNET-Pi
# stock) -- este script no aplica, es tarea de migrar_a_tectornet_pi.sh.
[ -f "$MARCA_VIEJA" ] || exit 0

# --- paso 1: mover el directorio, si todavia no se movio ---
if [ ! -d "$DIR_NUEVO" ]; then
	[ -d "$DIR_VIEJO" ] || abortar "no existe $DIR_VIEJO ni $DIR_NUEVO (estado inconsistente)"
	mv "$DIR_VIEJO" "$DIR_NUEVO" || abortar "fallo el mv de $DIR_VIEJO a $DIR_NUEVO"
fi

cd "$DIR_NUEVO" || abortar "no se pudo entrar a $DIR_NUEVO"

# --- paso 2: actualizar el remote y traer el codigo ya renombrado
# adentro (nombres de servicio/systemd unit viven en el repo mismo, asi
# que sin este pull instalar_servicio.sh de abajo seguiria generando la
# unidad vieja) ---
git remote set-url origin https://github.com/LSDArroyoGold/TectorNET-Pi.git \
	|| abortar "fallo actualizar el remote de git"
git pull origin main || abortar "fallo git pull tras el renombrado"

# --- paso 3: registrar el servicio NUEVO (instalar_servicio.sh es
# idempotente -- generar la unidad nueva no toca la vieja, que sigue
# activa en paralelo hasta el swap mas abajo) ---
bash instalar_servicio.sh || abortar "fallo instalar_servicio.sh"

sudo systemctl restart "$UNIDAD_NUEVA" || abortar "no arranco $UNIDAD_NUEVA"

# --- verificacion de salud ANTES de tocar el servicio viejo ---
sleep 40

if ! systemctl is-active --quiet "$UNIDAD_NUEVA"; then
	abortar "$UNIDAD_NUEVA no quedo activo despues de arrancar"
fi

if ! pgrep -f "arecord -f S16_LE" > /dev/null; then
	sudo systemctl stop "$UNIDAD_NUEVA"
	abortar "$UNIDAD_NUEVA esta activo pero arecord no esta corriendo (problema de audio/microfono)"
fi

# --- swap: recien ahora se apaga y se borra la unidad vieja ---
sudo systemctl stop "$UNIDAD_VIEJA" 2>/dev/null
sudo systemctl disable "$UNIDAD_VIEJA" 2>/dev/null
sudo rm -f "/etc/systemd/system/$UNIDAD_VIEJA"
sudo rm -f "/etc/logrotate.d/birdnet-lsd"
sudo systemctl daemon-reload

touch "$MARCA_NUEVA"
log "renombrado de birdnet-lsd a TectorNET-Pi completado OK ($DIR_VIEJO -> $DIR_NUEVO, $UNIDAD_VIEJA -> $UNIDAD_NUEVA)"
