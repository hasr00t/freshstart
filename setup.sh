#!/usr/bin/env bash
# kali-setup.sh — provision a fresh Kali VM on Parallels.
# Run as root: sudo ./kali-setup.sh

set -u
set -o pipefail

readonly LOG="/var/log/kali-setup.log"
readonly FAILURES="/var/log/kali-setup-failures.log"
readonly TOOLS_DIR="/opt/tools"

# GitHub repos to clone + auto-build. Deduped from tools-to-install.txt.
readonly GITHUB_REPOS=(
  "https://github.com/dirkjanm/mitm6"
  "https://github.com/CiscoCXSecurity/rdp-sec-check"
  "https://github.com/drwetter/testssl.sh"
  "https://github.com/danielmiessler/SecLists"
  "https://github.com/topotam/PetitPotam"
  "https://github.com/p0dalirius/Coercer"
  "https://github.com/dirkjanm/ldapdomaindump"
  "https://github.com/p0dalirius/FindUncommonShares"
  "https://github.com/RedTeamPentesting/pretender"
  "https://github.com/impostorkeanu/eavesarp-ng"
  "https://github.com/sullo/nikto"
  "https://github.com/DefensiveOrigins/icmp-timestamp"
  "https://github.com/dirkjanm/PKINITtools"
  "https://github.com/AD-Security/AD_Miner"
  "https://github.com/PlumHound/PlumHound"
  "https://github.com/dehobbs/ADScan"
  "https://github.com/hasr00t/sccmhunter"
  "https://github.com/garrettfoster13/pre2k"
  "https://github.com/csandker/pxethiefy"
  "https://github.com/login-securite/DonPAPI"
  "https://github.com/nyxgeek/ntlmscan"
  "https://github.com/absolomb/FindMeAccess"
  "https://github.com/dafthack/MFASweep"
  "https://github.com/ropnop/kerbrute"
  "https://github.com/Tylous/Talon"
  "https://github.com/Mr-Un1k0d3r/PowerLessShell"
  "https://github.com/Tylous/Mangle"
  "https://github.com/Tylous/ScareCrow"
  "https://github.com/Tylous/Ivy"
  "https://github.com/NetSPI/PowerHuntShares"
  "https://github.com/cisagov/snafflepy"
  "https://github.com/blacklanternsecurity/manspider"
  "https://github.com/Hackndo/WebclientServiceScanner"
  "https://github.com/synacktiv/GPOddity"
  "https://github.com/clr2of8/DPAT"
  "https://github.com/dafthack/GraphRunner"
  "https://github.com/subat0mik/Misconfiguration-Manager"
)

readonly APT_TOOLS=(
  nuclei
  feroxbuster
  eyewitness
  certipy-ad
  bloodhound
  responder
)

readonly PREREQS=(
  git
  python3-venv
  python3-pip
  python3-dev
  libpcap-dev
  golang
  build-essential
  perl
  wget
  curl
  make
  unzip
  mingw-w64
)

# Counters used by the final summary.
REPO_OK=0
REPO_FAIL=0
APT_OK=0
APT_FAIL=0
EXTRAS_OK=0
EXTRAS_FAIL=0

log() {
  local msg="$1"
  printf '%s %s\n' "$(date -Is)" "$msg" | tee -a "$LOG"
}

log_failure() {
  local subject="$1"
  local reason="$2"
  printf '%s [FAIL] %s — %s\n' "$(date -Is)" "$subject" "$reason" >> "$FAILURES"
}

# run_step LABEL CMD [ARGS...]
# Runs CMD, streams output to the main log, returns the command's exit code.
# Caller decides whether to abort on failure.
run_step() {
  local label="$1"; shift
  log "BEGIN $label"
  if "$@" >>"$LOG" 2>&1; then
    log "OK    $label"
    return 0
  fi
  local rc=$?
  log "FAIL  $label (exit $rc)"
  log_failure "$label" "exit $rc"
  return "$rc"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "ERROR: kali-setup.sh must be run as root. Try: sudo $0" >&2
    exit 1
  fi
}

