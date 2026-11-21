#!/usr/bin/env bash
#
# install.sh — повний бутстрап Dotfiles.
#
# Adaptive to the OS:
#   * NixOS                  -> validate nix/ flake, print integration steps,
#                               optionally run the auto-installer.
#   * Arch-based (Arch/EndeavourOS/Manjaro/CachyOS/...) -> pacman + yay + sync.sh.
#   * Debian/Ubuntu, Fedora, openSUSE, Gentoo -> generic path: packages are installed ONE BY ONE,
#     whatever is missing from the distro repos (quickshell, MangoWM, awww, matugen...) is listed
#     at the end as "install manually" instead of aborting.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Edgit13/Dotfiles/master/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --quickstart
#   # or:
#   git clone https://github.com/Edgit13/Dotfiles.git ~/Dotfiles
#   cd ~/Dotfiles && ./install.sh
#
# Requires: x86_64 with 2 cores, 4 GB RAM and ~30 GB free disk. 2 GB works with
# swap/zram but builds of yay and matugen will swap; the installer warns and
# caps build jobs on low-RAM machines.
#
# Flags:
#   --auto|--quickstart no questions (defaults everywhere)
#   --yes               alias of --auto
#   --minimal           skip optional apps (vlc, nautilus, dolphin, firefox, flatpak, ...)
#   --no-deps           skip packages, only deploy configs (sync.sh) and finishing steps
#   --dry-run           show what would happen, change nothing (not for NixOS)
#   --restore           undo: remove our symlinks and put back the latest ~/.config-backup-*
#   --hardware [--json] print the detected hardware profile and exit
#   --nvidia=open|proprietary|none   NVIDIA driver (default: ask, or open in --auto)
#   --no-tweaks         skip optional tuning (zram, sysctl, I/O scheduler, fstrim, PPD, bluetooth)
#   --with=a,b          enable optional groups, --without=a,b disable them
#                       (files browsers media terminals shell gaming flatpak bluetooth ocr ai)
#   --disk=<dev>        target disk for NixOS auto-install
#   --user=<name>       user to create (NixOS)
#   --password=<pass>   initial password (NixOS)
#
# Every run writes a log and a machine-readable report:
#   ~/.local/state/edots/install-<timestamp>.log
#   ~/.local/state/edots/install-report.json
#
set -uo pipefail

REPO_URL="https://github.com/Edgit13/Dotfiles.git"
REPO_DIR="${EDOTS_DIR:-$HOME/Dotfiles}"

# ── Flags ──
AUTO=0
DRY=0; MINIMAL=0; NODEPS=0; RESTORE=0; TWEAKS=1
SHOW_HW=0; JSON_OUT=0; NVIDIA_MODE="auto"
DISK_ARG=""
WITH_LIST=""; WITHOUT_LIST=""
USER_NAME="${USER:-user}"
USER_PASS="edots"
for a in "$@"; do
  case "$a" in
    --auto|--quickstart|--yes|-y) AUTO=1 ;;
    --dry-run)    DRY=1 ;;
    --minimal)    MINIMAL=1 ;;
    --no-deps)    NODEPS=1 ;;
    --restore)    RESTORE=1 ;;
    --hardware)   SHOW_HW=1 ;;
    --json)       JSON_OUT=1 ;;
    --no-tweaks)  TWEAKS=0 ;;
    --nvidia=*)   NVIDIA_MODE="${a#--nvidia=}" ;;
    --no-nvidia)  NVIDIA_MODE="none" ;;
    --with=*)     WITH_LIST="${WITH_LIST:+$WITH_LIST,}${a#--with=}" ;;
    --without=*)  WITHOUT_LIST="${WITHOUT_LIST:+$WITHOUT_LIST,}${a#--without=}" ;;
    --disk=*)     DISK_ARG="${a#--disk=}" ;;
    --user=*)     USER_NAME="${a#--user=}" ;;
    --password=*) USER_PASS="${a#--password=}" ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--auto|--quickstart] [--minimal] [--no-deps] [--dry-run] [--restore]
          [--hardware [--json]] [--nvidia=open|proprietary|none] [--no-tweaks]
          [--disk=nvme0n1] [--user=name] [--password=pass]

  --auto           skip every prompt (alias: --quickstart, --yes)
  --minimal        skip optional apps (vlc, nautilus, dolphin, firefox, flatpak, ...)
  --no-deps        do not install packages, only deploy configs
  --dry-run        print the plan, change nothing (not for NixOS)
  --restore        remove our symlinks and restore the latest ~/.config-backup-*
  --hardware       print CPU, GPU, memory, disk and tuning, then exit
  --json           with --hardware: emit JSON instead of text
  --nvidia=...     NVIDIA driver: open (Turing+), proprietary (older), none
  --no-tweaks      skip zram, sysctl, I/O scheduler, fstrim, power-profiles-daemon, bluetooth
  --with=a,b       enable optional groups: files browsers media terminals shell gaming
                   flatpak bluetooth ocr ai   (--without=a,b disables them)
  --disk=<dev>     target disk for the NixOS auto-installer
  --user=<name>    initial user name (NixOS)
  --password=<p>   initial password (NixOS)

Env fallbacks:
  EDOTS_AUTO=1 EDOTS_DISK=sda EDOTS_USER=eduard EDOTS_PASSWORD=xxx $0
  EDOTS_NVIDIA=open|proprietary|none  EDOTS_NO_TWEAKS=1
EOF
      exit 0 ;;
  esac
done
[ "${EDOTS_AUTO:-0}" = "1" ]      && AUTO=1
[ -n "${EDOTS_DISK:-}" ]          && DISK_ARG="$EDOTS_DISK"
[ -n "${EDOTS_USER:-}" ]          && USER_NAME="$EDOTS_USER"
[ -n "${EDOTS_PASSWORD:-}" ]      && USER_PASS="$EDOTS_PASSWORD"
[ -n "${EDOTS_NVIDIA:-}" ]        && NVIDIA_MODE="$EDOTS_NVIDIA"
[ "${EDOTS_NO_TWEAKS:-0}" = "1" ] && TWEAKS=0

# ─────────────────────────── terminal UI ────────────────────────
UI_TTY=0; [ -t 1 ] && UI_TTY=1
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UI_UTF8=1 ;;
  *) UI_UTF8=0 ;;
esac
UI_COLS=76
if [ "$UI_TTY" = 1 ]; then
  UI_COLS=$(tput cols 2>/dev/null || echo 76)
  case "$UI_COLS" in ''|*[!0-9]*) UI_COLS=76 ;; esac
  [ "$UI_COLS" -gt 76 ] && UI_COLS=76
  [ "$UI_COLS" -lt 50 ] && UI_COLS=50
fi
if [ "$UI_TTY" = 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_MAGENTA=$'\033[35m'; C_BLUE=$'\033[34m'
  case "${TERM:-}:${COLORTERM:-}" in
    *256color*|*:truecolor|*:24bit) C_ACCENT=$'\033[38;5;141m' ;;
    *) C_ACCENT=$C_MAGENTA ;;
  esac
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_MAGENTA=''; C_BLUE=''; C_ACCENT=''
fi
if [ "$UI_UTF8" = 1 ]; then
  I_OK="✓"; I_WARN="!"; I_ERR="✗"; I_INFO="·"; I_STEP="▸"; I_ARROW="›"; I_LOGO="◆"; I_RULE="─"
  B_FULL="█"; B_EMPTY="░"
  SPIN_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
else
  I_OK="+"; I_WARN="!"; I_ERR="x"; I_INFO="-"; I_STEP=">"; I_ARROW=">"; I_LOGO="*"; I_RULE="-"
  B_FULL="#"; B_EMPTY="."
  SPIN_FRAMES=("|" "/" "-" "\\")
fi

# Everything on screen is mirrored to a log (colours/spinner frames are stripped on exit);
# a future assistant can read the log and the JSON reports back.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/edots"
mkdir -p "$STATE_DIR" 2>/dev/null || STATE_DIR="${TMPDIR:-/tmp}"
LOG_FILE="$STATE_DIR/install-$(date +%Y%m%d-%H%M%S).log"
START_TS=$SECONDS; START_ISO="$(date -Is 2>/dev/null || date)"
REPORT_ON=0; SUDO_KA_PID=""
if command -v tee >/dev/null 2>&1; then
  exec > >(tee -a "$LOG_FILE") 2>&1
  ln -sf "$LOG_FILE" "$STATE_DIR/latest.log" 2>/dev/null || true
else
  LOG_FILE=""
fi

c_info() { printf '%s%s%s %s\n' "$C_CYAN" "$I_INFO" "$C_RESET" "$*"; }
c_warn() { printf '%s%s%s %s\n' "$C_YELLOW" "$I_WARN" "$C_RESET" "$*"; }
c_err()  { printf '%s%s%s %s\n' "$C_RED" "$I_ERR" "$C_RESET" "$*"; }
c_ok()   { printf '%s%s%s %s\n' "$C_GREEN" "$I_OK" "$C_RESET" "$*"; }
c_dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

fmt_time() { printf '%dm%02ds' $(( $1 / 60 )) $(( $1 % 60 )); }
hr() {
  local i s=""
  for ((i = 0; i < UI_COLS - 2; i++)); do s+="$I_RULE"; done
  printf '%s  %s%s\n' "$C_DIM" "$s" "$C_RESET"
}
kv() { printf '  %s%-9s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"; }

FAILED=(); PKG_INSTALLED=(); PKG_PRESENT=(); PKG_SKIPPED=()
STEP_NO=0; STEP_TOTAL=0
section() {
  STEP_NO=$((STEP_NO + 1))
  local n="$STEP_NO"; [ "$STEP_TOTAL" -gt 0 ] && n="$STEP_NO/$STEP_TOTAL"
  printf '\n%s%s %s%s  %s[%s · %s]%s\n' "$C_BOLD$C_ACCENT" "$I_STEP" "$*" "$C_RESET" \
    "$C_DIM" "$n" "$(fmt_time $(( SECONDS - START_TS )))" "$C_RESET"
}

# ── progress bar + spinner ──
_bar() {  # _bar <cur> <total> <width>
  local cur="$1" tot="$2" w="${3:-22}" f e i s=""
  [ "$tot" -gt 0 ] || tot=1
  f=$(( cur * w / tot )); [ "$f" -gt "$w" ] && f=$w
  e=$(( w - f ))
  for ((i = 0; i < f; i++)); do s+="$B_FULL"; done
  for ((i = 0; i < e; i++)); do s+="$B_EMPTY"; done
  printf '%s' "$s"
}

PKG_I=0; PKG_TOTAL=0
pkg_begin() { PKG_I=0; PKG_TOTAL="${1:-0}"; }
_pkg_draw() {  # _pkg_draw <label> <frame> <secs>
  local d=$(( PKG_I - 1 )) pct=0
  [ "$d" -lt 0 ] && d=0
  [ "$PKG_TOTAL" -gt 0 ] && pct=$(( d * 100 / PKG_TOTAL ))
  printf '\r\033[K  %s%s%s %s%3d%%%s %s%d/%d%s  %-26.26s %s%s %ds%s' \
    "$C_ACCENT" "$(_bar "$d" "$PKG_TOTAL" 22)" "$C_RESET" \
    "$C_BOLD" "$pct" "$C_RESET" "$C_DIM" "$PKG_I" "$PKG_TOTAL" "$C_RESET" \
    "$1" "$C_CYAN" "$2" "${3:-0}" "$C_RESET"
}
pkg_tick() {
  PKG_I=$((PKG_I + 1))
  if [ "$UI_TTY" = 1 ] && [ "$PKG_TOTAL" -gt 0 ]; then
    _pkg_draw "$1" "${SPIN_FRAMES[0]}" 0
  else
    printf '  [%d/%d] %s\n' "$PKG_I" "$PKG_TOTAL" "$1"
  fi
}
pkg_note() { [ "$UI_TTY" = 1 ] && printf '\r\033[K'; c_warn "$*"; }
pkg_end()  { [ "$UI_TTY" = 1 ] && printf '\r\033[K'; }

# Run noisy commands into the log; the screen only shows progress.
log_cmd() {
  if [ -n "${LOG_FILE:-}" ]; then "$@" >>"$LOG_FILE" 2>&1; else "$@" >/dev/null 2>&1; fi
}

# pkg_run <label> cmd...   (after pkg_tick: animates the same progress line)
pkg_run() {
  local label="$1"; shift
  if [ "$UI_TTY" != 1 ] || [ "$DRY" = 1 ]; then log_cmd "$@"; return $?; fi
  "$@" </dev/null >>"${LOG_FILE:-/dev/null}" 2>&1 &
  local pid=$! i=0 t0=$SECONDS rc
  while kill -0 "$pid" 2>/dev/null; do
    _pkg_draw "$label" "${SPIN_FRAMES[$(( i % ${#SPIN_FRAMES[@]} ))]}" "$(( SECONDS - t0 ))"
    i=$((i + 1)); sleep 0.1
  done
  wait "$pid"; rc=$?
  return $rc
}

# run_spin <label> cmd...   (single long command with a spinner and timer)
run_spin() {
  local label="$1"; shift
  if [ "$UI_TTY" != 1 ]; then c_info "$label..."; log_cmd "$@"; return $?; fi
  if [ "$DRY" = 1 ]; then "$@"; return $?; fi
  "$@" </dev/null >>"${LOG_FILE:-/dev/null}" 2>&1 &
  local pid=$! i=0 t0=$SECONDS rc
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[K  %s%s%s %s %s%s%s' "$C_CYAN" "${SPIN_FRAMES[$(( i % ${#SPIN_FRAMES[@]} ))]}" "$C_RESET" \
      "$label" "$C_DIM" "$(fmt_time $(( SECONDS - t0 )))" "$C_RESET"
    i=$((i + 1)); sleep 0.1
  done
  wait "$pid"; rc=$?
  printf '\r\033[K'
  [ "$rc" -eq 0 ] && c_ok "$label" || c_warn "$label — failed (see log)"
  return $rc
}

# ── read from the terminal even when the script itself comes through a pipe (curl | bash) ──
# ── read from the terminal even when the script itself comes through a pipe (curl | bash) ──
rd() {  # rd "prompt" VAR
  local _p="$1" _v="$2" _a=""
  if [ -t 0 ]; then read -r -p "$_p" _a || _a=""
  elif [ -r /dev/tty ]; then read -r -p "$_p" _a </dev/tty || _a=""
  fi
  printf -v "$_v" '%s' "$_a"
}

# ── dry-run: mutating commands become no-ops that only print what they would do ──
c_dry() { printf '%s  DRY: %s%s\n' "$C_DIM" "$*" "$C_RESET"; }
if [ "$DRY" = 1 ]; then
  for _c in sudo yay paru git curl wget fc-cache systemctl npm makepkg cc mkdir mv rm cp ln chmod cargo; do
    eval "$_c() { c_dry \"$_c \$*\"; return 0; }"
  done
  c_warn "dry-run: nothing will be changed"
fi

MANUAL=()   # пакети, яких нема в репозиторіях дистрибутива — користувач ставить вручну

# ── Conflict resolution: [S]kip / [A]ppend / [O]verwrite ──
ask_conflict() {
  local path="$1" default="${2:-skip}" a
  if [ "$AUTO" = "1" ]; then echo "$default"; return; fi
  while true; do
    rd "  '$path' exists — [S]kip / [A]ppend / [O]verwrite? [S/a/o]: " a
    case "$a" in
      [Aa]*)  echo "append";    return ;;
      [Oo]*)  echo "overwrite"; return ;;
      [Ss]*|"") echo "skip";    return ;;
      *) c_warn "Enter s, a or o." ;;
    esac
  done
}

