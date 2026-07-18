#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/config/node.env}"
readonly ENV_FILE

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR:-}" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || fail "Ejecuta este instalador como root."
[[ -f "$ENV_FILE" ]] || fail "No existe $ENV_FILE. Copia config/node.env.example a config/node.env."

# shellcheck disable=SC1090
source "$ENV_FILE"

required_vars=(
  CHAIN_ID
  MONIKER
  MUCOIND_VERSION
  MUCOIND_ARCHIVE
  MUCOIND_ARCHIVE_URL
  MUCOIND_ARCHIVE_CHECKSUM_URL
  MUCOIND_BINARY_NAME
  MUCOIND_BINARY_SHA256
  GENESIS_URL
  GENESIS_SHA256
  SERVICE_USER
  SERVICE_GROUP
  SERVICE_NAME
  BINARY_INSTALL_PATH
  NODE_HOME
)

for var in "${required_vars[@]}"; do
  [[ -n "${!var:-}" ]] || fail "Variable obligatoria vacía: $var"
done

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) fail "Arquitectura no compatible: $(uname -m). Solo Linux AMD64." ;;
esac

if [[ ! -f /etc/os-release ]]; then
  fail "No se pudo identificar el sistema operativo."
fi

# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] || fail "Este instalador requiere Ubuntu."
[[ "${VERSION_ID:-}" == "24.04" ]] || fail "Este instalador fue validado para Ubuntu 24.04."

log "Instalando dependencias"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  jq \
  tar \
  coreutils \
  sudo

if ! getent group "$SERVICE_GROUP" >/dev/null; then
  groupadd --system "$SERVICE_GROUP"
fi

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  log "Creando usuario del servicio: $SERVICE_USER"
  useradd \
    --system \
    --gid "$SERVICE_GROUP" \
    --home-dir "/home/$SERVICE_USER" \
    --create-home \
    --shell /usr/sbin/nologin \
    "$SERVICE_USER"
fi

WORK_DIR="$(mktemp -d)"
ARCHIVE_PATH="${WORK_DIR}/${MUCOIND_ARCHIVE}"
CHECKSUM_PATH="${WORK_DIR}/${MUCOIND_ARCHIVE}.sha256"

log "Descargando MuCoin ${MUCOIND_VERSION}"
curl --fail --location --retry 3 \
  "$MUCOIND_ARCHIVE_URL" \
  --output "$ARCHIVE_PATH"

curl --fail --location --retry 3 \
  "$MUCOIND_ARCHIVE_CHECKSUM_URL" \
  --output "$CHECKSUM_PATH"

log "Verificando checksum del paquete"
(
  cd "$WORK_DIR"
  sha256sum -c "$(basename "$CHECKSUM_PATH")"
)

tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR"

EXTRACTED_BINARY="${WORK_DIR}/${MUCOIND_BINARY_NAME}"
[[ -f "$EXTRACTED_BINARY" ]] || fail "El paquete no contiene ${MUCOIND_BINARY_NAME}."

ACTUAL_BINARY_SHA256="$(sha256sum "$EXTRACTED_BINARY" | awk '{print $1}')"

if [[ "$ACTUAL_BINARY_SHA256" != "$MUCOIND_BINARY_SHA256" ]]; then
  fail "Checksum del binario incorrecto: $ACTUAL_BINARY_SHA256"
fi

log "Instalando binario en $BINARY_INSTALL_PATH"
install -o root -g root -m 0755 \
  "$EXTRACTED_BINARY" \
  "$BINARY_INSTALL_PATH"

"$BINARY_INSTALL_PATH" version --long --output json |
  jq '{
    name,
    server_name,
    version,
    commit,
    go,
    cosmos_sdk_version
  }'

if [[ -e "$NODE_HOME/config/genesis.json" ]]; then
  fail "Ya existe un nodo en $NODE_HOME. El instalador no sobrescribirá una instalación existente."
fi

log "Inicializando nodo $MONIKER"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$NODE_HOME"

sudo -u "$SERVICE_USER" \
  "$BINARY_INSTALL_PATH" init "$MONIKER" \
  --chain-id "$CHAIN_ID" \
  --home "$NODE_HOME" \
  >/dev/null

log "Descargando genesis oficial"
curl --fail --location --retry 3 \
  "$GENESIS_URL" \
  --output "${WORK_DIR}/genesis.json"

ACTUAL_GENESIS_SHA256="$(
  sha256sum "${WORK_DIR}/genesis.json" |
  awk '{print $1}'
)"

if [[ "$ACTUAL_GENESIS_SHA256" != "$GENESIS_SHA256" ]]; then
  fail "Checksum del genesis incorrecto: $ACTUAL_GENESIS_SHA256"
fi

install \
  -o "$SERVICE_USER" \
  -g "$SERVICE_GROUP" \
  -m 0600 \
  "${WORK_DIR}/genesis.json" \
  "$NODE_HOME/config/genesis.json"

log "Aplicando configuración del nodo"
"$SCRIPT_DIR/scripts/configure-node.sh" "$ENV_FILE"

chown -R "$SERVICE_USER:$SERVICE_GROUP" "$NODE_HOME"
chmod 0750 "$NODE_HOME"
chmod 0750 "$NODE_HOME/config"
chmod 0600 "$NODE_HOME/config/genesis.json"
chmod 0600 "$NODE_HOME/config/node_key.json"
chmod 0600 "$NODE_HOME/config/priv_validator_key.json"
chmod 0600 "$NODE_HOME/data/priv_validator_state.json"

log "Instalando servicio systemd"
install -o root -g root -m 0644 \
  "$SCRIPT_DIR/systemd/mucoind.service" \
  "/etc/systemd/system/${SERVICE_NAME}.service"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
systemctl start "${SERVICE_NAME}.service"

sleep 5

log "Estado del servicio"
systemctl status "${SERVICE_NAME}.service" --no-pager -l || true

log "Instalación terminada"
echo "Servicio: ${SERVICE_NAME}.service"
echo "Node home: $NODE_HOME"
echo "Binario: $BINARY_INSTALL_PATH"
echo "Logs: journalctl -u ${SERVICE_NAME}.service -f"
