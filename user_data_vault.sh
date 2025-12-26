#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Inputs (filled by Terraform templatefile)
# ----------------------------
VAULT_VERSION="${vault_version}"                 # e.g. "1.16.3"
CLUSTER_NAME="${cluster_name}"                   # e.g. "vault-aws-lab"
DOMAIN_NAME="${domain_name}"                     # e.g. "vault.example.com" (what clients use)
NODE_ID="${node_id}"                             # e.g. "1", "2", "3"
RAFT_RETRY_JOIN_ADDRESSES="${raft_retry_join_addresses}"  # comma-separated https://<ip>:8200
ENABLE_TLS="${enable_tls}"                       # "true" or "false"

# Base64-encoded PEMs. (Optional but recommended)
TLS_CERT_B64="${tls_cert_b64}"                   # vault server cert PEM (leaf)
TLS_KEY_B64="${tls_key_b64}"                     # vault server key PEM
TLS_CA_B64="${tls_ca_b64}"                       # root/intermediate CA PEM your clients trust

# ----------------------------
# Helpers
# ----------------------------
log() { echo "[$(date -Is)] $*"; }

PRIVATE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
HOSTNAME_SHORT="$(hostname -s)"

# ----------------------------
# OS prep
# ----------------------------
log "Updating OS packages..."
apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  unzip \
  jq

# ----------------------------
# Install Vault (OSS) from HashiCorp apt repo
# ----------------------------
log "Installing Vault ${VAULT_VERSION}..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
chmod a+r /etc/apt/keyrings/hashicorp.gpg

echo \
  "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list

apt-get update -y
# Pin exact version if desired; otherwise just install latest in repo
apt-get install -y "vault=${VAULT_VERSION}*" || apt-get install -y vault

# ----------------------------
# Create vault user and directories
# ----------------------------
log "Creating vault user and directories..."
id -u vault >/dev/null 2>&1 || useradd --system --home /etc/vault.d --shell /usr/sbin/nologin vault

mkdir -p /etc/vault.d
mkdir -p /opt/vault/data
mkdir -p /opt/vault/tls
chown -R vault:vault /etc/vault.d /opt/vault
chmod 750 /etc/vault.d /opt/vault
chmod 750 /opt/vault/data

# ----------------------------
# TLS materials (optional)
# ----------------------------
if [[ "${ENABLE_TLS}" == "true" ]]; then
  log "Writing TLS files..."
  if [[ -n "${TLS_CERT_B64}" && -n "${TLS_KEY_B64}" && -n "${TLS_CA_B64}" ]]; then
    echo "${TLS_CERT_B64}" | base64 -d > /opt/vault/tls/vault.crt
    echo "${TLS_KEY_B64}"  | base64 -d > /opt/vault/tls/vault.key
    echo "${TLS_CA_B64}"   | base64 -d > /opt/vault/tls/ca.pem

    chown vault:vault /opt/vault/tls/vault.crt /opt/vault/tls/vault.key /opt/vault/tls/ca.pem
    chmod 644 /opt/vault/tls/vault.crt /opt/vault/tls/ca.pem
    chmod 600 /opt/vault/tls/vault.key
  else
    log "ENABLE_TLS=true but TLS_*_B64 not provided. Vault will fail unless you place certs manually."
  fi
fi

# ----------------------------
# Vault configuration
# ----------------------------
log "Writing Vault config..."
cat > /etc/vault.d/vault.hcl <<EOF
ui = true
disable_mlock = true
cluster_name = "${CLUSTER_NAME}"

# Vault listens on 8200 for API; 8201 is used for cluster traffic.
listener "tcp" {
  address       = "0.0.0.0:8200"

  tls_disable   = ${ENABLE_TLS}
  ${ENABLE_TLS:+tls_cert_file = "/opt/vault/tls/vault.crt"}
  ${ENABLE_TLS:+tls_key_file  = "/opt/vault/tls/vault.key"}
  ${ENABLE_TLS:+tls_client_ca_file = "/opt/vault/tls/ca.pem"}
}

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "${CLUSTER_NAME}-node-${NODE_ID}"

  # Retry join: list of peers (ideally private IPs) to join the raft cluster.
EOF

# Add retry_join blocks from comma-separated list:
IFS=',' read -ra ADDRS <<< "${RAFT_RETRY_JOIN_ADDRESSES}"
for addr in "${ADDRS[@]}"; do
  addr_trimmed="$(echo "$addr" | xargs)"
  if [[ -n "$addr_trimmed" ]]; then
    cat >> /etc/vault.d/vault.hcl <<EOF
  retry_join {
    leader_api_addr = "${addr_trimmed}"
  }
EOF
  fi
done

cat >> /etc/vault.d/vault.hcl <<EOF
}

# Use the node's private IPs for intra-cluster correctness.
api_addr     = "https://${PRIVATE_IP}:8200"
cluster_addr = "https://${PRIVATE_IP}:8201"

# Optional: log level
log_level = "info"
EOF

chown vault:vault /etc/vault.d/vault.hcl
chmod 640 /etc/vault.d/vault.hcl

# ----------------------------
# systemd unit
# ----------------------------
log "Configuring systemd service..."
cat > /etc/systemd/system/vault.service <<'EOF'
[Unit]
Description=HashiCorp Vault
Documentation=https://developer.hashicorp.com/vault/docs
Requires=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

# Hardening (basic)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vault
systemctl start vault

log "Vault started. Check: sudo journalctl -u vault -n 200 --no-pager"
log "Note: Vault will be sealed until you init/unseal."