# ─────────────────────────── hardware profile ───────────────────────────
HW_ARCH=""; HW_KERNEL=""; HW_DISTRO="Linux"
HW_CPU_VENDOR=""; HW_CPU_MODEL=""; HW_CORES=1; HW_THREADS=1
HW_RAM_MB=0; HW_SWAP_MB=0
HW_DISK_KIND="unknown"; HW_DISK_FREE_GB=0; HW_DISK_TOTAL_GB=0
HW_LAPTOP=0; HW_VM=0; HW_UEFI=0
HW_GPU_NAMES=""; hw_gpu_vendors=()
MICROCODE_PKG=""; GPU_PKG_SUMMARY=""; BUILD_JOBS=1
TWEAK_ZRAM=0; TWEAK_TRIM=0; TWEAK_PPD=0; TWEAK_BT=0
TWEAK_SYSCTL=0; TWEAK_IOSCHED=0; TWEAK_THERMAL=0; TWEAK_NVIDIA=0
HW_VM_KIND=""; HW_AVX2=0; HW_VRAM_MB=0; HW_TIER="mid"; HW_EFFECTS="balanced"
HW_LLM_MODEL=""; HW_LLM_SIZE=""; HW_LLM_BUDGET_MB=0; HW_LLM_ACCEL="cpu"
HW_ZRAM_MAX_RAM_MB=16500; HW_PKGS=()

detect_hardware() {
  HW_ARCH="$(uname -m 2>/dev/null || echo unknown)"
  HW_KERNEL="$(uname -r 2>/dev/null || echo unknown)"
  HW_DISTRO="$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}" )"

  local k v
  while IFS=':' read -r k v; do
    case "$k" in
      vendor_id)    [ -z "$HW_CPU_VENDOR" ] && HW_CPU_VENDOR="${v# }" ;;
      "model name") [ -z "$HW_CPU_MODEL" ]  && HW_CPU_MODEL="${v# }" ;;
    esac
  done < /proc/cpuinfo 2>/dev/null

  HW_THREADS=$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
  case "$HW_THREADS" in ''|*[!0-9]*) HW_THREADS=1 ;; esac
  HW_CORES="$HW_THREADS"
  if command -v lscpu >/dev/null 2>&1; then
    local cores
    cores=$(lscpu -p=CORE,SOCKET 2>/dev/null | grep -v '^#' | sort -u | wc -l)
    [ "${cores:-0}" -ge 1 ] 2>/dev/null && HW_CORES="$cores"
  fi

  HW_RAM_MB=$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
  HW_SWAP_MB=$(awk '/^SwapTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
  case "$HW_RAM_MB" in ''|*[!0-9]*) HW_RAM_MB=0 ;; esac
  case "$HW_SWAP_MB" in ''|*[!0-9]*) HW_SWAP_MB=0 ;; esac

  hw_gpu_vendors=(); HW_GPU_NAMES=""
  local line
  if command -v lspci >/dev/null 2>&1; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      line="${line#*: }"
      HW_GPU_NAMES="${HW_GPU_NAMES:+$HW_GPU_NAMES · }${line}"
      case "$line" in
        *Intel*)    hw_gpu_vendors+=(intel) ;;
        *AMD*|*ATI*) hw_gpu_vendors+=(amd) ;;
        *NVIDIA*)   hw_gpu_vendors+=(nvidia) ;;
      esac
    done < <(lspci 2>/dev/null | grep -Ei 'VGA compatible|3D controller|Display controller')
  else
    local f
    for f in /sys/class/drm/card[0-9]/device/vendor; do
      [ -r "$f" ] || continue
      case "$(cat "$f" 2>/dev/null)" in
        0x8086)        hw_gpu_vendors+=(intel);  HW_GPU_NAMES="${HW_GPU_NAMES:+$HW_GPU_NAMES · }Intel" ;;
        0x1002|0x1022) hw_gpu_vendors+=(amd);    HW_GPU_NAMES="${HW_GPU_NAMES:+$HW_GPU_NAMES · }AMD" ;;
        0x10de)        hw_gpu_vendors+=(nvidia); HW_GPU_NAMES="${HW_GPU_NAMES:+$HW_GPU_NAMES · }NVIDIA" ;;
      esac
    done
  fi
  local out=() gfx
  for gfx in "${hw_gpu_vendors[@]}"; do
    case " ${out[*]} " in *" $gfx "*) ;; *) out+=("$gfx") ;; esac
  done
  hw_gpu_vendors=("${out[@]}")

  HW_LAPTOP=0
  compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1 && HW_LAPTOP=1
  if [ "$HW_LAPTOP" -eq 0 ] && [ -r /sys/class/dmi/id/chassis_type ]; then
    case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in 8|9|10|14) HW_LAPTOP=1 ;; esac
  fi

  HW_VM=0
  command -v systemd-detect-virt >/dev/null 2>&1 \
    && systemd-detect-virt --vm --quiet >/dev/null 2>&1 && HW_VM=1

  HW_VM_KIND=""
  [ "$HW_VM" -eq 1 ] && HW_VM_KIND="$(systemd-detect-virt --vm 2>/dev/null || true)"

  HW_UEFI=0; [ -d /sys/firmware/efi ] && HW_UEFI=1

  local root_src root_base rot
  root_src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  root_src="${root_src%%\[*}"
  root_base=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1 || true)
  [ -n "$root_base" ] || root_base=$(basename "${root_src:-unknown}")
  if [[ "$root_base" == nvme* ]]; then
    HW_DISK_KIND="nvme"
  elif [ -r "/sys/block/$root_base/queue/rotational" ]; then
    rot=$(cat "/sys/block/$root_base/queue/rotational" 2>/dev/null || echo 1)
    [ "$rot" = 0 ] && HW_DISK_KIND="ssd" || HW_DISK_KIND="hdd"
  fi

  HW_DISK_FREE_GB=$(df -Pk "${HOME:-/}" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024/1024}')
  HW_DISK_TOTAL_GB=$(df -Pk "${HOME:-/}" 2>/dev/null | awk 'NR==2 {printf "%d", $2/1024/1024}')
  case "$HW_DISK_FREE_GB"  in ''|*[!0-9]*) HW_DISK_FREE_GB=0 ;;  esac
  case "$HW_DISK_TOTAL_GB" in ''|*[!0-9]*) HW_DISK_TOTAL_GB=0 ;; esac

  case "$HW_CPU_VENDOR" in
    GenuineIntel) MICROCODE_PKG="intel-ucode" ;;
    AuthenticAMD) MICROCODE_PKG="amd-ucode" ;;
    *)            MICROCODE_PKG="" ;;
  esac

  BUILD_JOBS=1
  if [ "$HW_RAM_MB" -ge 1536 ]; then BUILD_JOBS=$(( HW_RAM_MB / 1536 )); fi
  [ "$BUILD_JOBS" -gt "$HW_THREADS" ] && BUILD_JOBS=$HW_THREADS
  [ "$BUILD_JOBS" -gt 16 ] && BUILD_JOBS=16
  [ "$BUILD_JOBS" -lt 1 ] && BUILD_JOBS=1

  classify_profile
}

classify_profile() {
  local f b v budget
  HW_AVX2=0; grep -qw avx2 /proc/cpuinfo 2>/dev/null && HW_AVX2=1

  HW_VRAM_MB=0
  for f in /sys/class/drm/card[0-9]/device/mem_info_vram_total; do
    [ -r "$f" ] || continue
    read -r b < "$f" 2>/dev/null || continue
    case "$b" in ''|*[!0-9]*) continue ;; esac
    v=$(( b / 1048576 ))
    [ "$v" -gt "$HW_VRAM_MB" ] && HW_VRAM_MB=$v
  done
  if command -v nvidia-smi >/dev/null 2>&1; then
    v=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -dc '0-9')
    if [ -n "$v" ] && [ "$v" -gt "$HW_VRAM_MB" ]; then HW_VRAM_MB=$v; fi
  fi

  # Tier drives UI effects in the bar and the size of the local model.
  HW_TIER="mid"
  if [ "$HW_RAM_MB" -lt 6144 ] || [ "$HW_THREADS" -lt 4 ]; then HW_TIER="low"
  elif [ "$HW_RAM_MB" -ge 15000 ] && [ "$HW_THREADS" -ge 8 ]; then HW_TIER="high"
  fi
  case "$HW_TIER" in low) HW_EFFECTS="minimal" ;; mid) HW_EFFECTS="balanced" ;; *) HW_EFFECTS="full" ;; esac

  # Local LLM sizing (Q4 quantisation): GPU memory if there is enough, else half of RAM.
  HW_LLM_ACCEL="cpu"
  if [ "$HW_VRAM_MB" -ge 3000 ]; then HW_LLM_ACCEL="gpu"; budget=$(( HW_VRAM_MB - 768 ))
  else budget=$(( HW_RAM_MB / 2 - 1024 )); fi
  [ "$budget" -lt 0 ] && budget=0
  HW_LLM_BUDGET_MB=$budget
  HW_LLM_MODEL=""; HW_LLM_SIZE=""
  if   [ "$budget" -ge 6500 ] && [ "$HW_LLM_ACCEL" = gpu ]; then HW_LLM_MODEL="qwen2.5:7b";   HW_LLM_SIZE="4.7 GB"
  elif [ "$budget" -ge 3000 ]; then HW_LLM_MODEL="qwen2.5:3b";   HW_LLM_SIZE="1.9 GB"
  elif [ "$budget" -ge 1500 ]; then HW_LLM_MODEL="qwen2.5:1.5b"; HW_LLM_SIZE="1.0 GB"
  elif [ "$budget" -ge 700 ];  then HW_LLM_MODEL="qwen2.5:0.5b"; HW_LLM_SIZE="0.4 GB"
  fi
  # CPU without AVX2 is too slow for anything above 1.5B
  if [ "$HW_LLM_ACCEL" = cpu ] && [ "$HW_AVX2" -eq 0 ]; then
    case "$HW_LLM_MODEL" in qwen2.5:3b|qwen2.5:7b) HW_LLM_MODEL="qwen2.5:1.5b"; HW_LLM_SIZE="1.0 GB" ;; esac
  fi
}