init_logs() {
  : > "$LOG"
  : > "$FAILURES"
  log "kali-setup.sh starting"
}

phase_update() {
  log "=== Phase 1: VM update ==="
  export DEBIAN_FRONTEND=noninteractive
  if ! run_step "apt update" apt-get update; then
    log "FATAL: apt update failed; aborting."
    exit 1
  fi
  if ! run_step "apt full-upgrade" apt-get full-upgrade -y; then
    log "FATAL: apt full-upgrade failed; aborting."
    exit 1
  fi
}

phase_prereqs() {
  log "=== Phase 2: Prerequisites ==="
  if ! run_step "apt install prereqs" apt-get install -y "${PREREQS[@]}"; then
    log "FATAL: prerequisite install failed; aborting."
    exit 1
  fi
}

phase_workspace() {
  log "=== Phase 3: Workspace ==="
  if ! run_step "mkdir $TOOLS_DIR" mkdir -p "$TOOLS_DIR"; then
    log "FATAL: could not create $TOOLS_DIR; aborting."
    exit 1
  fi
  export GOPATH="/root/go"
  export GOBIN="/root/go/bin"
  mkdir -p "$GOPATH" "$GOBIN"
  export PATH="$GOBIN:$PATH"
  log "GOPATH=$GOPATH GOBIN=$GOBIN"
}

repo_name_from_url() {
  local url="$1"
  local base="${url##*/}"
  printf '%s' "${base%.git}"
}

# build_repo REPO_DIR REPO_NAME
# Detects build type and runs the appropriate install. Returns 0 on success or
# clone-only (no build needed); non-zero on build failure.
build_repo() {
  local dir="$1"
  local name="$2"
  local venv="$dir/.venv"

  if [[ -f "$dir/pyproject.toml" ]]; then
    log "build $name: pyproject.toml -> venv + pip install ."
    python3 -m venv "$venv" >>"$LOG" 2>&1 || return 1
    "$venv/bin/pip" install --upgrade pip >>"$LOG" 2>&1 || return 1
    ( cd "$dir" && "$venv/bin/pip" install . ) >>"$LOG" 2>&1 || return 1
    return 0
  fi

  if [[ -f "$dir/setup.py" ]]; then
    log "build $name: setup.py -> venv + pip install ."
    python3 -m venv "$venv" >>"$LOG" 2>&1 || return 1
    "$venv/bin/pip" install --upgrade pip >>"$LOG" 2>&1 || return 1
    ( cd "$dir" && "$venv/bin/pip" install . ) >>"$LOG" 2>&1 || return 1
    return 0
  fi

  if [[ -f "$dir/requirements.txt" ]]; then
    log "build $name: requirements.txt -> venv + pip install -r"
    python3 -m venv "$venv" >>"$LOG" 2>&1 || return 1
    "$venv/bin/pip" install --upgrade pip >>"$LOG" 2>&1 || return 1
    "$venv/bin/pip" install -r "$dir/requirements.txt" >>"$LOG" 2>&1 || return 1
    return 0
  fi

  if [[ -f "$dir/go.mod" ]]; then
    log "build $name: go.mod -> go build"
    ( cd "$dir" && go build ./... ) >>"$LOG" 2>&1 || return 1
    return 0
  fi

  if [[ -f "$dir/Makefile" ]]; then
    log "build $name: Makefile -> make"
    ( cd "$dir" && make ) >>"$LOG" 2>&1 || return 1
    return 0
  fi

  log "build $name: no recognized build files (clone-only)"
  return 0
}

