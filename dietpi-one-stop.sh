#!/usr/bin/env bash
set -euo pipefail

# One-stop setup script for DietPi:
# - sets eth0 to static 192.168.178.100/24
# - installs Lighttpd as a simple web server
# - installs and configures dnsmasq as a DHCP server handing out 192.168.178.x addresses
# Run as root on the DietPi system.

STATIC_IP="192.168.178.100"
CIDR="24"
INTERFACE="eth0"
DHCP_RANGE_START="192.168.178.101"
DHCP_RANGE_END="192.168.178.200"
LEASE_TIME="12h"
DNS_SERVERS="1.1.1.1,8.8.8.8"
BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WEB_SRC_DIR="${SCRIPT_DIR}/www"
WEB_DEST_DIR="/var/www/html"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Bitte als root ausführen (sudo bash dietpi-one-stop.sh)." >&2
    exit 1
  fi
}

install_packages() {
  echo "[1/5] Pakete installieren (lighttpd, dnsmasq)..."
  apt-get update -y
  apt-get install -y lighttpd dnsmasq
  systemctl enable lighttpd
}

configure_static_ip() {
  echo "[2/5] Statische IP auf ${STATIC_IP}/${CIDR} für ${INTERFACE} setzen..."
  local dhcpcd_conf="/etc/dhcpcd.conf"
  if [ -f "${dhcpcd_conf}" ]; then
    cp "${dhcpcd_conf}" "${dhcpcd_conf}.backup-${BACKUP_SUFFIX}"
  fi

  # Entferne alten Block (idempotent).
  sed -i '/^### BEGIN dietpi-one-stop/,/^### END dietpi-one-stop/d' "${dhcpcd_conf}"

  cat <<EOF >> "${dhcpcd_conf}"
### BEGIN dietpi-one-stop
interface ${INTERFACE}
static ip_address=${STATIC_IP}/${CIDR}
# Falls ein Internet-Gateway existiert, hier anpassen. Standard: dieses Gerät.
static routers=${STATIC_IP}
static domain_name_servers=${DNS_SERVERS//,/ }
### END dietpi-one-stop
EOF
}

configure_dnsmasq() {
  echo "[3/5] DHCP-Server (dnsmasq) konfigurieren..."
  local dnsmasq_conf="/etc/dnsmasq.d/dietpi-one-stop.conf"

  if [ -f "${dnsmasq_conf}" ]; then
    cp "${dnsmasq_conf}" "${dnsmasq_conf}.backup-${BACKUP_SUFFIX}"
  fi

  cat <<EOF > "${dnsmasq_conf}"
interface=${INTERFACE}
bind-interfaces
domain-needed
bogus-priv
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},255.255.255.0,${LEASE_TIME}
dhcp-option=3,${STATIC_IP}       # Gateway für Clients
dhcp-option=6,${DNS_SERVERS}     # DNS für Clients
EOF

  systemctl enable dnsmasq
}

deploy_website() {
  echo "[4/5] Webseite aus ${WEB_SRC_DIR} nach ${WEB_DEST_DIR} deployen..."
  if [ ! -d "${WEB_SRC_DIR}" ]; then
    echo "Fehler: Quellordner ${WEB_SRC_DIR} nicht gefunden." >&2
    exit 1
  fi

  if [ -d "${WEB_DEST_DIR}" ]; then
    cp -a "${WEB_DEST_DIR}" "${WEB_DEST_DIR}.backup-${BACKUP_SUFFIX}"
  fi

  rm -rf "${WEB_DEST_DIR}"
  mkdir -p "${WEB_DEST_DIR}"
  cp -a "${WEB_SRC_DIR}/." "${WEB_DEST_DIR}/"
  chown -R www-data:www-data "${WEB_DEST_DIR}"
}

generate_video_playlist() {
  echo "    - Video-Playlist erzeugen..."
  local video_dir="${WEB_DEST_DIR}/assets/videos"
  local playlist_file="${video_dir}/playlist.json"

  mkdir -p "${video_dir}"

  mapfile -t video_files < <(find "${video_dir}" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.webm" -o -iname "*.ogg" -o -iname "*.ogv" \) | sort)

  if [ "${#video_files[@]}" -eq 0 ]; then
    echo "      Keine Videodateien gefunden. Es wird eine leere playlist.json erzeugt."
  fi

  {
    echo '{'
    echo '  "videos": ['
    if [ "${#video_files[@]}" -gt 0 ]; then
      for idx in "${!video_files[@]}"; do
        fname="$(basename "${video_files[$idx]}")"
        suffix=","
        if [ "$idx" -eq "$(( ${#video_files[@]} - 1 ))" ]; then
          suffix=""
        fi
        printf '    "%s"%s\n' "${fname}" "${suffix}"
      done
    fi
    echo '  ]'
    echo '}'
  } > "${playlist_file}"

  chown -R www-data:www-data "${video_dir}"
}

configure_lighttpd() {
  echo "[5/5] Lighttpd für index6ArtikelWerbung.html konfigurieren..."
  local conf_available="/etc/lighttpd/conf-available/99-dietpi-onestop.conf"
  local conf_enabled="/etc/lighttpd/conf-enabled/99-dietpi-onestop.conf"

  cat <<'EOF' > "${conf_available}"
server.document-root = "/var/www/html"
index-file.names = ( "index6ArtikelWerbung.html", "index.html", "index.php" )

mimetype.assign += (
  ".mp4" => "video/mp4",
  ".m4v" => "video/mp4",
  ".webm" => "video/webm",
  ".ogg" => "video/ogg",
  ".ogv" => "video/ogg"
)
EOF

  ln -sf "${conf_available}" "${conf_enabled}"
  systemctl enable lighttpd
}

restart_services() {
  echo "Dienste neu starten..."
  systemctl restart dhcpcd || service dhcpcd restart
  systemctl restart dnsmasq
  systemctl restart lighttpd
}

require_root
install_packages
configure_static_ip
configure_dnsmasq
deploy_website
generate_video_playlist
configure_lighttpd
restart_services

echo "Fertig. Webserver: http://${STATIC_IP}/  | DHCP-Range: ${DHCP_RANGE_START}-${DHCP_RANGE_END} auf ${INTERFACE}."
echo "Website-Quelle: ${WEB_SRC_DIR} -> ${WEB_DEST_DIR}"
echo "Video-Playlist: ${WEB_DEST_DIR}/assets/videos/playlist.json (auf Basis vorhandener Videos erzeugt)"
echo "Backup von dhcpcd.conf (falls vorhanden): /etc/dhcpcd.conf.backup-${BACKUP_SUFFIX}"