hw_machine() {
  local mem_gb=$(( (HW_RAM_MB + 512) / 1024 ))
  printf '%s' "${HW_CPU_MODEL:-unknown CPU}"
  [ -n "$HW_GPU_NAMES" ] && printf ' · %s' "$HW_GPU_NAMES"
  printf ' · %s GB RAM' "$mem_gb"
  [ "$HW_LAPTOP" -eq 1 ] && printf ' · laptop'
  [ "$HW_VM" -eq 1 ] && printf ' · VM'
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}
json_string() { printf '"%s"' "$(json_escape "${1:-}")"; }
json_array() {
  local first=1 x
  printf '['
  for x in "$@"; do
    [ -n "$x" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    first=0
    json_string "$x"
  done
  printf ']'
}
json_bool() { [ "${1:-0}" = 1 ] && printf true || printf false; }

print_hardware_text() {
  local mem_gb=$(( (HW_RAM_MB + 512) / 1024 )) swap_gb=$(( (HW_SWAP_MB + 512) / 1024 ))
  local gpu_hint="none" vram="" ai="none — not enough memory for a useful local model"
  [ "${#hw_gpu_vendors[@]}" -gt 0 ] && gpu_hint="$(IFS=,; echo "${hw_gpu_vendors[*]}")"
  [ "$HW_VRAM_MB" -gt 0 ] && vram=" · ${HW_VRAM_MB} MB VRAM"
  [ -n "$HW_LLM_MODEL" ] && ai="$HW_LLM_MODEL (~$HW_LLM_SIZE, $HW_LLM_ACCEL)"
  kv "System"  "$HW_DISTRO · $HW_KERNEL · $HW_ARCH"
  kv "CPU"     "${HW_CPU_MODEL:-unknown} · $HW_CORES cores / $HW_THREADS threads$([ "$HW_AVX2" -eq 1 ] && echo ' · AVX2')"
  kv "Memory"  "$mem_gb GB RAM · $swap_gb GB swap"
  kv "GPU"     "${HW_GPU_NAMES:-none detected}$vram"
  kv "Disk"    "$HW_DISK_KIND · $HW_DISK_FREE_GB GB free of $HW_DISK_TOTAL_GB GB"
  kv "Machine" "$([ "$HW_LAPTOP" -eq 1 ] && echo laptop || echo desktop) · $([ "$HW_UEFI" -eq 1 ] && echo UEFI || echo BIOS) · $([ "$HW_VM" -eq 1 ] && echo "virtual (${HW_VM_KIND:-vm})" || echo physical)"
  kv "Profile" "tier $HW_TIER · effects $HW_EFFECTS"
  kv "Local AI" "$ai"
  kv "Tuning"  "microcode ${MICROCODE_PKG:-unknown} · GPUs $gpu_hint · build jobs $BUILD_JOBS"
}

print_hardware_json() {
  printf '{\n'
  printf '  "schema": 2,\n'
  printf '  "generated": %s,\n' "$(json_string "$(date -Is 2>/dev/null || date)")"
  printf '  "os": {"distro": %s, "kernel": %s, "arch": %s},\n' \
    "$(json_string "$HW_DISTRO")" "$(json_string "$HW_KERNEL")" "$(json_string "$HW_ARCH")"
  printf '  "cpu": {"vendor": %s, "model": %s, "cores": %d, "threads": %d, "avx2": %s},\n' \
    "$(json_string "$HW_CPU_VENDOR")" "$(json_string "$HW_CPU_MODEL")" "$HW_CORES" "$HW_THREADS" "$(json_bool "$HW_AVX2")"
  printf '  "memory": {"total_mb": %d, "swap_mb": %d},\n' "$HW_RAM_MB" "$HW_SWAP_MB"
  printf '  "gpu": {"names": %s, "vendors": %s, "vram_mb": %d},\n' \
    "$(json_string "$HW_GPU_NAMES")" "$(json_array "${hw_gpu_vendors[@]}")" "$HW_VRAM_MB"
  printf '  "disk": {"kind": %s, "free_gb": %d, "total_gb": %d},\n' \
    "$(json_string "$HW_DISK_KIND")" "$HW_DISK_FREE_GB" "$HW_DISK_TOTAL_GB"
  printf '  "machine": {"laptop": %s, "uefi": %s, "virtual": %s, "vm_kind": %s},\n' \
    "$(json_bool "$HW_LAPTOP")" "$(json_bool "$HW_UEFI")" "$(json_bool "$HW_VM")" "$(json_string "$HW_VM_KIND")"
  printf '  "tuning": {"microcode": %s, "build_jobs": %d},\n' "$(json_string "$MICROCODE_PKG")" "$BUILD_JOBS"
  printf '  "profile": {"tier": %s, "effects": %s, "llm": {"model": %s, "size": %s, "budget_mb": %d, "accel": %s}}\n' \
    "$(json_string "$HW_TIER")" "$(json_string "$HW_EFFECTS")" "$(json_string "$HW_LLM_MODEL")" \
    "$(json_string "$HW_LLM_SIZE")" "$HW_LLM_BUDGET_MB" "$(json_string "$HW_LLM_ACCEL")"
  printf '}\n'
}

check_hardware() {
  [ "$HW_ARCH" = "x86_64" ] || c_warn "Architecture: $HW_ARCH — Edots targets x86_64; some pieces may be unavailable."
  [ "$HW_THREADS" -ge 2 ] || c_warn "CPU: $HW_THREADS thread(s) — builds will be slow (2 cores recommended)."
  if [ "$HW_RAM_MB" -lt 3800 ]; then
    c_warn "RAM: $(( (HW_RAM_MB + 512) / 1024 )) GB — 4 GB recommended; yay (Go) and matugen (Rust) build from source."
    c_warn "      Build jobs capped at $BUILD_JOBS; zram is configured unless --no-tweaks."
  elif [ "$OS" = arch ] && [ "$TWEAKS" -eq 1 ] && [ "$HW_RAM_MB" -le "$HW_ZRAM_MAX_RAM_MB" ]; then
    c_info "RAM: $(( (HW_RAM_MB + 512) / 1024 )) GB — enabling zram."
  fi
  [ "$HW_DISK_FREE_GB" -ge 25 ] \
    || c_warn "Disk: ${HW_DISK_FREE_GB} GB free in ${HOME} — 30 GB recommended (packages, AUR builds, wallpapers)."
  export MAKEFLAGS="${MAKEFLAGS:--j$BUILD_JOBS}"
  export NINJAFLAGS="${NINJAFLAGS:--j$BUILD_JOBS}"
  export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$BUILD_JOBS}"
  c_info "Build jobs: $BUILD_JOBS (${HW_THREADS} threads, $(( (HW_RAM_MB + 512) / 1024 )) GB RAM)."
}

banner() {
  local mode="interactive" ai="local model: none fits"
  [ "$AUTO" -eq 1 ] && mode="auto"
  [ "$DRY" -eq 1 ] && mode="$mode · dry-run"
  [ "$MINIMAL" -eq 1 ] && mode="$mode · minimal"
  [ -n "$HW_LLM_MODEL" ] && ai="local model: $HW_LLM_MODEL"
  printf '\n  %s%s Edots%s %sinstaller%s\n' "$C_BOLD$C_ACCENT" "$I_LOGO" "$C_RESET" "$C_DIM" "$C_RESET"
  hr
  kv "System"  "$HW_DISTRO · $HW_KERNEL · $HW_ARCH"
  kv "Machine" "$(hw_machine)"
  kv "Profile" "tier $HW_TIER · effects $HW_EFFECTS · $ai"
  kv "Mode"    "$mode"
  [ -n "${LOG_FILE:-}" ] && kv "Log" "$LOG_FILE"
  hr
  echo
}

plan_item() { printf '  %s%s%s %-8s %s\n' "$C_ACCENT" "$I_INFO" "$C_RESET" "$1" "$2"; }
print_plan() {
  local cpu="${MICROCODE_PKG:-no microcode package}" mem disk
  [ "$HW_LAPTOP" -eq 1 ] && [ "$HW_CPU_VENDOR" = GenuineIntel ] && [ "$HW_VM" -eq 0 ] && cpu="$cpu + thermald"
  printf '  %sTuned for this machine%s\n' "$C_BOLD" "$C_RESET"
  plan_item "CPU" "$cpu"
  plan_item "GPU" "$GPU_PKG_SUMMARY"
  if [ "$TWEAKS" -ne 1 ]; then
    plan_item "Tuning" "disabled (--no-tweaks)"
  else
    if [ "$HW_RAM_MB" -le "$HW_ZRAM_MAX_RAM_MB" ]; then mem="zram (zstd) · swappiness 150"
    else mem="$(( (HW_RAM_MB + 512) / 1024 )) GB — no zram needed · swappiness 10"; fi
    plan_item "Memory" "$mem"
    if [ "$HW_VM" -eq 1 ]; then disk="virtual disk — scheduler untouched"
    else
      case "$HW_DISK_KIND" in
        nvme) disk="NVMe · scheduler none · periodic TRIM" ;;
        ssd)  disk="SSD · mq-deadline · periodic TRIM" ;;
        hdd)  disk="HDD · bfq scheduler" ;;
        *)    disk="scheduler rules per device type" ;;
      esac
    fi
    plan_item "Disk" "$disk"
    [ "$HW_VM" -eq 0 ] && plan_item "Power" "power-profiles-daemon$([ "$HW_LAPTOP" -eq 1 ] && echo ' (laptop)')"
    [ "$HW_VM" -eq 1 ] && plan_item "Guest" "${HW_VM_KIND:-vm} guest tools"
    case " ${hw_gpu_vendors[*]} " in *" nvidia "*) [ "$NVIDIA_MODE" != none ] && plan_item "NVIDIA" "Wayland modeset + suspend/resume services" ;; esac
  fi
  plan_item "Build" "-j$BUILD_JOBS for makepkg / cargo"
  echo
}

resolve_nvidia() {
  case " ${hw_gpu_vendors[*]} " in
    *" nvidia "*) ;;
    *) [ "$NVIDIA_MODE" = auto ] && NVIDIA_MODE=none; return 0 ;;
  esac
  case "$NVIDIA_MODE" in
    open|proprietary|none) ;;
    *) c_warn "Unknown --nvidia=$NVIDIA_MODE — using auto."; NVIDIA_MODE=auto ;;
  esac
  [ "$NVIDIA_MODE" = none ] && { c_info "NVIDIA: driver install skipped."; return 0; }
  if [ "$NVIDIA_MODE" = auto ]; then
    if [ "$AUTO" -eq 1 ] || [ "$UI_TTY" -ne 1 ]; then
      NVIDIA_MODE=open
      c_warn "NVIDIA: installing nvidia-open-dkms (Turing or newer)."
      c_warn "         Older cards: --nvidia=proprietary; skip: --nvidia=none."
    else
      local a
      rd "NVIDIA GPU detected — driver [O]pen (Turing+) / [P]roprietary / [S]kip? [O/p/s]: " a
      case "$a" in
        [Pp]*) NVIDIA_MODE=proprietary ;;
        [Ss]*) NVIDIA_MODE=none ;;
        *)     NVIDIA_MODE=open ;;
      esac
    fi
  fi
  [ "$NVIDIA_MODE" = open ]        && c_info "NVIDIA: open kernel modules + userspace."
  [ "$NVIDIA_MODE" = proprietary ] && c_info "NVIDIA: proprietary kernel modules + userspace."
}