# process_repo URL
# Clones (or pulls) the repo, then auto-builds it. Updates REPO_OK / REPO_FAIL.
process_repo() {
  local url="$1"
  local name
  name="$(repo_name_from_url "$url")"
  local dir="$TOOLS_DIR/$name"

  log "--- repo: $name ($url) ---"

  if [[ -d "$dir/.git" ]]; then
    if ! run_step "git pull $name" git -C "$dir" pull --ff-only; then
      REPO_FAIL=$((REPO_FAIL + 1))
      return
    fi
  else
    if ! run_step "git clone $name" git clone --depth 1 "$url" "$dir"; then
      REPO_FAIL=$((REPO_FAIL + 1))
      return
    fi
  fi

  if build_repo "$dir" "$name"; then
    log "OK    build $name"
    REPO_OK=$((REPO_OK + 1))
  else
    local rc=$?
    log "FAIL  build $name (exit $rc)"
    log_failure "build $name" "exit $rc"
    REPO_FAIL=$((REPO_FAIL + 1))
  fi
}

phase_github() {
  log "=== Phase 4: GitHub tools ==="
  for url in "${GITHUB_REPOS[@]}"; do
    process_repo "$url"
  done
}

phase_apt_tools() {
  log "=== Phase 5: apt tools ==="
  export DEBIAN_FRONTEND=noninteractive
  for pkg in "${APT_TOOLS[@]}"; do
    if run_step "apt install $pkg" apt-get install -y "$pkg"; then
      APT_OK=$((APT_OK + 1))
    else
      APT_FAIL=$((APT_FAIL + 1))
    fi
  done
}

phase_extras() {
  log "=== Phase 6: Extras ==="

  # 1. pcapy-ng in a dedicated venv (used by pcredz).
  local pcredz_venv="$TOOLS_DIR/_pcredz-venv"
  if run_step "pcapy-ng venv create" python3 -m venv "$pcredz_venv" \
     && run_step "pcapy-ng pip upgrade" "$pcredz_venv/bin/pip" install --upgrade pip \
     && run_step "pcapy-ng install" "$pcredz_venv/bin/pip" install pcapy-ng; then
    EXTRAS_OK=$((EXTRAS_OK + 1))
  else
    EXTRAS_FAIL=$((EXTRAS_FAIL + 1))
  fi

  # 2. impacket fork (pr_SystemDPAPIdump branch).
  local impacket_zip="$TOOLS_DIR/impacket-pr_SystemDPAPIdump.zip"
  local impacket_url="https://codeload.github.com/clavoillotte/impacket/zip/refs/heads/pr_SystemDPAPIdump"
  if run_step "impacket fork wget" wget -O "$impacket_zip" "$impacket_url" \
     && run_step "impacket fork unzip" unzip -o "$impacket_zip" -d "$TOOLS_DIR"; then
    EXTRAS_OK=$((EXTRAS_OK + 1))
  else
    EXTRAS_FAIL=$((EXTRAS_FAIL + 1))
  fi

  # 3. Tailscale via the official one-liner.
  log "BEGIN install tailscale"
  if curl -fsSL https://tailscale.com/install.sh | sh >>"$LOG" 2>&1; then
    log "OK    install tailscale"
    EXTRAS_OK=$((EXTRAS_OK + 1))
  else
    local rc=$?
    log "FAIL  install tailscale (exit $rc)"
    log_failure "install tailscale" "exit $rc"
    EXTRAS_FAIL=$((EXTRAS_FAIL + 1))
  fi
}

print_summary() {
  local total_repos=${#GITHUB_REPOS[@]}
  local total_apt=${#APT_TOOLS[@]}

  log "=== Summary ==="
  log "GitHub repos: $REPO_OK / $total_repos succeeded ($REPO_FAIL failed)"
  log "apt tools:    $APT_OK / $total_apt succeeded ($APT_FAIL failed)"
  log "Extras:       $EXTRAS_OK / 3 succeeded ($EXTRAS_FAIL failed)"
  if [[ -s "$FAILURES" ]]; then
    log "Failures recorded in: $FAILURES"
  else
    log "No failures recorded."
  fi
  log "Full transcript: $LOG"
  log "kali-setup.sh complete."
}

main() {
  require_root
  init_logs
  phase_update
  phase_prereqs
  phase_workspace
  phase_github
  phase_apt_tools
  phase_extras
  print_summary
}

main "$@"
