#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
#  SCRIPT METADATA
# ═══════════════════════════════════════════════════════════════════════════
SCRIPT_VERSION="1.4.0"
SKILL_NAME="xngTool"
SKILL_VERSION="1.0.0"
SKILL_AUTHOR="Hermes Community"
SKILL_DESCRIPTION="SearXNG-powered web search tool for Hermes"

# ═══════════════════════════════════════════════════════════════════════════
#  COLORS  (disabled when stdout is not a terminal)
# ═══════════════════════════════════════════════════════════════════════════
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ═══════════════════════════════════════════════════════════════════════════
#  LOGGING
# ═══════════════════════════════════════════════════════════════════════════
_LOG_FD=""

_log() {
    [[ -n "$_LOG_FD" ]] || return 0
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >&"$_LOG_FD"
}

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; _log "INFO  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; _log "WARN  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; _log "ERROR $*"; }
step()  { echo -e "${BLUE}[STEP]${NC}  $*"; _log "STEP  $*"; }

# ═══════════════════════════════════════════════════════════════════════════
#  TRAP – structured error reporting  (NEW)
# ═══════════════════════════════════════════════════════════════════════════
_error_handler() {
    local exit_code=$?
    local line_no=$1
    local cmd="$2"
    echo ""
    error "Script aborted (exit $exit_code)"
    error "  Line    : $line_no"
    error "  Command : $cmd"
    error "  Log     : ${LOG_FILE:-<not yet initialised>}"
    _log "FATAL exit=$exit_code line=$line_no cmd=$cmd"
    exit "$exit_code"
}
trap '_error_handler "${LINENO}" "${BASH_COMMAND}"' ERR

# ═══════════════════════════════════════════════════════════════════════════
#  PATH RESOLUTION
# ═══════════════════════════════════════════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_CONFIG="$HERMES_HOME/config.yaml"
SKILL_DIR="$HERMES_HOME/skills/xngTool"
PYTHON_CMD="${PYTHON_CMD:-python3}"

# ═══════════════════════════════════════════════════════════════════════════
#  FLAGS
# ═══════════════════════════════════════════════════════════════════════════
FLAG_UNINSTALL=false
FLAG_FORCE=false
FLAG_HELP=false
FLAG_DRY_RUN=false
FLAG_VERBOSE=false
FLAG_VERIFY=true          # checksum-verify copied files

# ═══════════════════════════════════════════════════════════════════════════
#  USAGE
# ═══════════════════════════════════════════════════════════════════════════
usage() {
    cat <<USAGE

${BOLD}${BLUE}xngTool Installer v${SCRIPT_VERSION}${NC}

${BOLD}Usage:${NC}  $(basename "$0") [OPTIONS]

${BOLD}Options:${NC}
  -h, --help        Show this help and exit
  -u, --uninstall   Remove the skill and clean config.yaml
  -f, --force       Overwrite / answer yes to every prompt
  -d, --dry-run     Show what would be done without changing anything
  -v, --verbose     Mirror all output into the log file
  -V, --version     Print version and exit

${BOLD}Environment:${NC}
  HERMES_HOME       Hermes home dir          (default: ~/.hermes)
  SEARXNG_URL       SearXNG instance URL     (default: http://127.0.0.1:8888)
  PYTHON_CMD        Python 3 binary          (default: python3)
  LOG_FILE          Log path                 (default: ~/.hermes/xngtool_install.log)
  HTTP_PROXY        Proxy for connectivity checks
  HTTPS_PROXY       Proxy for connectivity checks

${BOLD}Examples:${NC}
  ./install.sh                                   # standard install
  SEARXNG_URL="http://sx.local:8080" ./install.sh
  ./install.sh --force                           # no prompts
  ./install.sh --dry-run                         # preview only
  ./install.sh -u                                # uninstall

${BOLD}Security notes:${NC}
  SELinux   →  sudo chcon -R -t bin_t ~/.hermes/skills/xngTool/scripts/
  AppArmor  →  allow read/execute on the skill dir in the Hermes profile

USAGE
}

# ═══════════════════════════════════════════════════════════════════════════
#  ARGUMENT PARSING  (before logging so --help / --version stay clean)
# ═══════════════════════════════════════════════════════════════════════════
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)            FLAG_HELP=true;      shift ;;
        -u|--uninstall|remove) FLAG_UNINSTALL=true; shift ;;
        -f|--force)           FLAG_FORCE=true;     shift ;;
        -d|--dry-run)         FLAG_DRY_RUN=true;   shift ;;
        -v|--verbose)         FLAG_VERBOSE=true;   shift ;;
        -V|--version)         echo "install.sh v${SCRIPT_VERSION}"; exit 0 ;;
        *)
            error "Unknown option: $1"; echo ""; usage; exit 1 ;;
    esac