choose_hw_pkgs() {
  HW_PKGS=()
  [ -n "$MICROCODE_PKG" ] && [ "$HW_VM" -eq 0 ] && HW_PKGS+=("$MICROCODE_PKG")
  HW_PKGS+=(mesa vulkan-icd-loader)
  GPU_PKG_SUMMARY="mesa"
  local v dkms=0
  for v in "${hw_gpu_vendors[@]}"; do
    case "$v" in
      intel)
        HW_PKGS+=(vulkan-intel intel-media-driver libva-intel-driver)
        GPU_PKG_SUMMARY="$GPU_PKG_SUMMARY+vulkan-intel"
        ;;
      amd)
        HW_PKGS+=(vulkan-radeon libva-mesa-driver)
        GPU_PKG_SUMMARY="$GPU_PKG_SUMMARY+vulkan-radeon"
        ;;
      nvidia)
        case "$NVIDIA_MODE" in
          open)        HW_PKGS+=(nvidia-open-dkms nvidia-utils); dkms=1 ;;
          proprietary) HW_PKGS+=(nvidia-dkms nvidia-utils);      dkms=1 ;;
        esac
        GPU_PKG_SUMMARY="$GPU_PKG_SUMMARY+nvidia-$NVIDIA_MODE"
        ;;
    esac
  done
  if [ "$dkms" -eq 1 ]; then
    local kpkg
    kpkg=$(pacman -Qoq "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -1 || true)
    [ -n "$kpkg" ] && HW_PKGS+=("${kpkg}-headers") || HW_PKGS+=(linux-headers)
  fi
  # hybrid graphics (iGPU + dGPU): per-app GPU switching
  [ "${#hw_gpu_vendors[@]}" -ge 2 ] && [ "$HW_VM" -eq 0 ] && HW_PKGS+=(switcheroo-control)
  # virtual machines: guest integration instead of laptop/power bits
  if [ "$HW_VM" -eq 1 ]; then
    case "$HW_VM_KIND" in
      kvm|qemu) HW_PKGS+=(qemu-guest-agent spice-vdagent) ;;
      oracle)   HW_PKGS+=(virtualbox-guest-utils) ;;
      vmware)   HW_PKGS+=(open-vm-tools) ;;
    esac
  fi
  if [ "$HW_LAPTOP" -eq 1 ]; then
    HW_PKGS+=(sof-firmware alsa-ucm-conf)
    [ "$HW_CPU_VENDOR" = GenuineIntel ] && [ "$HW_VM" -eq 0 ] && HW_PKGS+=(thermald)
  fi
  [ "$HW_RAM_MB" -le "$HW_ZRAM_MAX_RAM_MB" ] && [ "$TWEAKS" -eq 1 ] && HW_PKGS+=(zram-generator)
  command -v lspci >/dev/null 2>&1 || HW_PKGS+=(pciutils)

  local out=() p
  for p in "${HW_PKGS[@]}"; do
    case " ${out[*]} " in *" $p "*) ;; *) out+=("$p") ;; esac
  done
  HW_PKGS=("${out[@]}")
}

setup_tuning() {
  section "System tuning"
  if [ "$TWEAKS" -ne 1 ]; then c_info "Skipped (--no-tweaks)."; return 0; fi

  # ── memory: zram for machines up to ~16 GB, then matching sysctl ──
  if swapon --show=NAME --noheadings 2>/dev/null | grep -q 'zram'; then
    TWEAK_ZRAM=1; c_ok "zram swap already active"
  elif [ "$HW_RAM_MB" -le "$HW_ZRAM_MAX_RAM_MB" ]; then
    if [ -f /etc/systemd/zram-generator.conf ]; then
      c_info "zram config already exists — leaving it untouched"
    elif ! pacman -Qi zram-generator >/dev/null 2>&1 && [ "$DRY" != 1 ]; then
      c_warn "zram-generator not installed — zram skipped"
    elif [ "$DRY" = 1 ]; then
      c_dry "write /etc/systemd/zram-generator.conf and start zram0"
      TWEAK_ZRAM=1
    else
      sudo mkdir -p /etc/systemd
      printf '[zram0]\nzram-size = min(ram / 2, 8192)\ncompression-algorithm = zstd\n' \
        | sudo tee /etc/systemd/zram-generator.conf >/dev/null
      sudo systemctl daemon-reload
      if sudo systemctl start systemd-zram-setup@zram0.service 2>/dev/null \
         && swapon --show=NAME --noheadings 2>/dev/null | grep -q 'zram'; then
        TWEAK_ZRAM=1; c_ok "zram swap enabled (up to 8 GB, zstd)"
      else
        c_warn "zram config written, but zram0 did not start — reboot to activate"
      fi
    fi
  fi
  local swp=10 sysctl_conf
  [ "$TWEAK_ZRAM" = 1 ] && swp=150
  sysctl_conf="# Managed by Edots — memory tuning (tier: $HW_TIER)"$'\n'"vm.swappiness = $swp"$'\n'"vm.vfs_cache_pressure = 50"
  [ "$TWEAK_ZRAM" = 1 ] && sysctl_conf+=$'\n'"vm.page-cluster = 0"
  if write_sys_file /etc/sysctl.d/99-edots.conf "$sysctl_conf" "sysctl: swappiness $swp"; then
    TWEAK_SYSCTL=1; log_cmd sudo sysctl -p /etc/sysctl.d/99-edots.conf
  fi

  # ── disk: I/O scheduler per device type + periodic TRIM ──
  if [ "$HW_VM" -eq 0 ]; then
    local rules
    rules='# Managed by Edots — I/O scheduler per device type
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"'
    if write_sys_file /etc/udev/rules.d/60-edots-ioscheduler.rules "$rules" "I/O scheduler rules"; then
      TWEAK_IOSCHED=1
      log_cmd sudo udevadm control --reload
      log_cmd sudo udevadm trigger --subsystem-match=block --action=change
    fi
  fi
  if [ "$HW_DISK_KIND" = "ssd" ] || [ "$HW_DISK_KIND" = "nvme" ]; then
    enable_unit fstrim.timer && TWEAK_TRIM=1
  fi
  enable_unit paccache.timer "paccache.timer (package cache cleanup)" || true

  # ── power: tlp wins if the user already has it; skipped in VMs ──
  if [ "$HW_VM" -eq 1 ]; then
    c_info "Virtual machine — power management skipped"
  elif pacman -Qi tlp >/dev/null 2>&1; then
    c_info "tlp is installed — leaving power management to it"
  else
    enable_unit power-profiles-daemon.service && TWEAK_PPD=1
  fi
  if pacman -Qi thermald >/dev/null 2>&1; then
    enable_unit thermald.service && TWEAK_THERMAL=1
  fi

  # ── bluetooth only when the machine actually has an adapter ──
  if [ -d /sys/class/bluetooth/hci0 ]; then
    enable_unit bluetooth.service && TWEAK_BT=1
  else
    c_info "No Bluetooth adapter — service left alone"
  fi

  # ── hybrid graphics / VM guest services ──
  pacman -Qi switcheroo-control >/dev/null 2>&1 && enable_unit switcheroo-control.service
  if [ "$HW_VM" -eq 1 ]; then
    local u
    for u in qemu-guest-agent.service spice-vdagentd.service vboxservice.service vmtoolsd.service; do
      if [ "$DRY" = 1 ] || systemctl list-unit-files --no-legend "$u" 2>/dev/null | grep -q "$u"; then
        enable_unit "$u" || true
      fi
    done
  fi

  # ── NVIDIA: Wayland modeset + suspend/resume hooks ──
  if [ "$NVIDIA_MODE" != "none" ]; then
    local nv_conf u
    nv_conf='# Managed by Edots — NVIDIA on Wayland
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1'
    if write_sys_file /etc/modprobe.d/nvidia-edots.conf "$nv_conf" "NVIDIA modprobe options (reboot to apply)"; then
      TWEAK_NVIDIA=1
    fi
    for u in nvidia-suspend nvidia-resume nvidia-hibernate; do
      if systemctl list-unit-files --no-legend "$u.service" 2>/dev/null | grep -q "$u.service"; then
        log_cmd sudo systemctl enable "$u.service" && c_ok "$u.service enabled"
      fi
    done
  fi

  # ── microcode needs to be in the initrd; the package only drops the image ──
  if [ -n "$MICROCODE_PKG" ] && [ "$HW_VM" -eq 0 ] && [ -f "/boot/${MICROCODE_PKG}.img" ]; then
    c_ok "microcode image present: /boot/${MICROCODE_PKG}.img"
  elif [ -n "$MICROCODE_PKG" ] && [ "$HW_VM" -eq 0 ] && pacman -Qi "$MICROCODE_PKG" >/dev/null 2>&1; then
    c_warn "$MICROCODE_PKG installed but /boot/${MICROCODE_PKG}.img is missing — check the bootloader initrd"
  fi
}

# ───────────────────── sudo keep-alive (long AUR builds outlive the sudo timestamp) ─────────────────────
sudo_keepalive() {
  [ "$DRY" = 1 ] && return 0
  sudo -v || { c_err "sudo is required."; exit 1; }
  ( while true; do sudo -n true 2>/dev/null; sleep 45; kill -0 "$$" 2>/dev/null || exit 0; done ) &
  SUDO_KA_PID=$!
}

# ───────────────────── optional component groups ─────────────────────
GRP_KEYS=(files browsers media terminals shell gaming flatpak bluetooth ocr ai)
GRP_NAME=("File managers" "Browsers" "Media" "Extra terminals" "Shell extras" "Gaming" "Flatpak" "Bluetooth GUI" "OCR languages" "AI helper")
GRP_DESC=("Nautilus, Dolphin" "Firefox, Zen" "VLC + codecs" "Alacritty, Ghostty" "starship, figlet, tree" "gamemode" "Flatpak runtime" "Blueman" "Ukrainian + Russian" "Ollama + local model")
GRP_SEL=()

init_groups() {
  local i k
  for i in "${!GRP_KEYS[@]}"; do
    k="${GRP_KEYS[$i]}"
    case "$k" in
      ai)        GRP_SEL[$i]=0; GRP_DESC[$i]="Ollama + ${HW_LLM_MODEL:-(no model fits this PC)}" ;;
      bluetooth) if [ -d /sys/class/bluetooth/hci0 ]; then GRP_SEL[$i]=1; else GRP_SEL[$i]=0; fi ;;
      *)         GRP_SEL[$i]=1 ;;
    esac
    [ "$MINIMAL" = 1 ] && GRP_SEL[$i]=0
    case ",$WITH_LIST," in *",$k,"*) GRP_SEL[$i]=1 ;; esac
    case ",$WITHOUT_LIST," in *",$k,"*) GRP_SEL[$i]=0 ;; esac
  done
}
group_on() {
  local i
  for i in "${!GRP_KEYS[@]}"; do
    [ "${GRP_KEYS[$i]}" = "$1" ] && [ "${GRP_SEL[$i]}" = 1 ] && return 0
  done
  return 1
}
grp_pacman() {
  case "$1" in
    files)     echo "nautilus dolphin kdialog" ;;
    browsers)  echo "firefox" ;;
    media)     echo "vlc vlc-plugins-all" ;;
    terminals) echo "alacritty ghostty" ;;
    shell)     echo "starship figlet tree" ;;
    gaming)    echo "gamemode" ;;
    flatpak)   echo "flatpak" ;;
    bluetooth) echo "blueman" ;;
    ai)
      printf 'python-psutil python-requests ollama'
      case "$NVIDIA_MODE" in open|proprietary) printf ' ollama-cuda' ;; esac
      echo ;;
  esac
}
grp_aur() {
  case "$1" in
    browsers) echo "zen-browser-bin" ;;
    ocr)      echo "tesseract-data-ukr tesseract-data-rus" ;;
  esac
}

# Interactive checklist: ↑/↓ move, space toggle, a/n all/none, enter confirm.
pick_groups() {
  [ "$UI_TTY" = 1 ] && [ -r /dev/tty ] || return 0
  local n=${#GRP_KEYS[@]} cur=0 i key frame line mark pre nm
  printf '\n  %sOptional components%s\n  %s↑/↓ move · space toggle · a all · n none · enter confirm%s\n\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET" >/dev/tty
  trap 'printf "\033[?25h" >/dev/tty; exit 130' INT
  printf '\033[?25l' >/dev/tty
  while true; do
    frame=""
    for ((i = 0; i < n; i++)); do
      if [ "${GRP_SEL[$i]}" = 1 ]; then mark="${C_GREEN}[${I_OK}]${C_RESET}"; else mark="${C_DIM}[ ]${C_RESET}"; fi
      if [ "$i" -eq "$cur" ]; then pre="${C_ACCENT}${I_ARROW}${C_RESET}"; nm="$C_BOLD"; else pre=" "; nm=""; fi
      printf -v line '\r\033[K  %s %s %s%-15s%s %s%-.38s%s\n' "$pre" "$mark" "$nm" "${GRP_NAME[$i]}" "$C_RESET" "$C_DIM" "${GRP_DESC[$i]}" "$C_RESET"
      frame+="$line"
    done
    printf '%s' "$frame" >/dev/tty
    IFS= read -rsn1 key </dev/tty || break
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 -t 0.1 key </dev/tty || key=""
        case "$key" in
          '[A') cur=$(( (cur - 1 + n) % n )) ;;
          '[B') cur=$(( (cur + 1) % n )) ;;
        esac ;;
      k) cur=$(( (cur - 1 + n) % n )) ;;
      j) cur=$(( (cur + 1) % n )) ;;
      ' ') if [ "${GRP_SEL[$cur]}" = 1 ]; then GRP_SEL[$cur]=0; else GRP_SEL[$cur]=1; fi ;;
      a|A) for ((i = 0; i < n; i++)); do GRP_SEL[$i]=1; done ;;
      n|N) for ((i = 0; i < n; i++)); do GRP_SEL[$i]=0; done ;;
      ''|q) break ;;
    esac
    printf '\033[%dA' "$n" >/dev/tty
  done
  printf '\033[?25h\n' >/dev/tty
  trap - INT
}

