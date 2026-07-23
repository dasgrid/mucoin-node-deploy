# MuCoin Node Deployment

Automated deployment tooling for running a MuCoin mainnet full node on Ubuntu Server 24.04 AMD64.

The installer downloads the official MuCoin binary, verifies its SHA-256 checksum, downloads and verifies the canonical genesis file, initializes the node, applies the network configuration, and installs a hardened `systemd` service.

## Network information

| Property          | Value            |
| ----------------- | ---------------- |
| Network           | MuCoin Mainnet   |
| Chain ID          | `mucoin-1`       |
| Native token      | `MUC`            |
| Base denomination | `umuc`           |
| Decimals          | `6`              |
| Bech32 prefix     | `muc`            |
| Daemon            | `mucoind`        |
| Current release   | `rewards-v0.7.0` |
| Minimum gas price | `0.0025umuc`     |

## Public services

| Service     | Endpoint                                                                             |
| ----------- | ------------------------------------------------------------------------------------ |
| Website     | https://mucoin.org                                                                   |
| Explorer    | https://mucoin.org/explorer                                                          |
| RPC         | https://rpc.mucoin.org                                                               |
| REST API    | https://rest.mucoin.org                                                              |
| Source code | https://github.com/dasgrid/mucoin                                                    |
| Genesis     | https://raw.githubusercontent.com/dasgrid/mucoin/main/networks/mucoin-1/genesis.json |

## Supported environment

The automated installer has been validated for:

* Ubuntu Server 24.04
* Linux AMD64 / x86_64
* Root or sudo access
* Internet access for downloading packages, the MuCoin binary and genesis
* TCP port `26656` available for inbound P2P connections when operating a public node

The installer intentionally stops on unsupported operating systems or architectures.

## Recommended resources

Suggested minimum resources for a standard full node:

* 2 CPU cores
* 4 GB RAM
* 100 GB SSD or NVMe storage
* Stable internet connection

Storage requirements increase over time as the blockchain grows.

## Installation

Clone the deployment repository:

```bash
git clone https://github.com/dasgrid/mucoin-node-deploy.git
cd mucoin-node-deploy
```

Create the active node configuration:

```bash
cp config/node.env.example config/node.env
```

Edit the configuration:

```bash
nano config/node.env
```

At minimum, review and customize:

```bash
MONIKER="mucoin-node"
EXTERNAL_ADDRESS=""
```

For a public P2P node, `EXTERNAL_ADDRESS` can be set to the server's public address:

```bash
EXTERNAL_ADDRESS="PUBLIC_IP:26656"
```

Run the installer as root:

```bash
sudo ./install.sh
```

The installer will:

1. Validate Ubuntu 24.04 and AMD64.
2. Install the required system packages.
3. Create the dedicated `mucoin` system user and group.
4. Download the official `mucoind` release.
5. Verify the release archive checksum.
6. Verify the extracted binary checksum.
7. Initialize the node with chain ID `mucoin-1`.
8. Download and verify the canonical genesis.
9. Configure RPC, P2P, REST API, gRPC, pruning, snapshots and indexing.
10. Install and start the `mucoind.service` systemd unit.

The installer does not overwrite an existing node installation.

## Default network configuration

The default configuration uses the following persistent peer:

```text
32361fe4a8e26a1096261c031a951ed31bb07598@169.58.22.139:26656
```

Default interfaces:

| Service  | Address                 |
| -------- | ----------------------- |
| P2P      | `tcp://0.0.0.0:26656`   |
| RPC      | `tcp://127.0.0.1:26657` |
| REST API | `tcp://127.0.0.1:1317`  |
| gRPC     | `127.0.0.1:9090`        |

RPC, REST and gRPC are bound to localhost by default for security. P2P is exposed publicly so the node can connect to the network.

## Verify the service

Check the systemd service:

```bash
sudo systemctl status mucoind --no-pager -l
```

Follow the node logs:

```bash
sudo journalctl -u mucoind -f
```

Check the local RPC status:

```bash
curl -s http://127.0.0.1:26657/status | jq
```

Check the synchronization state:

```bash
curl -s http://127.0.0.1:26657/status |
jq '{
  network: .result.node_info.network,
  moniker: .result.node_info.moniker,
  latest_block_height: .result.sync_info.latest_block_height,
  latest_block_time: .result.sync_info.latest_block_time,
  catching_up: .result.sync_info.catching_up
}'
```

A fully synchronized node should eventually report:

```json
{
  "catching_up": false
}
```

## Node locations

| Item            | Path                                  |
| --------------- | ------------------------------------- |
| Binary          | `/usr/local/bin/mucoind`              |
| Node home       | `/home/mucoin/.mucoin`                |
| Configuration   | `/home/mucoin/.mucoin/config`         |
| Blockchain data | `/home/mucoin/.mucoin/data`           |
| Systemd service | `/etc/systemd/system/mucoind.service` |

## Pruned node profile

A low-disk example configuration is available at:

```text
config/node-pruned.env.example
```

Review its pruning and indexing settings before using it. A pruned node reduces disk usage but does not retain the complete historical blockchain state.

## Firewall

A public node normally needs inbound TCP access to:

```text
26656
```

RPC, REST API and gRPC should remain restricted unless they are intentionally placed behind a secured reverse proxy or firewall.

Example using UFW:

```bash
sudo ufw allow 26656/tcp
```

Do not expose local RPC, REST or gRPC interfaces publicly without appropriate access controls.

## IBC

MuCoin supports ICS-20 transfers and has an active IBC connection with Osmosis.

| MuCoin               | Osmosis                   |
| -------------------- | ------------------------- |
| `transfer/channel-0` | `transfer/channel-110556` |
| `connection-0`       | `connection-11080`        |
| `07-tendermint-0`    | `07-tendermint-3729`      |

MUC on Osmosis uses:

```text
ibc/8B84D6340B0340917D3E2E3A17B4BE962F5593637AD7E42F6AE61D6A00ACE713
```

## Security

Never copy, publish or commit:

* Mnemonic phrases
* Validator private keys
* `priv_validator_key.json`
* `node_key.json`
* Keyring files
* Passwords
* Production `.env` files
* Backup archives containing private node material

The active `config/node.env` file is intentionally excluded through `.gitignore`.

The systemd service runs under a dedicated non-login user and includes the following hardening settings:

```text
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
UMask=0027
```

## Uninstall

Review the uninstall script before running it:

```bash
sudo ./uninstall.sh
```

Uninstalling a node may remove local blockchain data and configuration. Back up any required node or validator material before proceeding.

## License

MuCoin source code is licensed under the Apache License 2.0.