done

[[ "$FLAG_HELP" == true ]] && { usage; exit 0; }

# ═══════════════════════════════════════════════════════════════════════════
#  LOGGING SETUP  (after arg-parse; non-verbose keeps terminal clean)
# ═══════════════════════════════════════════════════════════════════════════
LOG_FILE="${LOG_FILE:-$HOME/.hermes/xngtool_install.log}"

_setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec 3>>"$LOG_FILE"
    _LOG_FD=3
    _log "══ install.sh v${SCRIPT_VERSION} started (verbose=$FLAG_VERBOSE dry-run=$FLAG_DRY_RUN) ══"

    if [[ "$FLAG_VERBOSE" == true ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}
_setup_logging

# ═══════════════════════════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

# ─── confirm()  (FIX: proper default handling) ──────────────────────────
#   confirm "Prompt text" [Y|N]
#   Default controls what Enter (empty input) does.
confirm() {
    local prompt="$1"
    local default="${2:-N}"

    # Non-interactive → honour --force or fall back to default
    if [[ ! -t 0 ]]; then
        if [[ "$FLAG_FORCE" == true ]]; then return 0; fi
        [[ "${default^^}" == "Y" ]]
        return $?
    fi

    local hint
    [[ "${default^^}" == "Y" ]] && hint="[Y/n]" || hint="[y/N]"

    local answer
    read -rp "${prompt} ${hint} " answer
    answer="${answer:-$default}"          # empty → use default

    [[ "${answer,,}" =~ ^(y|yes)$ ]]
}

# ─── URL validation  (SIMPLIFIED) ───────────────────────────────────────
validate_url_format() {
    local url="$1"
    # Must start with http:// or https://, have a host, optional port/path
    if [[ "$url" =~ ^https?://[^[:space:]/][^[:space:]]*$ ]]; then
        return 0
    fi
    error "Invalid URL: $url  (expected http://host[:port][/path])"
    return 1
}

# ─── Write-permission check  (NEW) ──────────────────────────────────────
require_writable() {
    local target="$1"
    local label="${2:-$target}"

    # Walk upward to the first existing ancestor
    local probe="$target"
    while [[ ! -e "$probe" ]]; do
        probe="$(dirname "$probe")"
    done

    if [[ ! -w "$probe" ]]; then
        error "No write permission on: $probe  (needed for $label)"
        error "Try:  sudo chown -R \$(whoami) \"$probe\""
        return 1
    fi
    _log "Write OK: $probe"
    return 0
}

# ─── File checksum verification  (NEW) ──────────────────────────────────
_verify_copy() {
    local src="$1" dst="$2"
    if command -v sha256sum &>/dev/null; then
        [[ "$(sha256sum < "$src")" == "$(sha256sum < "$dst")" ]]
    elif command -v md5sum &>/dev/null; then
        [[ "$(md5sum < "$src")" == "$(md5sum < "$dst")" ]]
    else
        cmp -s "$src" "$dst"
    fi
}

# ─── Detect existing installed version  (NEW) ───────────────────────────
_installed_version() {
    local manifest="$SKILL_DIR/skill.json"
    [[ -f "$manifest" ]] || { echo ""; return; }
    "$PYTHON_CMD" -c "
import json, sys
try:
    print(json.load(open(sys.argv[1]))['version'])
except Exception:
    print('')
" "$manifest" 2>/dev/null
}

# ─── PEP 668 / externally-managed pip  (NEW) ────────────────────────────
_pip_install() {
    local pkg="$1"

    # 1. Try plain pip
    if "$PYTHON_CMD" -m pip install --quiet "$pkg" 2>/dev/null; then
        return 0
    fi

    # 2. Try --user
    if "$PYTHON_CMD" -m pip install --quiet --user "$pkg" 2>/dev/null; then
        return 0
    fi

    # 3. Detect PEP 668 EXTERNALLY-MANAGED marker
    local stdlib_dir
    stdlib_dir="$("$PYTHON_CMD" -c "import sysconfig; print(sysconfig.get_path('stdlib'))" 2>/dev/null)"
    if [[ -n "$stdlib_dir" && -f "$(dirname "$stdlib_dir")/EXTERNALLY-MANAGED" ]]; then
        warn "PEP 668: this Python is externally managed."
        warn "Options:"
        warn "  a) python3 -m venv ~/.hermes/.venv && source ~/.hermes/.venv/bin/activate"
        warn "  b) pip install --break-system-packages $pkg   (not recommended)"
        warn "  c) Install via your distro package manager (e.g. apt install python3-yaml)"
        echo ""
        if confirm "Try --break-system-packages?" "N"; then
            "$PYTHON_CMD" -m pip install --quiet --break-system-packages "$pkg"
            return $?
        fi
        return 1
    fi

    # 4. Last resort: pip3 binary
    if command -v pip3 &>/dev/null && pip3 install --quiet "$pkg" 2>/dev/null; then
        return 0
    fi

    return 1
}

# ─── Security module detection ───────────────────────────────────────────
check_security_modules() {
    local shown=false

    if command -v getenforce &>/dev/null && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
        [[ "$shown" == false ]] && { echo ""; warn "Security-hardened system:"; shown=true; }
        warn "  SELinux ENFORCING – if skill scripts fail to execute:"
        warn "    sudo chcon -R -t bin_t \"$SKILL_DIR/scripts/\""
        if ! sudo -n true 2>/dev/null; then
            warn "  (passwordless sudo unavailable)"
        fi
    fi

    if command -v aa-status &>/dev/null && aa-status --enabled 2>/dev/null; then
        [[ "$shown" == false ]] && { echo ""; warn "Security-hardened system:"; shown=true; }
        warn "  AppArmor ENABLED – allow read/execute on $SKILL_DIR/scripts/"
    fi
}

# ─── SearXNG connectivity ───────────────────────────────────────────────
validate_searxng_url() {
    local url="${1%/}"
    local timeout=8

    validate_url_format "$url" || return 1
    info "Probing SearXNG at $url ..."
    _log "SearXNG probe: $url"

    local -a endpoints=("$url/healthz" "$url/search?q=test&format=json")

    if command -v curl &>/dev/null; then
        for ep in "${endpoints[@]}"; do
            if curl -sf --max-time "$timeout" "$ep" &>/dev/null; then
                info "✓ SearXNG reachable ($ep)"; return 0
            fi
        done
    elif command -v wget &>/dev/null; then
        for ep in "${endpoints[@]}"; do
            if wget -q --timeout="$timeout" -O /dev/null "$ep" 2>/dev/null; then
                info "✓ SearXNG reachable ($ep)"; return 0
            fi
        done
    elif command -v "$PYTHON_CMD" &>/dev/null; then
        if SEARXNG_PROBE_URL="$url" "$PYTHON_CMD" -c "
import os, sys, urllib.request
base = os.environ['SEARXNG_PROBE_URL']
for p in ('/healthz', '/search?q=test&format=json'):
    try:
        urllib.request.urlopen(base + p, timeout=8); sys.exit(0)
    except Exception: pass
sys.exit(1)
" 2>/dev/null; then
            info "✓ SearXNG reachable"; return 0
        fi
    else
        warn "No HTTP client found – skipping connectivity check"
        return 0
    fi

    warn "✗ SearXNG unreachable at $url (install will proceed)"
    _log "SearXNG unreachable"
    return 1
}

# ─── Systemd service detection ──────────────────────────────────────────
check_searxng_service() {
    command -v systemctl &>/dev/null || return 0
    if systemctl is-active --quiet searxng 2>/dev/null; then
        info "SearXNG systemd service is active"
    elif systemctl list-unit-files 2>/dev/null | grep -q "searxng\.service"; then
        warn "SearXNG unit exists but is stopped. Start: sudo systemctl start searxng"
    fi
    return 0
}

# ─── Generate + validate manifest  (ENHANCED) ───────────────────────────
generate_manifest() {
    local manifest_path="$SKILL_DIR/skill.json"

    MANIFEST_NAME="$SKILL_NAME" \
    MANIFEST_VERSION="$SKILL_VERSION" \
    MANIFEST_DESC="$SKILL_DESCRIPTION" \
    MANIFEST_AUTHOR="$SKILL_AUTHOR" \
    MANIFEST_INSTALLER="$SCRIPT_VERSION" \
    MANIFEST_SEARXNG="${SEARXNG_URL:-http://127.0.0.1:8888}" \
    MANIFEST_DIR="$SKILL_DIR" \
    "$PYTHON_CMD" << 'PYEOF'
import json, os, datetime, sys

manifest = {
    "name":              os.environ["MANIFEST_NAME"],
    "version":           os.environ["MANIFEST_VERSION"],
    "description":       os.environ["MANIFEST_DESC"],
    "author":            os.environ["MANIFEST_AUTHOR"],
    "installer_version": os.environ["MANIFEST_INSTALLER"],
    "installed_at":      datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "entrypoint":        "scripts/xngTool.py",
    "files":             ["SKILL.md", "README.md", "scripts/xngTool.py"],
    "dependencies":      {"python": ">=3.7", "pyyaml": ">=5.0"},
    "config": {
        "searxng_url":   os.environ["MANIFEST_SEARXNG"],
        "backend":       "searxng",
    },
}

path = os.path.join(os.environ["MANIFEST_DIR"], "skill.json")
with open(path, "w") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")

# ── structural validation (not just syntax) ──
REQUIRED_KEYS = {"name": str, "version": str, "entrypoint": str,
                 "files": list, "dependencies": dict, "config": dict}
with open(path) as f:
    check = json.load(f)

errors = []
for key, typ in REQUIRED_KEYS.items():
    if key not in check:
        errors.append(f"missing key: {key}")
    elif not isinstance(check[key], typ):
        errors.append(f"{key}: expected {typ.__name__}, got {type(check[key]).__name__}")

if not check.get("files"):
    errors.append("files list is empty")
if "searxng_url" not in check.get("config", {}):
    errors.append("config.searxng_url missing")

if errors:
    print(f"[WARN] Manifest structural issues: {'; '.join(errors)}", file=sys.stderr)
    sys.exit(1)

print(f"[INFO] Manifest written + validated: {path}")
PYEOF

    if [[ $? -eq 0 ]]; then
        info "Manifest OK: $manifest_path"
        _log "Manifest valid"
    else
        warn "Manifest written but failed structural validation"
        _log "Manifest INVALID"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
#  UNINSTALL
# ═══════════════════════════════════════════════════════════════════════════
uninstall() {
    echo ""
    step "Removing xngTool skill..."
    _log "Uninstall started"

    if [[ -d "$SKILL_DIR" ]]; then
        rm -rf "$SKILL_DIR"
        info "Removed: $SKILL_DIR"
    else
        warn "Not found: $SKILL_DIR – nothing to remove."
    fi

    if [[ -f "$HERMES_CONFIG" ]]; then
        info "Cleaning config.yaml..."
        (
            export HERMES_CONFIG
            "$PYTHON_CMD" << 'PYEOF'
import os, sys, yaml
p = os.environ["HERMES_CONFIG"]
try:
    cfg = yaml.safe_load(open(p)) or {}
    web = cfg.get("web") or {}
    changed = any(web.pop(k, None) is not None for k in ("searxng_url", "backend"))
    if not web: cfg.pop("web", None)
    else: cfg["web"] = web
    if changed:
        yaml.dump(cfg, open(p, "w"), default_flow_style=False,
                  sort_keys=False, allow_unicode=True)
        print("[INFO] Config entries removed.")
    else:
        print("[INFO] Nothing to clean.")
except Exception as e:
    print(f"[WARN] {e}", file=sys.stderr)
PYEOF
        ) || warn "Config cleanup issue (see log)"
    fi

    echo ""
    info "✔ xngTool removed."
    _log "Uninstall done"
    exit 0
}

[[ "$FLAG_UNINSTALL" == true ]] && uninstall

# ═══════════════════════════════════════════════════════════════════════════
#  DRY RUN  (full walk-through, no mutations)
# ═══════════════════════════════════════════════════════════════════════════
if [[ "$FLAG_DRY_RUN" == true ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}━━━ DRY RUN – nothing will be changed ━━━${NC}"
    echo ""

    step "Source files"
    for f in SKILL.md README.md xngTool.py; do
        [[ -f "$SCRIPT_DIR/$f" ]] \
            && info "  ✓ $f" \
            || error "  ✗ $f MISSING"
    done

    step "Python"
    if command -v "$PYTHON_CMD" &>/dev/null; then
        info "  ✓ $PYTHON_CMD ($("$PYTHON_CMD" --version 2>&1))"
    else
        error "  ✗ $PYTHON_CMD not found"
    fi

    step "Targets"
    info "  Skill dir : $SKILL_DIR"
    info "  Config    : $HERMES_CONFIG"
    info "  SearXNG   : ${SEARXNG_URL:-http://127.0.0.1:8888}"

    local_existing="$(_installed_version)"
    [[ -n "$local_existing" ]] \
        && warn "  Existing version: $local_existing → would upgrade to $SKILL_VERSION" \
        || info "  No existing installation"

    step "Actions that would run"
    echo "  1. mkdir -p $SKILL_DIR/scripts"
    echo "  2. install -m 644 SKILL.md README.md → $SKILL_DIR/"
    echo "  3. install -m 755 xngTool.py        → $SKILL_DIR/scripts/"
    echo "  4. Generate + validate skill.json"
    echo "  5. Update web.searxng_url in $HERMES_CONFIG"
    echo "  6. Checksum-verify all copied files"
    echo ""
    info "Re-run without --dry-run to execute."
    _log "Dry run complete"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
#  INSTALL
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${CYAN}━━━ xngTool Installer v${SCRIPT_VERSION} ━━━${NC}"
echo ""

# ─── Required files ──────────────────────────────────────────────────────
step "Verifying source files..."
for f in SKILL.md README.md xngTool.py; do
    if [[ ! -f "$SCRIPT_DIR/$f" ]]; then
        error "Missing: $SCRIPT_DIR/$f"
        error "Run this script from the xngTool source directory."
        exit 1
    fi
done
info "All source files present."

# ─── Write-permission pre-flight  (NEW) ─────────────────────────────────
step "Checking write permissions..."
require_writable "$HERMES_HOME"  "Hermes home"
require_writable "$SKILL_DIR"    "skill directory"
require_writable "$(dirname "$HERMES_CONFIG")" "config.yaml"
info "Write permissions OK."

# ─── Hermes home ─────────────────────────────────────────────────────────
[[ -d "$HERMES_HOME" ]] || { warn "Creating $HERMES_HOME"; mkdir -p "$HERMES_HOME"; }

# ─── Python + PyYAML ─────────────────────────────────────────────────────
echo ""
step "Checking Python..."

if ! command -v "$PYTHON_CMD" &>/dev/null; then
    error "'$PYTHON_CMD' not found. Set PYTHON_CMD or install Python 3."
    exit 1
fi

PYTHON_VERSION="$("$PYTHON_CMD" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")"
if "$PYTHON_CMD" -c "import sys; sys.exit(0 if sys.version_info >= (3,7) else 1)"; then
    info "Python $PYTHON_VERSION ✓"
else
    warn "Python $PYTHON_VERSION < 3.7"
    confirm "Continue anyway?" || exit 1
fi

step "Checking PyYAML..."
if "$PYTHON_CMD" -c "
import yaml, sys
v = tuple(int(x) for x in yaml.__version__.split('.')[:2])
sys.exit(0 if v >= (5,0) else 1)
" 2>/dev/null; then
    info "PyYAML $("$PYTHON_CMD" -c "import yaml; print(yaml.__version__)") ✓"
else
    warn "PyYAML ≥ 5.0 not found."
    if confirm "Install PyYAML now?" "Y"; then
        info "Installing PyYAML (PEP 668-aware)..."
        if _pip_install "pyyaml>=5.0"; then
            info "PyYAML installed ✓"
        else
            error "Could not install PyYAML. See hints above."
            exit 1
        fi
    else
        error "PyYAML is required."; exit 1
    fi
fi
_log "Python deps OK"

# ─── Existing version detection  (NEW) ──────────────────────────────────
EXISTING_VER="$(_installed_version)"
if [[ -n "$EXISTING_VER" ]]; then
    echo ""
    if [[ "$EXISTING_VER" == "$SKILL_VERSION" ]]; then
        info "xngTool v$EXISTING_VER is already installed (same version)."
    else
        info "Upgrading xngTool: v$EXISTING_VER → v$SKILL_VERSION"
    fi
    _log "Existing version: $EXISTING_VER"

    if [[ "$FLAG_FORCE" != true ]]; then
        confirm "Overwrite existing installation?" || { info "Aborted."; exit 0; }
    else
        warn "Overwriting (--force)."
    fi
fi

# ─── Install files  (using install(1) instead of cp+chmod) ──────────────
echo ""
step "Installing skill files..."

mkdir -p "$SKILL_DIR/scripts"

# Backup
if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
    bak="$SKILL_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bak"
    cp -a "$SKILL_DIR/SKILL.md" "$SKILL_DIR/README.md" "$bak/" 2>/dev/null || true
    [[ -d "$SKILL_DIR/scripts" ]] && cp -a "$SKILL_DIR/scripts" "$bak/" 2>/dev/null || true
    info "Backup → $bak"
    _log "Backup at $bak"
fi

# install(1) = copy + set permissions in one atomic step
install -m 644 "$SCRIPT_DIR/SKILL.md"   "$SKILL_DIR/SKILL.md"
install -m 644 "$SCRIPT_DIR/README.md"  "$SKILL_DIR/README.md"
install -m 755 "$SCRIPT_DIR/xngTool.py" "$SKILL_DIR/scripts/xngTool.py"

info "Files installed."
_log "Files copied via install(1)"

# ─── Checksum verification  (NEW) ───────────────────────────────────────
if [[ "$FLAG_VERIFY" == true ]]; then
    step "Verifying copied files..."
    VERIFY_OK=true
    declare -A FILE_MAP=(
        ["$SCRIPT_DIR/SKILL.md"]="$SKILL_DIR/SKILL.md"
        ["$SCRIPT_DIR/README.md"]="$SKILL_DIR/README.md"
        ["$SCRIPT_DIR/xngTool.py"]="$SKILL_DIR/scripts/xngTool.py"
    )
    for src in "${!FILE_MAP[@]}"; do
        dst="${FILE_MAP[$src]}"
        if _verify_copy "$src" "$dst"; then
            info "  ✓ $(basename "$dst") checksum OK"
        else
            error "  ✗ $(basename "$dst") CHECKSUM MISMATCH"
            VERIFY_OK=false
        fi
    done
    if [[ "$VERIFY_OK" != true ]]; then
        error "File verification failed – aborting."
        exit 1
    fi
    _log "Checksums verified"
fi

# ─── Manifest ────────────────────────────────────────────────────────────
echo ""
step "Generating skill manifest..."
generate_manifest

# ─── SearXNG config ──────────────────────────────────────────────────────
echo ""
step "Configuring SearXNG..."

SEARXNG_URL="${SEARXNG_URL:-http://127.0.0.1:8888}"
check_searxng_service
validate_searxng_url "$SEARXNG_URL" || true

(
    export HERMES_CONFIG SEARXNG_URL
    "$PYTHON_CMD" << 'PYEOF'
import os, sys, yaml

p   = os.environ["HERMES_CONFIG"]
url = os.environ["SEARXNG_URL"]

try:
    cfg = yaml.safe_load(open(p)) or {}
except FileNotFoundError:
    cfg = {}
except yaml.YAMLError as e:
    print(f"[ERROR] YAML parse: {e}", file=sys.stderr); sys.exit(1)

web = cfg.get("web") or {}
if web.get("searxng_url") == url and web.get("backend") == "searxng":
    print(f"[INFO] Already configured: {url}"); sys.exit(0)

old = web.get("searxng_url", "")
if old: print(f"[INFO] Updating: {old} → {url}")

web["searxng_url"] = url
web["backend"]     = "searxng"
cfg["web"]         = web

os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
with open(p, "w") as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
print(f"[INFO] ✓ web.searxng_url = {url}")
PYEOF
) || {
    error "Config update failed. Add manually to $HERMES_CONFIG:"
    echo "  web:"
    echo "    backend: searxng"
    echo "    searxng_url: $SEARXNG_URL"
    exit 1
}
_log "Config updated"

# ─── Security notes ──────────────────────────────────────────────────────
check_security_modules

# ─── Final verification ─────────────────────────────────────────────────
echo ""
step "Final check..."
FINAL_OK=true
for f in "$SKILL_DIR/SKILL.md" "$SKILL_DIR/README.md" \
         "$SKILL_DIR/scripts/xngTool.py" "$SKILL_DIR/skill.json"; do
    [[ -f "$f" ]] && info "  ✓ $(basename "$f")" || { error "  ✗ $(basename "$f")"; FINAL_OK=false; }
done
[[ "$FINAL_OK" == true ]] || exit 1

# ─── Done ────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}━━━ Installation Complete ━━━${NC}"
echo ""
info "Skill   : $SKILL_DIR"
info "Config  : $HERMES_CONFIG"
info "SearXNG : $SEARXNG_URL"
info "Log     : $LOG_FILE"
echo ""
info "Test:  $PYTHON_CMD $SKILL_DIR/scripts/xngTool.py search \"hello\" --json"
info "Remove: $(basename "$0") --uninstall"
echo ""

_log "══ install.sh finished OK ══"
