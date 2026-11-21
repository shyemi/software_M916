#!/usr/bin/env bash
# Instalador de Redragon M916 Pro 4K para Linux (Wine)
set -euo pipefail

APP_DIR="$HOME/.local/share/redragon-m916"
PREFIX="$HOME/.local/share/wineprefixes/redragon-m916"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
UDEV_RULE="/etc/udev/rules.d/99-redragon-m916.rules"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_SRC="$SCRIPT_DIR/app"

log()  { printf '\033[1;31m[Redragon]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[Redragon]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[Redragon] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] && die "No ejecutes este script como root. Usa tu usuario normal; el script pedira sudo cuando haga falta."
[ -d "$APP_SRC" ] || die "No encuentro la carpeta 'app' junto al script. Descomprime el paquete completo."

DISTRO=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO="${ID:-}"
fi

install_pkgs() {
  local pkgs=("$@")
  [ ${#pkgs[@]} -eq 0 ] && return 0
  log "Instalando dependencias: ${pkgs[*]}"
  case "$DISTRO" in
    arch|archarm|endeavouros|manjaro|garuda|cachyos|artix|arcolinux)
      sudo pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    debian|ubuntu|linuxmint|pop|neon|zorin)
      sudo apt-get update
      sudo apt-get install -y "${pkgs[@]}" ;;
    fedora)
      sudo dnf install -y "${pkgs[@]}" ;;
    *)
      die "Distro '$DISTRO' no reconocida. Instala manualmente: ${pkgs[*]}" ;;
  esac
}

# Dependencias base
NEED=()
for c in wine winetricks cabextract wget fc-list; do
  if ! command -v "$c" >/dev/null 2>&1; then
    case "$c" in
      fc-list) NEED+=(fontconfig) ;;
      *) NEED+=("$c") ;;
    esac
  fi
done
[ ${#NEED[@]} -gt 0 ] && install_pkgs "${NEED[@]}"

# Fuente CJK (la interfaz del software viene en chino)
if command -v fc-list >/dev/null 2>&1 && ! fc-list :lang=zh 2>/dev/null | grep -q .; then
  case "$DISTRO" in
    arch|archarm|endeavouros|manjaro|garuda|cachyos|artix|arcolinux) install_pkgs noto-fonts-cjk ;;
    debian|ubuntu|linuxmint|pop|neon|zorin) install_pkgs fonts-noto-cjk ;;
    fedora) install_pkgs google-noto-sans-cjk-fonts ;;
    *) warn "No pude instalar una fuente CJK automaticamente. Instala Noto Sans CJK si ves cuadros en la app." ;;
  esac
  fc-cache -f >/dev/null 2>&1 || true
fi

# Copiar la aplicacion
log "Copiando la aplicacion a $APP_DIR"
mkdir -p "$APP_DIR"
cp -a "$APP_SRC/." "$APP_DIR/"
[ -f "$APP_DIR/Mouse Drive Beta.exe" ] || die "No se copio 'Mouse Drive Beta.exe'. Revisa el paquete."

# Prefix Wine + .NET Framework 4.8 nativo
unset WINEARCH
export WINEPREFIX="$PREFIX"
export WINEDEBUG=-all
mkdir -p "$PREFIX"

if [ ! -f "$PREFIX/system.reg" ]; then
  log "Creando prefix Wine en $PREFIX"
  # Evita el dialogo de Wine Mono/Gecko; luego se instala .NET 4.8 nativo.
  WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
fi

DOTNET_OK=0
[ -f "$PREFIX/drive_c/windows/dotnet48.installed.workaround" ] && DOTNET_OK=1

if [ "$DOTNET_OK" -eq 0 ]; then
  log "Instalando .NET Framework 4.8 nativo (descarga ~100 MB, tarda varios minutos)..."
  winetricks -q dotnet48 || die "Fallo la instalacion de .NET 4.8. Revisa la conexion y vuelve a ejecutar el script."
else
  log ".NET Framework 4.8 ya esta instalado en el prefix."
fi

# Lanzador
log "Creando lanzador en $BIN_DIR/redragon-mouse"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/redragon-mouse" <<EOF
#!/bin/sh
export WINEPREFIX="$PREFIX"
cd "$APP_DIR" || exit 1
exec wine "Mouse Drive Beta.exe" "\$@"
EOF
chmod +x "$BIN_DIR/redragon-mouse"

# Entrada de menu
log "Creando entrada de menu"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/redragon-mouse.desktop" <<EOF
[Desktop Entry]
Name=Redragon M916 Pro 4K
Comment=Software de configuracion del mouse Redragon M916 Pro 4K (Wine)
Exec=$BIN_DIR/redragon-mouse
Icon=$APP_DIR/res/logo.ico
Terminal=false
Type=Application
Categories=Utility;Settings;
EOF
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

# Regla udev para acceso HID (mouse Bluetooth, cable y receptor 4K)
log "Instalando regla udev (te va a pedir sudo)..."
sudo tee "$UDEV_RULE" >/dev/null <<'EOF'
# Redragon M916 Pro 4K - mouse HID (Bluetooth F533 / cable F54D / receptor 4K F54F)
SUBSYSTEM=="hidraw", ATTRS{id/vendor}=="3554", ATTRS{id/product}=="f533", MODE="0666"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", ATTRS{idProduct}=="f54d", MODE="0666"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", ATTRS{idProduct}=="f54f", MODE="0666"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "Añade $BIN_DIR al PATH si quieres usar 'redragon-mouse' desde cualquier terminal." ;;
esac

log "Listo."
log "Conecta el receptor 4K o el cable USB-C del mouse."
log "Abre la app desde el menu ('Redragon M916 Pro 4K') o ejecuta: redragon-mouse"
warn "Por Bluetooth el software NO detecta el mouse. Usa el receptor 4K o el cable."
