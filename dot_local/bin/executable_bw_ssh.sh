#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# DEFAULTS & VARIABLES
# ==============================================================================
TARGET_DIR="$HOME/.ssh"
FORCE=false
UPDATE_CONFIG=false
SILENT=false
SEARCH_TERM=""
SHOW_HELP=false

# ==============================================================================
# LOGGING FUNCTION
# ==============================================================================
log() {
  if [ "$SILENT" = false ]; then
    echo "$@"
  fi
}

# ==============================================================================
# PATH DISPLAY HELPER
# ==============================================================================
# Replaces $HOME with ~ for cleaner output
display_path() {
  local path="$1"
  echo "${path/#$HOME/'~'}"
}

# ==============================================================================
# AI-FRIENDLY HELP FUNCTION
# ==============================================================================
show_help() {
  cat <<'EOF'
---
name: bw_ssh
version: 1.2.0
description: |
  Extracts native Bitwarden SSH keys (type 5) and securely loads them into the 
  local ssh-agent. Optionally extracts and saves the public key to disk, and 
  can automatically configure the ~/.ssh/config file for seamless SSH routing.
synopsis: bw_ssh [OPTIONS] <SEARCH_TERM>
arguments:
  - name: SEARCH_TERM
    type: string
    required: true
    description: The name of the SSH key item in Bitwarden (case-insensitive).
options:
  - flag: -d, --dir
    type: string
    default: ~/.ssh
    description: Directory to save the public key. Auto-created with 700 permissions if missing.
  - flag: -f, --force
    type: boolean
    default: false
    description: Overwrite existing public key files. Creates a .bak backup of the old file.
  - flag: -c, --config
    type: boolean
    default: false
    description: Automatically append/update the ~/.ssh/config file with IdentitiesOnly yes.
  - flag: -s, --silent
    type: boolean
    default: false
    description: Suppress all standard output. Errors are still printed to stderr.
  - flag: -h, --help
    type: boolean
    default: false
    description: Display this help message.
behavior:
  private_key_handling: |
    The private key is NEVER written to disk. It is piped directly into ssh-agent.
    If the public key exists and differs from the vault (and --force is not used), 
    the script aborts entirely, and the private key is NOT loaded.
  public_key_handling: |
    If the public key file already exists, its SHA256 hash is compared to the vault.
    If hashes match, the public key save is skipped, but the private key is still loaded.
    If they differ, the script ABORTS entirely unless --force is used.
  ssh_agent: |
    Automatically starts ssh-agent if it is not already running.
examples:
  - command: bw_ssh github
    description: Load the 'github' key into ssh-agent and save 'github.pub' to ~/.ssh.
  - command: bw_ssh -d /custom/keys -c myserver
    description: Save public key to /custom/keys, update ~/.ssh/config, and load into agent.
  - command: bw_ssh -f github
    description: Force overwrite the existing github.pub file (backing up the old one).
  - command: bw_ssh -s github
    description: Load key silently with no terminal output.
---
EOF
  exit 0
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
  -d | --dir)
    TARGET_DIR="$2"
    shift 2
    ;;
  -f | --force)
    FORCE=true
    shift
    ;;
  -c | --config)
    UPDATE_CONFIG=true
    shift
    ;;
  -s | --silent)
    SILENT=true
    shift
    ;;
  -h | --help)
    SHOW_HELP=true
    shift
    ;;
  -*)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
  *)
    SEARCH_TERM="$1"
    shift
    ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then show_help; fi

if [ -z "$SEARCH_TERM" ]; then
  echo "Error: SEARCH_TERM is required." >&2
  echo "Run 'bw_ssh --help' for usage instructions." >&2
  exit 1
fi

# ==============================================================================
# PREREQUISITES & VAULT CHECK
# ==============================================================================
for cmd in bw jq ssh-add; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' is not installed." >&2
    exit 1
  fi
done

if ! bw status | grep -q '"unlocked"'; then
  echo "Error: Bitwarden vault is locked." >&2
  echo "Please unlock it first: eval \$(bw unlock --raw)" >&2
  exit 1
fi

# ==============================================================================
# DATA EXTRACTION (Using temp files to safely handle newlines in keys)
# ==============================================================================
# ==============================================================================
# DATA EXTRACTION (Optimized: Single 'bw' call)
# ==============================================================================
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 1. Fetch the search results ONCE from Bitwarden and save to a local JSON file
bw list items --search "$SEARCH_TERM" >"$TMP_DIR/search_results.json"

# 2. Extract the specific fields locally using jq (much faster than calling bw again)
jq -r --arg term "$SEARCH_TERM" '
    map(select(.type == 5 and (.name | ascii_downcase) == ($term | ascii_downcase))) | .[0] |
    .name' "$TMP_DIR/search_results.json" >"$TMP_DIR/name"

