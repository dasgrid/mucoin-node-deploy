#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Uso: $0 /ruta/node.env" >&2
  exit 1
fi

ENV_FILE="$1"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "No existe el archivo de configuración: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

required_vars=(
  CHAIN_ID
  MONIKER
  BINARY_INSTALL_PATH
  NODE_HOME
  MINIMUM_GAS_PRICES
  RPC_LADDR
  P2P_LADDR
  API_ENABLE
  API_ADDRESS
  GRPC_ENABLE
  GRPC_ADDRESS
  PRUNING
  INDEXER
  SNAPSHOT_INTERVAL
  SNAPSHOT_KEEP_RECENT
  PROMETHEUS
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Variable obligatoria vacía: $var" >&2
    exit 1
  fi
done

if [[ ! -x "$BINARY_INSTALL_PATH" ]]; then
  echo "No existe el binario ejecutable: $BINARY_INSTALL_PATH" >&2
  exit 1
fi

if [[ ! -d "$NODE_HOME/config" ]]; then
  echo "El nodo no fue inicializado: $NODE_HOME/config" >&2
  exit 1
fi

set_app_config() {
  local key="$1"
  local value="$2"

  "$BINARY_INSTALL_PATH" config set \
    app \
    "$key" \
    "$value" \
    --home "$NODE_HOME"
}

set_client_config() {
  local key="$1"
  local value="$2"

  "$BINARY_INSTALL_PATH" config set \
    client \
    "$key" \
    "$value" \
    --home "$NODE_HOME"
}

echo "Configurando client.toml..."
set_client_config chain-id "$CHAIN_ID"
set_client_config keyring-backend file
set_client_config output json
set_client_config node "tcp://127.0.0.1:26657"
set_client_config broadcast-mode sync

echo "Configurando app.toml..."
set_app_config minimum-gas-prices "$MINIMUM_GAS_PRICES"
set_app_config pruning "$PRUNING"
set_app_config api.enable "$API_ENABLE"
set_app_config api.address "$API_ADDRESS"
set_app_config grpc.enable "$GRPC_ENABLE"
set_app_config grpc.address "$GRPC_ADDRESS"
set_app_config state-sync.snapshot-interval "$SNAPSHOT_INTERVAL"
set_app_config state-sync.snapshot-keep-recent "$SNAPSHOT_KEEP_RECENT"

echo "Configurando config.toml de CometBFT..."

export CONFIG_TOML="$NODE_HOME/config/config.toml"
export CFG_MONIKER="$MONIKER"
export CFG_RPC_LADDR="$RPC_LADDR"
export CFG_P2P_LADDR="$P2P_LADDR"
export CFG_SEEDS="${SEEDS:-}"
export CFG_PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
export CFG_EXTERNAL_ADDRESS="${EXTERNAL_ADDRESS:-}"
export CFG_INDEXER="$INDEXER"
export CFG_PROMETHEUS="$PROMETHEUS"

python3 <<'PY'
import os
import re
import sys
from pathlib import Path

path = Path(os.environ["CONFIG_TOML"])

if not path.is_file():
    raise SystemExit(f"No existe config.toml: {path}")

text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

values = {
    ("", "moniker"): os.environ["CFG_MONIKER"],
    ("rpc", "laddr"): os.environ["CFG_RPC_LADDR"],
    ("p2p", "laddr"): os.environ["CFG_P2P_LADDR"],
    ("p2p", "seeds"): os.environ["CFG_SEEDS"],
    ("p2p", "persistent_peers"): os.environ["CFG_PERSISTENT_PEERS"],
    ("p2p", "external_address"): os.environ["CFG_EXTERNAL_ADDRESS"],
    ("p2p", "pex"): True,
    ("tx_index", "indexer"): os.environ["CFG_INDEXER"],
    ("instrumentation", "prometheus"): (
        os.environ["CFG_PROMETHEUS"].strip().lower() == "true"
    ),
}

def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"

    escaped = (
        str(value)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
    )
    return f'"{escaped}"'

current_section = ""
updated = set()
output = []

section_pattern = re.compile(r"^\s*\[([^\]]+)\]\s*(?:#.*)?$")
key_pattern = re.compile(r'^(\s*)([A-Za-z0-9_-]+)(\s*=\s*)(.*?)(\r?\n)?$')

for line in lines:
    section_match = section_pattern.match(line)

    if section_match:
        current_section = section_match.group(1).strip()
        output.append(line)
        continue

    key_match = key_pattern.match(line)

    if not key_match:
        output.append(line)
        continue

    indent, key, separator, old_value, newline = key_match.groups()
    target = (current_section, key)

    if target not in values:
        output.append(line)
        continue

    output.append(
        f"{indent}{key}{separator}{toml_value(values[target])}"
        f"{newline or ''}"
    )
    updated.add(target)

missing = set(values) - updated

if missing:
    formatted = ", ".join(
        f"[{section or 'root'}].{key}"
        for section, key in sorted(missing)
    )
    raise SystemExit(
        f"No se encontraron todas las claves esperadas en config.toml: {formatted}"
    )

temporary = path.with_suffix(".toml.tmp")
temporary.write_text("".join(output), encoding="utf-8")
temporary.replace(path)

print("config.toml actualizado correctamente.")
PY

unset \
  CONFIG_TOML \
  CFG_MONIKER \
  CFG_RPC_LADDR \
  CFG_P2P_LADDR \
  CFG_SEEDS \
  CFG_PERSISTENT_PEERS \
  CFG_EXTERNAL_ADDRESS \
  CFG_INDEXER \
  CFG_PROMETHEUS

echo "Configuración de MuCoin aplicada correctamente."