# ───────────────────── privileged file / unit helpers ─────────────────────
# write_sys_file <path> <content> <label> — idempotent; never touches files that are not ours.
write_sys_file() {
  local path="$1" content="$2" label="${3:-$1}"
  if [ "$DRY" = 1 ]; then c_dry "write $path"; return 0; fi
  if [ -f "$path" ] && [ "$(cat "$path" 2>/dev/null)" = "$content" ]; then
    c_ok "$label already set"; return 0
  fi
  if [ -e "$path" ] && ! grep -q 'Managed by Edots' "$path" 2>/dev/null; then
    c_info "$path exists and is not ours — left untouched"; return 1
  fi
  if printf '%s\n' "$content" | sudo tee "$path" >/dev/null 2>&1; then
    c_ok "$label"; return 0
  fi
  c_warn "could not write $path"; return 1
}

# enable_unit <unit> [label]
enable_unit() {
  local u="$1" l="${2:-$1}"
  if [ "$DRY" = 1 ]; then c_dry "enable $u"; return 0; fi
  if systemctl is-enabled --quiet "$u" 2>/dev/null && systemctl is-active --quiet "$u" 2>/dev/null; then
    c_ok "$l already active"; return 0
  fi
  if log_cmd sudo systemctl enable --now "$u"; then c_ok "$l enabled"; return 0; fi
  c_warn "$l did not start"; return 1
}

tune_pacman() {
  [ "$TWEAKS" -eq 1 ] || return 0
  local changed=0
  if grep -qE '^#ParallelDownloads' /etc/pacman.conf 2>/dev/null; then
    sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf; changed=1
  fi
  if grep -qE '^#Color$' /etc/pacman.conf 2>/dev/null; then
    sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf; changed=1
  fi
  [ "$changed" = 1 ] && c_ok "pacman.conf: parallel downloads + colour"
  return 0
}

# ───────────────────── hardware profile for the bar assistant ─────────────────────
write_hw_profile() {
  if [ "$DRY" = 1 ]; then c_dry "write $STATE_DIR/hardware.json"; return 0; fi
  classify_profile   # re-read VRAM etc.: the GPU driver may have just been installed
  if print_hardware_json > "$STATE_DIR/hardware.json" 2>/dev/null; then
    c_ok "hardware profile: $STATE_DIR/hardware.json (tier $HW_TIER)"
  else
    c_warn "could not write hardware.json"
  fi
}

write_report() {
  [ "$DRY" = 1 ] && return 0
  local f="$STATE_DIR/install-report.json" i g_on=() g_off=()
  for i in "${!GRP_KEYS[@]}"; do
    if [ "${GRP_SEL[$i]:-0}" = 1 ]; then g_on+=("${GRP_KEYS[$i]}"); else g_off+=("${GRP_KEYS[$i]}"); fi
  done
  {
    printf '{\n  "schema": 1,\n'
    printf '  "started": %s,\n'  "$(json_string "$START_ISO")"
    printf '  "finished": %s,\n' "$(json_string "$(date -Is 2>/dev/null || date)")"
    printf '  "duration_s": %d,\n' "$(( SECONDS - START_TS ))"
    printf '  "os": %s,\n' "$(json_string "$OS")"
    printf '  "mode": {"auto": %s, "minimal": %s, "no_deps": %s, "tweaks": %s, "nvidia": %s},\n' \
      "$(json_bool "$AUTO")" "$(json_bool "$MINIMAL")" "$(json_bool "$NODEPS")" "$(json_bool "$TWEAKS")" "$(json_string "$NVIDIA_MODE")"
    printf '  "groups": {"enabled": %s, "disabled": %s},\n' "$(json_array "${g_on[@]}")" "$(json_array "${g_off[@]}")"
    printf '  "packages": {"installed": %s, "present": %s, "skipped": %s},\n' \
      "$(json_array "${PKG_INSTALLED[@]}")" "$(json_array "${PKG_PRESENT[@]}")" "$(json_array "${PKG_SKIPPED[@]}")"
    printf '  "failed": %s,\n' "$(json_array "${FAILED[@]}")"
    printf '  "tweaks": {"zram": %s, "fstrim": %s, "power_profiles": %s, "bluetooth": %s, "sysctl": %s, "io_scheduler": %s, "thermald": %s, "nvidia_modprobe": %s},\n' \
      "$(json_bool "$TWEAK_ZRAM")" "$(json_bool "$TWEAK_TRIM")" "$(json_bool "$TWEAK_PPD")" "$(json_bool "$TWEAK_BT")" \
      "$(json_bool "$TWEAK_SYSCTL")" "$(json_bool "$TWEAK_IOSCHED")" "$(json_bool "$TWEAK_THERMAL")" "$(json_bool "$TWEAK_NVIDIA")"
    printf '  "paths": {"log": %s, "hardware": %s, "repo": %s},\n' \
      "$(json_string "${LOG_FILE:-}")" "$(json_string "$STATE_DIR/hardware.json")" "$(json_string "$REPO_DIR")"
    printf '  "hardware": '
    print_hardware_json
    printf '}\n'
  } > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
}

on_exit() {
  [ -n "${SUDO_KA_PID:-}" ] && kill "$SUDO_KA_PID" 2>/dev/null
  [ "$UI_TTY" = 1 ] && printf '\033[?25h' >/dev/tty 2>/dev/null
  [ "${REPORT_ON:-0}" = 1 ] && write_report
  if [ -n "${LOG_FILE:-}" ] && [ -f "$LOG_FILE" ]; then
    exec >&- 2>&-
    sleep 0.3
    sed -i -E 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/.*\r//' "$LOG_FILE" 2>/dev/null
  fi
}
trap on_exit EXIT

# ───────────────────── AI helper (local model for the bar assistant) ─────────────────────
setup_ai() {
  group_on ai || return 0
  section "AI helper (local model)"
  if [ -z "$HW_LLM_MODEL" ]; then
    c_warn "Not enough memory for a useful local model ($(( (HW_RAM_MB + 512) / 1024 )) GB RAM, no GPU memory)."
    c_info "The assistant can still run rule-based, or call a remote API."
    return 0
  fi
  if [ "$DRY" != 1 ] && ! command -v ollama >/dev/null 2>&1; then
    c_warn "ollama is not installed — install it, then: ollama pull $HW_LLM_MODEL"
    FAILED+=("ai:ollama"); return 0
  fi
  enable_unit ollama.service "ollama.service" || FAILED+=("systemd:ollama")
  c_info "Recommended model for this machine: $HW_LLM_MODEL (~$HW_LLM_SIZE, runs on $HW_LLM_ACCEL)"
  local ans="n"
  if [ "$AUTO" -ne 1 ] && [ "$DRY" != 1 ]; then rd "Download $HW_LLM_MODEL now? [y/N]: " ans; fi
  case "${ans:-n}" in
    [Yy]*)
      sleep 2
      if run_spin "ollama pull $HW_LLM_MODEL" ollama pull "$HW_LLM_MODEL"; then :; else FAILED+=("ai:model"); fi ;;
    *) c_info "Later: ollama pull $HW_LLM_MODEL" ;;
  esac
  c_info "Assistant context: $STATE_DIR/hardware.json · install-report.json · latest.log"
}

# ───────────────────── login shell ─────────────────────
ensure_fish_shell() {
  [ "$DRY" = 1 ] && return 0
  command -v fish >/dev/null 2>&1 || return 0
  local fb; fb=$(command -v fish)

  if [ "$(id -u)" = 0 ]; then
    c_warn "running as root — leaving the login shell alone (use a normal user)"
    return 0
  fi
  if [ "${SHELL##*/}" = "fish" ]; then
    c_ok "fish is already the login shell"
    return 0
  fi

  # chsh refuses a shell that is not listed in /etc/shells
  grep -qxF "$fb" /etc/shells 2>/dev/null \
    || echo "$fb" | sudo tee -a /etc/shells >/dev/null 2>&1

  if sudo chsh -s "$fb" "$USER" >/dev/null 2>&1 || chsh -s "$fb" >/dev/null 2>&1; then
    c_ok "fish set as the login shell (takes effect after relogin)"
  else
    c_warn "could not set fish as the login shell — run: chsh -s $fb"
    FAILED+=("shell:fish")
  fi
}

# ───────────────────── OS detection ─────────────────────
detect_os() {
  local id="" like=""
  if [ -r /etc/os-release ]; then
    id="$(. /etc/os-release; echo "${ID:-}")"; like="$(. /etc/os-release; echo "${ID_LIKE:-}")"
  fi
  local all=" $id $like "
  if   [ "$id" = nixos ]; then echo nixos
  elif command -v pacman >/dev/null 2>&1 || [[ "$all" == *" arch "* ]]; then echo arch
  elif [[ "$all" == *" debian "* || "$all" == *" ubuntu "* ]]; then echo debian
  elif [[ "$all" == *" fedora "* || "$all" == *" rhel "* ]]; then echo fedora
  elif [[ "$all" == *" suse "* || "$all" == *" opensuse "* ]]; then echo suse
  elif [[ "$all" == *" gentoo "* ]]; then echo gentoo
  else echo unknown
  fi
}
OS="$(detect_os)"

if [ "$EUID" -eq 0 ]; then
  c_err "Do not run as root — the script will ask for sudo when it needs it."
  exit 1
fi