jq -r --arg term "$SEARCH_TERM" '
    map(select(.type == 5 and (.name | ascii_downcase) == ($term | ascii_downcase))) | .[0] |
    .sshKey.publicKey' "$TMP_DIR/search_results.json" >"$TMP_DIR/pub"

jq -r --arg term "$SEARCH_TERM" '
    map(select(.type == 5 and (.name | ascii_downcase) == ($term | ascii_downcase))) | .[0] |
    .sshKey.privateKey' "$TMP_DIR/search_results.json" >"$TMP_DIR/priv"

ITEM_NAME=$(cat "$TMP_DIR/name")
PUB_KEY=$(cat "$TMP_DIR/pub")
PRIV_KEY=$(cat "$TMP_DIR/priv")

if [ -z "$ITEM_NAME" ] || [ "$ITEM_NAME" == "null" ] || [ -z "$PRIV_KEY" ]; then
  echo "Error: No native SSH Key (type 5) found matching '$SEARCH_TERM'." >&2
  exit 1
fi

log "🔑 Found SSH key: '$ITEM_NAME'"

# ==============================================================================
# DIRECTORY SETUP
# ==============================================================================
if [ ! -d "$TARGET_DIR" ]; then
  log "📁 Creating directory: $(display_path "$TARGET_DIR")"
  mkdir -p "$TARGET_DIR"
  chmod 700 "$TARGET_DIR"
fi

PUB_FILE="$TARGET_DIR/$ITEM_NAME.pub"

# ==============================================================================
# PUBLIC KEY HANDLING (Hash check & Save)
# ==============================================================================
SKIP_PUB_SAVE=false

if [ -f "$PUB_FILE" ]; then
  # Determine hash command (Linux vs macOS)
  if command -v sha256sum &>/dev/null; then
    HASH_CMD="sha256sum"
  else
    HASH_CMD="shasum -a 256"
  fi

  EXISTING_HASH=$($HASH_CMD "$PUB_FILE" | awk '{print $1}')
  NEW_HASH=$(echo "$PUB_KEY" | $HASH_CMD | awk '{print $1}')

  if [ "$EXISTING_HASH" == "$NEW_HASH" ]; then
    log "✅ Public key '$(display_path "$PUB_FILE")' exists and matches vault. Skipping save."
    SKIP_PUB_SAVE=true
  else
    if [ "$FORCE" = true ]; then
      log "⚠️  Public key '$(display_path "$PUB_FILE")' exists but DIFFERS from vault."
      log "   --force specified. Backing up to '$(display_path "$PUB_FILE").bak' and overwriting."
      mv "$PUB_FILE" "$PUB_FILE.bak"
    else
      echo "⚠️  Public key '$(display_path "$PUB_FILE")' exists but DIFFERS from vault." >&2
      echo "   Neither public nor private keys will be saved. Use --force to overwrite." >&2
      exit 1
    fi
  fi
fi

if [ "$SKIP_PUB_SAVE" = false ]; then
  echo "$PUB_KEY" >"$PUB_FILE"
  chmod 644 "$PUB_FILE"
  log "💾 Saved public key to: $(display_path "$PUB_FILE")"
fi

# ==============================================================================
# PRIVATE KEY HANDLING (ssh-agent)
# ==============================================================================
# Ensure ssh-agent is running
if [ -z "${SSH_AUTH_SOCK:-}" ] || ! ssh-add -l &>/dev/null; then
  log "🔄 Starting ssh-agent..."
  eval "$(ssh-agent -s)" >/dev/null
fi

log "🔒 Adding private key to ssh-agent..."
# tr -d '\r' strips hidden Windows carriage returns
if ! echo "$PRIV_KEY" | tr -d '\r' | ssh-add - >/dev/null 2>&1; then
  echo "❌ Failed to add key to ssh-agent. (Does it require a passphrase?)" >&2
  exit 1
fi

log "✅ Private key loaded into ssh-agent."

# ==============================================================================
# CONFIG FILE HANDLING (Optional)
# ==============================================================================
if [ "$UPDATE_CONFIG" = true ]; then
  CONFIG_FILE="$HOME/.ssh/config"
  touch "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"

  # Check if Host block already exists
  if grep -q "^Host $ITEM_NAME$" "$CONFIG_FILE" 2>/dev/null; then
    log "ℹ️  Host '$ITEM_NAME' already exists in $(display_path "$CONFIG_FILE"). Skipping config update."
  else
    log "📝 Updating $(display_path "$CONFIG_FILE")..."
    cat <<EOF >>"$CONFIG_FILE"

# Added by bw_ssh on $(date +%Y-%m-%d)
Host $ITEM_NAME
IdentityFile $(display_path "$PUB_FILE")
    IdentitiesOnly yes
EOF
    log "✅ Added Host '$ITEM_NAME' to $(display_path "$CONFIG_FILE")."
  fi
fi

log "🎉 Done!"