# ───────────────────── --restore ─────────────────────
do_restore() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" last name dst
  [ -x "$REPO_DIR/sync.sh" ] || { c_err "sync.sh not found in $REPO_DIR — nothing to unlink."; return 1; }
  last="$(ls -d "$HOME"/.config-backup-* 2>/dev/null | sort | tail -1)"
  c_info "Will remove our symlinks (sync.sh unlink)${last:+ and move back files from $last}."
  if [ "$AUTO" = 1 ]; then ans=y; else rd "Continue? [y/N]: " ans; fi
  case "${ans:-n}" in [Yy]*) ;; *) c_info "Cancelled."; return 0 ;; esac
  "$REPO_DIR/sync.sh" unlink
  [ -n "$last" ] || { c_warn "No ~/.config-backup-* found — nothing to restore."; return 0; }
  for p in "$last"/* "$last"/.[!.]*; do
    [ -e "$p" ] || continue
    name="$(basename "$p")"
    case "$name" in
      edots)                  dst="$HOME/edots" ;;
      Wallpapers)             dst="$HOME/Pictures/Wallpapers" ;;
      upkg|utimer|gtk-reload) dst="/usr/local/bin/$name" ;;
      *)                      dst="$cfg/$name" ;;
    esac
    if [ -e "$dst" ] || [ -L "$dst" ]; then c_warn "skip $name — $dst already exists"; continue; fi
    case "$dst" in
      /usr/*) sudo mv "$p" "$dst" ;;
      *) mkdir -p "$(dirname "$dst")"; mv "$p" "$dst" ;;
    esac && c_ok "restored $dst"
  done
}

[ "$RESTORE" = 1 ] && { do_restore; exit $?; }

# ───────────────────── hardware, plan and wallpaper ─────────────────────
detect_hardware

if [ "$SHOW_HW" = 1 ]; then
  if [ "$JSON_OUT" = 1 ]; then print_hardware_json; else print_hardware_text; fi
  exit 0
fi

resolve_nvidia
init_groups
banner
check_hardware
if [ "$OS" = arch ]; then choose_hw_pkgs; print_plan; fi

if [ "$AUTO" -eq 0 ] && [ "$UI_TTY" -eq 1 ]; then
  if [ "$OS" = arch ] && [ "$NODEPS" -eq 0 ]; then pick_groups; fi
  rd "Continue? [Y/n]: " _go
  case "${_go:-y}" in
    [Nn]*) c_info "Cancelled."; exit 0 ;;
  esac
  echo
fi

REPORT_ON=1
case "$OS" in
  arch) if [ "$NODEPS" = 1 ]; then STEP_TOTAL=3; else STEP_TOTAL=9; group_on ai && STEP_TOTAL=10; fi ;;
  debian|fedora|suse|gentoo) if [ "$NODEPS" = 1 ]; then STEP_TOTAL=3; else STEP_TOTAL=5; fi ;;
  *) STEP_TOTAL=0 ;;
esac

# ───────────────────── wallpapers (shared across OSes) ─────────────────────
WALLPAPERS_REPO="https://github.com/Edgit13/Rice-Wallpapers.git"
WALLPAPERS_DIR="$HOME/Pictures/Wallpapers"

section "Wallpapers"
echo "Wallpapers live in a separate repo: $WALLPAPERS_REPO"
echo "If you agree, they will be cloned to: $WALLPAPERS_DIR"
if [ "$AUTO" = "1" ]; then wp_answer="y"; else
  rd "Install wallpapers? [y/N]: " wp_answer
fi
case "$wp_answer" in
  [Yy]*)
    if [ -d "$WALLPAPERS_DIR/.git" ]; then
      c_info "Wallpaper repo exists — pulling..."
      if git -C "$WALLPAPERS_DIR" pull --ff-only; then c_ok "wallpapers updated"
      else c_warn "git pull failed"; FAILED+=("wallpapers:pull"); fi
    elif [ -e "$WALLPAPERS_DIR" ]; then
      action=$(ask_conflict "$WALLPAPERS_DIR" skip)
      case "$action" in
        overwrite)
          wp_backup="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
          mkdir -p "$wp_backup"
          mv "$WALLPAPERS_DIR" "$wp_backup/Wallpapers"
          c_warn "old wallpapers moved to $wp_backup/Wallpapers"
          mkdir -p "$(dirname "$WALLPAPERS_DIR")"
          git clone "$WALLPAPERS_REPO" "$WALLPAPERS_DIR" && c_ok "wallpapers cloned" \
            || { c_warn "git clone failed"; FAILED+=("wallpapers:clone"); }
          ;;
        append)
          wp_tmp=$(mktemp -d)
          if git clone "$WALLPAPERS_REPO" "$wp_tmp/Wallpapers" 2>/dev/null; then
            cp -rn "$wp_tmp/Wallpapers/." "$WALLPAPERS_DIR/" && c_ok "added new files"
          else
            c_warn "git clone failed"; FAILED+=("wallpapers:clone")
          fi
          rm -rf "$wp_tmp"
          ;;
        *) c_info "Wallpapers skipped." ;;
      esac
    else
      mkdir -p "$(dirname "$WALLPAPERS_DIR")"
      c_info "Cloning wallpapers..."
      if git clone "$WALLPAPERS_REPO" "$WALLPAPERS_DIR"; then c_ok "wallpapers cloned"
      else c_warn "git clone failed"; FAILED+=("wallpapers:clone"); fi
    fi
    ;;
  *) c_info "Skipping wallpapers (later: git clone $WALLPAPERS_REPO $WALLPAPERS_DIR)." ;;
esac

# ───────────────────── repo clone ─────────────────────
section "Repository"
if [ -d "$REPO_DIR/.git" ]; then
  c_info "Repo already exists at $REPO_DIR — skipping clone."
elif [ -d "$REPO_DIR" ]; then
  action=$(ask_conflict "$REPO_DIR" skip)
  case "$action" in
    overwrite)
      repo_backup="$REPO_DIR.bak-$(date +%Y%m%d-%H%M%S)"
      mv "$REPO_DIR" "$repo_backup"
      c_warn "old $REPO_DIR moved to $repo_backup"
      git clone "$REPO_URL" "$REPO_DIR" || { c_err "git clone failed"; exit 1; }
      ;;
    append)
      c_info "Using existing $REPO_DIR as-is."
      ;;
    *)
      c_err "Clone skipped — cannot continue without the repo."
      exit 1
      ;;
  esac
else
  c_info "Cloning into $REPO_DIR..."
  git clone "$REPO_URL" "$REPO_DIR" || { c_err "git clone failed"; exit 1; }
fi
cd "$REPO_DIR" || exit 1

# Generate nix/local-user.nix (user + groups + Home-Manager)
write_lunix() {
  cat > "$REPO_DIR/nix/local-user.nix" <<EOF
{ osConfig, lib, ... }:
{
  users.users.$USER_NAME = {
    isNormalUser = lib.mkDefault true;
    initialPassword = lib.mkDefault "$USER_PASS";   # RUN `passwd` AFTER FIRST LOGIN
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "input" ];
  };

  home-manager.users.$USER_NAME = {
    imports = [ ./home.nix ];
    edots.home.enable = true;
    home.stateVersion = lib.mkDefault osConfig.system.stateVersion;
  };
}
EOF
}

# ════════════════════════ NIXOS ════════════════════════
nixos_auto_install() {
  echo
  c_warn "AUTO-INSTALL: the chosen disk will be WIPED (GPT: 1G ESP + ext4 root)."

  if [ ! -d /sys/firmware/efi ]; then
    c_err "BIOS boot detected. Auto mode only supports UEFI."
    c_err "For GRUB/BIOS — do the manual install (steps below)."
    return 1
  fi

  echo
  echo "Available disks:"
  lsblk -d -e 7,11 -o NAME,SIZE,MODEL | awk 'NR==1{print "  "$0; next}{print "  /dev/"$1"  "$2"  "$3}'
  echo
  if [ -n "$DISK_ARG" ]; then
    DISK="$DISK_ARG"
  elif [ "$AUTO" = "1" ]; then
    mapfile -t CAND < <(lsblk -d -n -e 7,11 -o NAME)
    if [ "${#CAND[@]}" -eq 1 ]; then
      c_warn "AUTO: single disk ${CAND[0]} chosen — WIPING in 5s (Ctrl+C to cancel)!"
      sleep 5
      DISK="${CAND[0]}"
    else
      c_err "AUTO: multiple disks — pass: $0 --auto --disk=<name>"
      return 1
    fi
  else
    rd "Target disk (e.g. nvme0n1 or sda), Enter to cancel: " DISK
    [ -n "$DISK" ] || { c_info "Cancelled."; return 1; }
  fi
  case "$DISK" in /dev/*) ;; *) DISK="/dev/$DISK" ;; esac
  if [ ! -b "$DISK" ]; then
    nm="${DISK#/dev/}"
    for alt in "v$nm" "u$nm" "s$nm" "nvme${nm}n1" "${nm}n1"; do
      if [ "$alt" != "$nm" ] && [ -b "/dev/$alt" ]; then
        c_warn "'$nm' does not exist — using '/dev/$alt'."
        DISK="/dev/$alt"; break
      fi
    done
  fi
  if [ ! -b "$DISK" ]; then
    c_err "'$DISK' does not exist. Real disks:"
    lsblk -d -e 7,11 -o NAME,SIZE,MODEL | sed 's/^/    /'
    return 1
  fi

  if lsblk -nr -o MOUNTPOINT "$DISK" | grep -qE '^/'; then
    c_err "$DISK has mounted partitions — refusing (umount first)."
    return 1
  fi

  base=$(basename "$DISK")
  if [ "$AUTO" = "1" ]; then
    c_warn "AUTO: $base will be WIPED. Continuing..."
    sleep 2
  else
    rd "CONFIRM: type '$base' again to WIPE all data: " CONFIRM
    if [ "$CONFIRM" != "$base" ]; then c_info "Mismatch — cancelled."; return 1; fi
  fi

  command -v sgdisk >/dev/null 2>&1 || { c_err "sgdisk missing — do manual install."; return 1; }

  c_info "Partitioning $DISK (GPT: EFI 1G + ext4 root)..."
  sudo sgdisk --zap-all "$DISK"
  sudo sgdisk -n1:0:+1G -t1:ef00 -c1:"EFI" "$DISK"
  sudo sgdisk -n2:0:0    -t2:8300 -c2:"nixos" "$DISK"
  sudo partprobe "$DISK" 2>/dev/null || sleep 2

  case "$DISK" in
    *[0-9]) P1="${DISK}p1"; P2="${DISK}p2" ;;
    *)      P1="${DISK}1";  P2="${DISK}2" ;;
  esac
  [ -b "$P1" ] || P1="${DISK}1"
  [ -b "$P2" ] || P2="${DISK}2"

  sudo mkfs.fat -F32 "$P1"
  sudo mkfs.ext4 -F "$P2"
  sudo mount "$P2" /mnt
  sudo mkdir -p /mnt/boot
  sudo mount "$P1" /mnt/boot

  c_info "Generating installed-system config..."
  sudo nixos-generate-config --root /mnt

  if ! grep -qE '^\s*boot.loader.(grub|systemd-boot|efi).enable = true' /mnt/etc/nixos/configuration.nix; then
    sudo sed -i \
      -e 's/^# boot.loader.systemd-boot.enable = true;/boot.loader.systemd-boot.enable = true;/' \
      -e 's/^# boot.loader.efi.canTouchEfiVariables = true;/boot.loader.efi.canTouchEfiVariables = true;/' \
      /mnt/etc/nixos/configuration.nix
    c_ok "systemd-boot enabled in /mnt/etc/nixos/configuration.nix"
  fi

  c_info "Installing with the rice (this takes a while, downloads inputs)..."
  if sudo env "NIX_CONFIG=$NIX_CONFIG" EDOTS_HOST_ROOT=/mnt \
        nixos-install --flake "$REPO_DIR/nix#edots" --impure; then
    c_ok "nixos-install: success"
  else
    c_err "nixos-install failed — see log above."
    return 1
  fi

  echo
  c_ok "DONE. After reboot: sddm → MangoWM session → login: $USER / edots → run 'passwd' first."
  if [ "$AUTO" = "1" ]; then
    c_warn "AUTO: rebooting in 5 seconds..."
    sleep 5
    sudo reboot
  fi
  rd "Reboot now? [y/N]: " rb
  case "$rb" in
    [Yy]*) sudo reboot ;;
    *) c_info "Reboot later: sudo reboot" ;;
  esac
  exit 0
}

install_nixos() {
  c_info "Detected NixOS."
  command -v nix >/dev/null 2>&1 || { c_err "nix not in PATH."; exit 1; }
  sudo_keepalive

  export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}extra-experimental-features = nix-command flakes"
  if ! nix show-config 2>/dev/null | grep -qE 'experimental-features.*flakes' \
     && [ -w /etc/nix ] && [ ! -L /etc/nix/nix.conf ]; then
    c_info "Trying to enable flakes in /etc/nix/nix.conf..."
    printf 'extra-experimental-features = nix-command flakes\n' | sudo tee -a /etc/nix/nix.conf >/dev/null 2>&1 \
      && sudo systemctl restart nix-daemon 2>/dev/null || true
  fi
  c_ok "flakes: NIX_CONFIG (env) active"

  if [ -f /etc/nixos/flake.nix ]; then
    cat << 'EOF2'
─────────────────────────────────────────────────────────────
/etc/nixos/flake.nix ALREADY EXISTS — auto-integration is unsafe.

Add to your flake manually:
  inputs.edots.url = "path:~/Dotfiles";
  inputs.edots.inputs.nixpkgs.follows = "nixpkgs";
  inputs.mango.url = "github:mangowm/mango";
  inputs.mango.inputs.nixpkgs.follows = "nixpkgs";

  modules: inputs.mango.nixosModules.mango, inputs.edots.nixosModules.edots,
    { edots.enable = true; programs.mango.enable = true;
      services.displayManager.defaultSession = "mango";
      home-manager.useUserPackages = true;
      home-manager.users.YOU = { imports = [ inputs.edots.homeManagerModules.edots ]; edots.home.enable = true; }; }

Then: sudo nixos-rebuild switch --flake .#HOST
─────────────────────────────────────────────────────────────
EOF2
    exit 0
  fi

  if [ -f /etc/nixos/hardware-configuration.nix ] \
     && grep -q 'fileSystems."/"' /etc/nixos/configuration.nix 2>/dev/null; then
    MODE="rebuild"
  else
    echo
    echo "Looks like a live CD / unconfigured host."
    echo "  [a] — AUTO: partition disk + install NixOS with the rice"
    echo "  [m] — MANUAL (print steps)"
    echo "  [s] — SKIP (attempt live-session rebuild)"
    if [ "$AUTO" = "1" ]; then
      MODE="install"
      c_warn "AUTO: chose install mode [a]."
    else
      rd "Choice [a/m/s]: " m
      case "$m" in
        [Aa]*) MODE="install" ;;
        [Mm]*)
          cat << 'EOF3'
Manual install:
  1) sudo cfdisk /dev/<disk>   # GPT: EFI ~1G + root
  2) sudo mkfs.fat -F32 <ESP> && sudo mkfs.ext4 <root>
  3) sudo mount <root> /mnt && sudo mkdir -p /mnt/boot && sudo mount <ESP> /mnt/boot
  4) sudo nixos-generate-config --root /mnt
  5) edit /mnt/etc/nixos/configuration.nix (boot.loader...)
  6) sudo EDOTS_HOST_ROOT=/mnt nixos-install --flake <repo>/nix#edots --impure
EOF3
          exit 0 ;;
        *) MODE="rebuild" ;;
      esac
    fi
  fi

  LUNIX="$REPO_DIR/nix/local-user.nix"
  if [ -f "$LUNIX" ]; then
    action=$(ask_conflict "nix/local-user.nix" overwrite)
    case "$action" in
      skip) c_info "local-user.nix kept as-is." ;;
      append)
        printf '\n  # added by install.sh %s\n  home-manager.users.%s = {\n    imports = [ ./home.nix ];\n    edots.home.enable = true;\n  };\n' "$(date +%F)" "$USER_NAME" >> "$LUNIX"
        c_ok "local-user.nix appended" ;;
      *)
        mv "$LUNIX" "$LUNIX.bak-$(date +%Y%m%d-%H%M%S)"
        write_lunix ;;
    esac
  else
    write_lunix
  fi
  grep -q 'nix/local-user.nix' "$REPO_DIR/.gitignore" 2>/dev/null || \
    echo 'nix/local-user.nix' >> "$REPO_DIR/.gitignore"
  c_ok "nix/local-user.nix -> user $USER_NAME"

  if [ "$MODE" = "install" ]; then
    nixos_auto_install
    exit $?
  fi

  c_info "Building: nixos-rebuild switch --flake $REPO_DIR/nix#edots..."
  if sudo env "NIX_CONFIG=$NIX_CONFIG" \
        nixos-rebuild switch --flake "$REPO_DIR/nix#edots" --impure; then
    c_ok "nixos-rebuild: success"
  else
    c_err "nixos-rebuild failed. On a live CD that is expected without a target disk;"
    c_err "run the installer and choose [a]."
    exit 1
  fi

  echo
  c_ok "DONE. MangoWM is the default session; the bar is edots-bar (explicit -p)."
  c_warn "If mango/autostart.conf has a manual qs launch — remove it (two instances)."
}

# ════════════════════════ ARCH-BASED ════════════════════════
post_install() {
  section "Finishing"
  write_hw_profile
  # ───────────────────── Edots screen tools (capture) ─────────────────────
  # Screenshot / OCR / Lens / recording live in the bar shell (screentool),
  # so there is no separate QuickSnip process to install.
  if [ -f "$REPO_DIR/quickshell/bar/screentool/ScreenTool.qml" ]; then
    c_ok "screentool present (part of the bar shell)"
  else
    c_warn "quickshell/bar/screentool/ScreenTool.qml missing — capture bind will not work"
    FAILED+=("screentool:missing")
  fi

  # ───────────────────── pnpm ─────────────────────
  if ! command -v pnpm >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    c_info "pnpm via npm..."
    sudo npm install -g pnpm >/dev/null 2>&1 && c_ok "pnpm" || { c_warn "pnpm failed"; FAILED+=("npm:pnpm"); }
  fi

  # ───────────────────── explicit skips ─────────────────────
  c_warn "SF Pro Display — proprietary, not installed automatically (optional: yay -S otf-san-francisco)."
  c_warn "Cursor 'Moga-Black' — install manually if you want it."

  # ───────────────────── compile pam-auth for the lock screen ─────────────────────
  PAM_SRC="$REPO_DIR/quickshell/bar/lockscreen/pam-auth.c"
  PAM_BIN="$REPO_DIR/quickshell/bar/lockscreen/pam-auth"
  if [ "$DRY" != 1 ] && [ -f "$PAM_SRC" ]; then
    c_info "Compiling lockscreen/pam-auth..."
    if cc -O2 -o "$PAM_BIN" "$PAM_SRC" -lpam; then
      chmod +x "$PAM_BIN"
      c_ok "pam-auth compiled"
    else
      c_warn "pam-auth compile failed (need gcc + pam headers)"
      FAILED+=("pam-auth")
    fi
  fi

  # ───────────────────── sync.sh install (symlinks) ─────────────────────
  if [ -x "$REPO_DIR/sync.sh" ]; then
    c_info "Symlinking configs via sync.sh install..."
    "$REPO_DIR/sync.sh" $([ "$DRY" = 1 ] && echo --dry-run) install
  else
    c_warn "sync.sh not found or not executable — link configs manually."
  fi

  # ───────────────────── systemd user services ─────────────────────
  if [ "$DRY" = 1 ]; then
    c_dry "enable + start swayidle.service"
  else
    mkdir -p "$HOME/.config/systemd/user"
    systemctl --user daemon-reload || true

    for unit in swayidle; do
      if [ -f "$HOME/.config/systemd/user/$unit.service" ]; then
        if systemctl --user enable --now "$unit.service"; then
          c_ok "$unit.service enabled + started"
        else
          c_warn "$unit.service failed to enable"; FAILED+=("systemd:$unit")
        fi
      else
        c_warn "$unit.service missing (sync.sh should have linked it)"
        FAILED+=("systemd:missing:$unit")
      fi
    done

    # Older installs shipped a separate logind-watch unit. Locking now goes
    # through the bar shell's `ilock` IPC, so that unit only restart-loops.
    if [ -f "$HOME/.config/systemd/user/edots-lockscreen.service" ]; then
      c_warn "obsolete edots-lockscreen.service found — disable it:"
      c_warn "  systemctl --user disable --now edots-lockscreen.service"
      FAILED+=("systemd:obsolete:edots-lockscreen")
    fi

    # The shell runs its own notification daemon. swaync ships a D-Bus service
    # file for org.freedesktop.Notifications, so systemd starts it whenever a
    # notification arrives while the shell is down (restart, crash) — it then
    # dies with "Could not acquire notification name" and restart-loops.
    if systemctl --user mask swaync.service 2>/dev/null; then
      c_ok "swaync.service masked (the shell has its own notification daemon)"
    else
      c_warn "could not mask swaync.service"; FAILED+=("systemd:mask:swaync")
    fi
  fi

  # ───────────────────── enable initial colour generation ─────────────────────
  if [ "$DRY" = 1 ]; then
    c_dry "generate the palette from the first wallpaper"
  elif command -v python3 >/dev/null; then
    wp=""
    # Keep the wallpaper that is currently displayed; never pick a random file.
    if command -v awww >/dev/null 2>&1; then
      wp="$(awww query 2>/dev/null | sed -nE 's/.*currently displaying: (image|animated|video): //p' | head -n1 || true)"
      [ -f "${wp:-}" ] || wp=""
    fi
    if [ -z "${wp:-}" ] && [ -f "$HOME/.config/quickshell/current-wallpaper.txt" ]; then
      wp="$(head -n1 "$HOME/.config/quickshell/current-wallpaper.txt" 2>/dev/null || true)"
      [ -f "${wp:-}" ] || wp=""
    fi
    if [ -z "${wp:-}" ]; then
      wp=$(find "$HOME/Pictures/Wallpapers" -type f \
           \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
           -print -quit 2>/dev/null)
    fi
    if [ -n "${wp:-}" ]; then
      c_info "Generating palette from $wp ..."
      python3 "$REPO_DIR/mango/scripts/wallcolors.py" "$wp" \
        && c_ok "palette generated" \
        || { c_warn "wallcolors.py failed"; FAILED+=("wallcolors"); }
    else
      c_warn "no wallpapers found — palette not generated"
    fi
  fi

  # ───────────────────── wallpaper colour index ─────────────────────
  if [ "$DRY" != 1 ] && [ -f "$REPO_DIR/quickshell/scripts/wallpaper_color_index.py" ] \
     && command -v python3 >/dev/null; then
    if python3 -c 'import PIL' >/dev/null 2>&1; then
      c_info "Indexing wallpapers by colour..."
      python3 "$REPO_DIR/quickshell/scripts/wallpaper_color_index.py" >/dev/null 2>&1 \
        && c_ok "wallpaper colour index built" \
        || { c_warn "wallpaper colour index failed (non-fatal)"; FAILED+=("wallpaper-index"); }
    else
      c_warn "Pillow missing — wallpaper colour index skipped (python-pillow / pip install pillow)"
    fi
  fi

  # ───────────────────── Firefox chrome files ─────────────────────
  if [ "$DRY" != 1 ] && command -v firefox >/dev/null 2>&1; then
    if [ -x "$REPO_DIR/edots/bin/link-firefox-chrome.sh" ]; then
      c_info "Linking Firefox chrome into the detected profile..."
      if "$REPO_DIR/edots/bin/link-firefox-chrome.sh"; then
        c_ok "Firefox chrome linked (restart Firefox to apply)"
      else
        c_warn "Firefox chrome not linked — run: $REPO_DIR/edots/bin/link-firefox-chrome.sh"
        FAILED+=("firefox-chrome")
      fi
    fi
  fi
}

install_arch() {
  c_info "Detected Arch-based distribution."
  sudo_keepalive

  # ───────────────────── pacman (official repos) ─────────────────────
  PACMAN_PKGS=(
    # Wayland / compositor
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk xdg-utils
    swayidle wlr-randr
    # Fonts
    ttf-material-symbols-variable ttf-fira-code ttf-jetbrains-mono
    # Networking / bluetooth
    networkmanager network-manager-applet bluez bluez-utils polkit pciutils
    # Power / audio
    power-profiles-daemon wireplumber pipewire pipewire-pulse pipewire-alsa
    upower
    # Wayland utils
    wl-clipboard brightnessctl wlopm iproute2 iputils slurp grim wf-recorder
    imagemagick
    # Apps (file managers, browsers, media, ... come from the optional groups)
    kitty
    libnotify cpupower playerctl bc
    inotify-tools python python-pip python-pillow
    # Shell / dev tools
    fish jq fastfetch neovim git ripgrep fd rofi curl
    eza bat btop cava yazi fzf github-cli
    # PAM headers for bar/lockscreen/pam-auth.c
    gcc pam
    # Notifications + clipboard history
    swaync cliphist
    # Screen capture: OCR, night light, updates, audio studio
    tesseract tesseract-data-eng
    gammastep pacman-contrib easyeffects
  )

  # CPU microcode, GPU userspace, laptop firmware and zram are added only when
  # the detected machine actually needs them (see choose_hw_pkgs).
  choose_hw_pkgs
  PACMAN_PKGS+=("${HW_PKGS[@]}")
  [ "${#HW_PKGS[@]}" -gt 0 ] && c_info "Hardware packages: ${HW_PKGS[*]}"

  # optional groups (interactive picker, --with / --without, --minimal)
  local _g _p
  for _g in "${GRP_KEYS[@]}"; do
    for _p in $(grp_pacman "$_g"); do
      if group_on "$_g"; then PACMAN_PKGS+=("$_p"); else PKG_SKIPPED+=("$_p"); fi
    done
  done

  # dedupe: hardware packages may already be in the base list
  _out=()
  for _p in "${PACMAN_PKGS[@]}"; do
    case " ${_out[*]} " in *" $_p "*) ;; *) _out+=("$_p") ;; esac
  done
  PACMAN_PKGS=("${_out[@]}")

  section "Official packages"
  tune_pacman
  run_spin "Syncing pacman databases" sudo pacman -Sy --noconfirm || c_warn "pacman -Sy failed — see $LOG_FILE"
  c_info "Installing ${#PACMAN_PKGS[@]} official packages..."
  local pkg pkg_new=0 pkg_old=0 pkg_bad=0 todo=()
  for pkg in "${PACMAN_PKGS[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
      pkg_old=$((pkg_old + 1)); PKG_PRESENT+=("$pkg")
    else
      todo+=("$pkg")
    fi
  done
  if [ "${#todo[@]}" -gt 0 ]; then
    # one transaction = parallel downloads and a single dependency solve; fall back to one-by-one
    if ! run_spin "pacman: ${#todo[@]} packages" sudo pacman -S --needed --noconfirm "${todo[@]}"; then
      c_warn "batch install failed (a package may be missing) — retrying one by one"
      pkg_begin "${#todo[@]}"
      for pkg in "${todo[@]}"; do
        pkg_tick "$pkg"
        pkg_run "$pkg" sudo pacman -S --needed --noconfirm "$pkg" || true
      done
      pkg_end
    fi
    for pkg in "${todo[@]}"; do
      if [ "$DRY" = 1 ] || pacman -Qi "$pkg" >/dev/null 2>&1; then
        pkg_new=$((pkg_new + 1)); PKG_INSTALLED+=("$pkg")
      else
        pkg_bad=$((pkg_bad + 1)); FAILED+=("pacman:$pkg")
        c_warn "failed: $pkg (pacman) — see $LOG_FILE"
      fi
    done
  fi
  c_ok "Official: $pkg_new new, $pkg_old present$([ "$pkg_bad" -gt 0 ] && echo ", $pkg_bad failed")."

  # ───────────────────── Google Sans Flex (GTK UI font) ─────────────────────
  section "Fonts"
  FONT_DIR="$HOME/.local/share/fonts"
  if [ ! -f "$FONT_DIR/GoogleSansFlex-Regular.ttf" ]; then
    c_info "Downloading Google Sans Flex..."
    mkdir -p "$FONT_DIR"
    if curl -fsSL -o "$FONT_DIR/GoogleSansFlex-Regular.ttf" \
      "https://raw.githubusercontent.com/LineageOS/android_external_google-fonts_google-sans-flex/lineage-23.2/GoogleSansFlex-Regular.ttf"; then
      fc-cache -f "$FONT_DIR" >/dev/null 2>&1
      c_ok "Google Sans Flex (Regular)"
      c_warn "  This is a static Regular instance; for full axes get the variable TTF from fonts.google.com"
    else
      c_warn "Google Sans Flex download failed — install manually"
      FAILED+=("font:google-sans-flex")
    fi
  else
    c_ok "Google Sans Flex already present"
  fi

  # ───────────────────── yay bootstrap ─────────────────────
  section "AUR helper"
  if ! command -v yay >/dev/null 2>&1; then
    c_info "yay not found — building from AUR..."
    run_spin "Installing base-devel" sudo pacman -S --needed --noconfirm base-devel git
    tmpdir=$(mktemp -d)
    if git clone https://aur.archlinux.org/yay.git "$tmpdir/yay" >/dev/null 2>&1 && \
       (if [ "$DRY" = 1 ]; then true; else cd "$tmpdir/yay"; fi && run_spin "Building yay (Go, a few minutes)" makepkg -si --noconfirm); then
      c_ok "yay installed"
    else
      c_err "yay build failed — see $LOG_FILE"; FAILED+=("yay-bootstrap")
    fi
    rm -rf "$tmpdir"
  else
    c_ok "yay already present"
  fi

  # ───────────────────── AUR ─────────────────────
  section "AUR packages"
  AUR_PKGS=(
    mangowm-git
    quickshell
    ttf-jetbrains-mono-nerd
    awww
    matugen
  )
  for _g in "${GRP_KEYS[@]}"; do
    group_on "$_g" || continue
    for _p in $(grp_aur "$_g"); do AUR_PKGS+=("$_p"); done
  done
  if command -v yay >/dev/null 2>&1; then
    c_info "Installing ${#AUR_PKGS[@]} AUR packages..."
    pkg_begin "${#AUR_PKGS[@]}"
    pkg_new=0; pkg_old=0; pkg_bad=0
    for pkg in "${AUR_PKGS[@]}"; do
      pkg_tick "$pkg"
      if pacman -Qi "$pkg" >/dev/null 2>&1; then
        pkg_old=$((pkg_old + 1)); PKG_PRESENT+=("$pkg"); continue
      fi
      if pkg_run "$pkg" yay -S --needed --noconfirm "$pkg"; then
        pkg_new=$((pkg_new + 1)); PKG_INSTALLED+=("$pkg")
      else
        pkg_bad=$((pkg_bad + 1)); FAILED+=("aur:$pkg")
        pkg_note "failed: $pkg (AUR) — see $LOG_FILE"
      fi
    done
    pkg_end
    c_ok "AUR: $pkg_new new, $pkg_old present$([ "$pkg_bad" -gt 0 ] && echo ", $pkg_bad failed")."
  else
    c_warn "yay unavailable — skipping AUR: ${AUR_PKGS[*]}"
    FAILED+=("aur:all (no yay)")
  fi

  setup_tuning
  section "Login shell"
  ensure_fish_shell
  setup_ai
  post_install
}


# ════════════════════════ DEBIAN / FEDORA / openSUSE / GENTOO ════════════════════════
# Логічна назва → пакет дистрибутива. «a|b» = пробувати по черзі. Порожньо = нема в репозиторіях → вручну.
pkgname() {
  local k="$1"
  case "$OS:$k" in
    debian:nm) echo network-manager ;;           fedora:nm) echo NetworkManager ;;     suse:nm) echo NetworkManager ;;
    gentoo:nm) echo net-misc/networkmanager ;;
    debian:swaync) echo sway-notification-center ;; fedora:swaync|suse:swaync) echo SwayNotificationCenter ;;
    gentoo:swaync) echo gui-apps/swaync ;;
    debian:notify) echo libnotify-bin ;;    fedora:notify) echo libnotify ;;         suse:notify) echo libnotify-tools ;;  gentoo:notify) echo x11-libs/libnotify ;;
    debian:imagemagick) echo imagemagick ;;    gentoo:imagemagick) echo media-gfx/imagemagick ;;
    fedora:imagemagick|suse:imagemagick) echo ImageMagick ;;
    debian:tesseract|suse:tesseract) echo tesseract-ocr ;; fedora:tesseract) echo tesseract ;; gentoo:tesseract) echo app-text/tesseract ;;
    debian:python) echo python3 ;; fedora:python|suse:python) echo python3 ;; gentoo:python) echo dev-lang/python ;;
    debian:pam-dev) echo libpam0g-dev ;;         fedora:pam-dev|suse:pam-dev) echo pam-devel ;; gentoo:pam-dev) echo sys-libs/pam ;;
    gentoo:gcc) echo sys-devel/gcc ;;
    debian:fonts-mono) echo fonts-jetbrains-mono ;; fedora:fonts-mono) echo jetbrains-mono-fonts-all ;; suse:fonts-mono) echo jetbrains-mono-fonts ;;
    fedora:rofi) echo "rofi-wayland|rofi" ;;
    fedora:quickshell) echo "quickshell" ;;       # потребує COPR (див. install_generic)
    debian:quickshell|suse:quickshell|gentoo:quickshell) echo "" ;;
    *:mangowm|*:awww|*:matugen|*:fonts-icons) echo "" ;;
    gentoo:brightnessctl) echo app-misc/brightnessctl ;;   gentoo:cliphist) echo gui-apps/cliphist ;;
    gentoo:wl-clipboard) echo gui-apps/wl-clipboard ;;     gentoo:swayidle) echo gui-apps/swayidle ;;
    gentoo:grim) echo gui-apps/grim ;;                     gentoo:slurp) echo gui-apps/slurp ;;
    gentoo:wf-recorder) echo gui-apps/wf-recorder ;;       gentoo:wlr-randr) echo gui-apps/wlr-randr ;;
    gentoo:kitty) echo x11-terms/kitty ;;                  gentoo:rofi) echo x11-misc/rofi ;;
    gentoo:ppd) echo sys-power/power-profiles-daemon ;;    gentoo:xdg-utils) echo x11-misc/xdg-utils ;;
    gentoo:pipewire) echo media-video/pipewire ;;          gentoo:wireplumber) echo media-video/wireplumber ;;
    gentoo:upower) echo sys-power/upower ;;                gentoo:playerctl) echo media-sound/playerctl ;;
    gentoo:jq) echo app-misc/jq ;;                         gentoo:git) echo dev-vcs/git ;;
    gentoo:fish) echo app-shells/fish ;;                   gentoo:neovim) echo app-editors/neovim ;;
    gentoo:fastfetch) echo app-misc/fastfetch ;;           gentoo:curl) echo net-misc/curl ;;
    gentoo:*) echo "" ;;
    *:ppd) echo power-profiles-daemon ;;
    *) echo "$k" ;;                                        # однакова назва (kitty, grim, slurp, jq, fish, ...)
  esac
}

pm_install_one() {  # $1 = «a|b|c»  $2 = label for the progress line
  local alt pkg label="${2:-$1}"; IFS='|' read -ra alt <<< "$1"
  for pkg in "${alt[@]}"; do
    case "$OS" in
      debian) pkg_run "$label" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" ;;
      fedora) pkg_run "$label" sudo dnf install -y "$pkg" ;;
      suse)   pkg_run "$label" sudo zypper --non-interactive install "$pkg" ;;
      gentoo) pkg_run "$label" sudo emerge --noreplace --quiet "$pkg" ;;
    esac && return 0
  done
  return 1
}

install_generic() {
  c_info "Detected $OS — generic path (packages one by one; missing ones are listed at the end)."
  sudo_keepalive
  section "Packages"
  case "$OS" in
    debian) run_spin "apt-get update" sudo apt-get update || true ;;
    fedora) sudo dnf copr enable -y errornointernet/quickshell >/dev/null 2>&1 || c_warn "COPR errornointernet/quickshell not enabled" ;;
  esac

  local CORE=(git curl gcc pam-dev python nm brightnessctl cliphist wl-clipboard notify swaync swayidle wlr-randr ppd
              pipewire wireplumber upower playerctl grim slurp wf-recorder imagemagick tesseract rofi kitty jq xdg-utils
              fonts-mono quickshell mangowm awww matugen fonts-icons)
  local OPT=(fish neovim fastfetch)
  local list=("${CORE[@]}"); [ "$MINIMAL" = 0 ] && list+=("${OPT[@]}")

  local k name
  c_info "Installing ${#list[@]} packages..."
  pkg_begin "${#list[@]}"
  for k in "${list[@]}"; do
    pkg_tick "$k"
    name="$(pkgname "$k")"
    if [ -z "$name" ]; then MANUAL+=("$k"); PKG_SKIPPED+=("$k"); continue; fi
    if pm_install_one "$name" "$k"; then PKG_INSTALLED+=("$k")
    else pkg_note "failed: $k ($name)"; FAILED+=("pkg:$k ($name)"); fi
  done
  pkg_end
  c_ok "Installed ${#PKG_INSTALLED[@]}; ${#MANUAL[@]} not in the distro repos (listed at the end)."

  # matugen є в crates.io
  if [[ " ${MANUAL[*]} " == *" matugen "* ]] && command -v cargo >/dev/null 2>&1; then
    if run_spin "matugen via cargo" cargo install matugen; then MANUAL=("${MANUAL[@]/matugen}"); fi
  fi
  for k in "${MANUAL[@]}"; do
    [ -n "$k" ] && FAILED+=("manual:$k")
  done
  c_warn "SF Pro Display — proprietary, install manually if you want it."
  section "Login shell"
  ensure_fish_shell
  post_install
}

# ───────────────────── dispatch ─────────────────────
case "$OS" in
  nixos)
    if [ "$DRY" = 1 ]; then c_err "--dry-run is not supported on NixOS (the flow partitions/rebuilds)."; exit 1; fi
    install_nixos ;;
  arch)
    if [ "$NODEPS" = 1 ]; then c_info "--no-deps: packages skipped"; post_install; else install_arch; fi ;;
  debian|fedora|suse|gentoo)
    if [ "$NODEPS" = 1 ]; then c_info "--no-deps: packages skipped"; post_install; else install_generic; fi ;;
  *)
    c_err "Unsupported distribution (no pacman, apt, dnf, zypper or emerge recognised)."
    c_err "Supported: NixOS, Arch-based, Debian/Ubuntu, Fedora, openSUSE, Gentoo. Try: ./install.sh --no-deps  (configs only)"
    exit 1
    ;;
esac
# ───────────────────── summary ─────────────────────
echo
hr
if [ "${#FAILED[@]}" -eq 0 ]; then
  c_ok "Done in $(fmt_time $(( SECONDS - START_TS ))) — no errors."
else
  c_warn "Done in $(fmt_time $(( SECONDS - START_TS ))) with ${#FAILED[@]} skipped items:"
  for f in "${FAILED[@]}"; do echo "    - $f"; done
  c_warn "Install those manually."
  for f in "${FAILED[@]}"; do
    case "$f" in
      manual:quickshell)  echo "    quickshell   → https://quickshell.org (build from source / distro overlay)" ;;
      manual:mangowm)     echo "    MangoWM      → https://github.com/DreamMaoMao/mangowc (build from source)" ;;
      manual:matugen)     echo "    matugen      → cargo install matugen  (or a release from github.com/InioX/matugen)" ;;
      manual:awww)        echo "    awww         → https://github.com/LGFae/swww (build from source)" ;;
      manual:fonts-icons) echo "    Material Symbols Rounded → fonts.google.com/icons → ~/.local/share/fonts, then fc-cache -f" ;;
    esac
  done
fi
kv "Packages" "${#PKG_INSTALLED[@]} installed · ${#PKG_PRESENT[@]} already present · ${#PKG_SKIPPED[@]} skipped"
kv "Profile"  "tier $HW_TIER · effects $HW_EFFECTS"
kv "Report"   "$STATE_DIR/install-report.json"
kv "Hardware" "$STATE_DIR/hardware.json"
[ -n "${LOG_FILE:-}" ] && kv "Log" "$STATE_DIR/latest.log"
hr
echo "Next steps:"
echo "  1. Relogin (so fish/swayidle/systemd pick up the environment)."
echo "  2. Bar:      edots reload        (or: qs -p ~/.config/quickshell/bar/shell.qml)"
echo "  3. Settings: edots settings"
echo "  4. Health:   edots doctor"
echo "  5. Lock:     edots lock"
echo "  6. Idle/suspend: systemctl --user status swayidle.service"
