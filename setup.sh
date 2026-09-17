#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup.sh -- Bash setup for Linux servers and WSL
# https://github.com/TheDarthAdmin/Bash-Setup
#
# The Bash twin of ShellSetup.ps1: Oh My Posh with a local theme, ble.sh
# predictions and highlighting, eza listings with icons, fzf, history
# filtering, and the same helpers as the PowerShell profile.
#
# Supported: Ubuntu, Debian, RHEL, Rocky, AlmaLinux, Fedora (x86_64, aarch64)
#
# Safe to run more than once: whatever is in place is skipped, and any file
# that changes is backed up first. Everything except distro packages installs
# into your home folder.
# ---------------------------------------------------------------------------

# The whole script lives in functions and only runs on the last line, so a
# download cut short by 'curl | bash' can never execute half a script.

set -uo pipefail

REPO_RAW_DEFAULT='https://raw.githubusercontent.com/TheDarthAdmin/Bash-Setup'

usage() {
    cat <<'USAGE'
Usage: setup.sh [options]

  -n, --dry-run          Show what would happen without changing anything
      --diagnose         Print detected distro, paths and tools, then exit
      --install-extras   Also install fzf and the Ookla Speedtest CLI
      --install-font     Install Hack Nerd Font (Linux desktops only; for SSH
                         and WSL the font belongs on the machine you type on)
      --update           Re-download tools, ble.sh and the theme to latest
      --theme <name>     Oh My Posh theme to store locally (default: darthadmin;
                         built-in names such as kali work too)
      --branch <name>    Branch to download repo files from (default: main)
      --skip-packages    Do not install distro packages (no sudo needed)
      --skip-tools       Do not install oh-my-posh / eza / fzf binaries
      --skip-blesh       Do not install ble.sh
      --uninstall        Remove the hook from ~/.bashrc (files are kept)
  -h, --help             Show this help

From the web:
  curl -fsSL https://raw.githubusercontent.com/TheDarthAdmin/Bash-Setup/main/setup.sh | bash
  curl -fsSL https://raw.githubusercontent.com/TheDarthAdmin/Bash-Setup/main/setup.sh | bash -s -- --install-extras
USAGE
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_STEP=$'\e[36m'; C_OK=$'\e[32m'; C_SKIP=$'\e[90m'; C_FAIL=$'\e[33m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
else
    C_STEP=''; C_OK=''; C_SKIP=''; C_FAIL=''; C_BOLD=''; C_RST=''
fi
step() { printf '%s==> %s%s\n' "$C_STEP" "$*" "$C_RST"; }
ok()   { printf '%s    %s%s\n' "$C_OK"   "$*" "$C_RST"; }
skip() { printf '%s    %s%s\n' "$C_SKIP" "$*" "$C_RST"; }
fail() { printf '%s    %s%s\n' "$C_FAIL" "$*" "$C_RST"; }
would() { printf '%s    [dry-run] %s%s\n' "$C_SKIP" "$*" "$C_RST"; }

# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------
detect_environment() {
    OS_ID=''; OS_LIKE=''; OS_NAME='unknown'; OS_VERSION=''
    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        OS_ID=$(. /etc/os-release && echo "${ID-}")
        # shellcheck source=/dev/null
        OS_LIKE=$(. /etc/os-release && echo "${ID_LIKE-}")
        # shellcheck source=/dev/null
        OS_NAME=$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")
        # shellcheck source=/dev/null
        OS_VERSION=$(. /etc/os-release && echo "${VERSION_ID-}")
    fi

    PKG=''
    case " $OS_ID $OS_LIKE " in
        *" debian "*|*" ubuntu "*) PKG=apt ;;
        *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*) PKG=dnf ;;
    esac
    if [[ -z $PKG ]]; then
        if command -v apt-get >/dev/null 2>&1; then PKG=apt
        elif command -v dnf >/dev/null 2>&1; then PKG=dnf
        fi
    fi

    case $(uname -m) in
        x86_64|amd64)  ARCH=amd64 ;;
        aarch64|arm64) ARCH=arm64 ;;
        *)             ARCH=unsupported ;;
    esac

    IS_WSL=0
    if [[ -n ${WSL_DISTRO_NAME-} ]] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        IS_WSL=1
    fi

    CAN_ROOT=0
    if [[ $EUID -eq 0 ]] || command -v sudo >/dev/null 2>&1; then CAN_ROOT=1; fi

    CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    BIN_DIR="$HOME/.local/bin"
    DARTH_DIR="$CONFIG_HOME/darthshell"
    POSH_DIR="$CONFIG_HOME/oh-my-posh"
    BLESH_DIR="$DATA_HOME/blesh"
    BASHRC="$HOME/.bashrc"

    # Tools installed on an earlier run must be found even before the profile
    # has put ~/.local/bin on PATH.
    case ":$PATH:" in *":$BIN_DIR:"*) ;; *) PATH="$BIN_DIR:$PATH" ;; esac

    LOCAL_ROOT=''
    if [[ -n ${BASH_SOURCE[0]-} && -f ${BASH_SOURCE[0]} ]]; then
        LOCAL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
        [[ -f $LOCAL_ROOT/darthshell.bash ]] || LOCAL_ROOT=''
    fi
    REPO_RAW="${DARTH_REPO_RAW:-$REPO_RAW_DEFAULT}/$BRANCH"

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/darthshell.XXXXXX")
    trap 'rm -rf "$TMP_DIR"' EXIT
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
has() { command -v "$1" >/dev/null 2>&1; }

as_root() {
    if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

download() {
    # download <url> <dest>
    curl -fsSL --retry 3 --connect-timeout 15 -o "$2" "$1"
}

github_latest_tag() {
    # Resolves the latest release tag through the redirect, which avoids the
    # rate-limited GitHub API.
    local url
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest") || return 1
    printf '%s' "${url##*/}"
}

backup_file() {
    local base backup n=1
    base="$1.bak-$(date +%Y%m%d-%H%M%S)"
    backup=$base
    # Two backups in the same second must not overwrite each other.
    while [[ -e $backup ]]; do backup="$base.$((n++))"; done
    cp -p -- "$1" "$backup" && ok "Backed up existing file to ${backup##*/}"
}

install_file() {
    # install_file <staged source> <destination> [mode]
    local src=$1 dest=$2 mode=${3:-0644}
    if [[ -f $dest ]] && cmp -s -- "$src" "$dest"; then
        skip "Unchanged: $dest"
        return 0
    fi
    if (( DRY_RUN )); then
        would "install $dest"
        return 0
    fi
    mkdir -p -- "$(dirname "$dest")" || return 1
    [[ -f $dest ]] && { backup_file "$dest" || return 1; }
    install -m "$mode" -- "$src" "$dest" || return 1
    ok "Installed $dest"
}

fetch_repo_file() {
    # fetch_repo_file <relative path> <staged dest>
    if [[ -n $LOCAL_ROOT && -f $LOCAL_ROOT/$1 ]]; then
        cp -- "$LOCAL_ROOT/$1" "$2" && skip "Source: local file $1"
    else
        download "$REPO_RAW/$1" "$2" && skip "Source: $REPO_RAW/$1"
    fi
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
install_packages() {
    step 'Distro packages'
    if (( SKIP_PACKAGES )); then skip 'Skipped (--skip-packages).'; return 0; fi
    if [[ -z $PKG ]]; then fail "Unsupported distro ($OS_NAME): install curl, git, jq, tar, xz, gawk, unzip and bash-completion yourself."; return 1; fi

    # command-or-file : apt package : dnf package
    local wanted=(
        'curl:curl:curl'
        'git:git:git'
        'jq:jq:jq'
        'tar:tar:tar'
        'xz:xz-utils:xz'
        'gawk:gawk:gawk'
        'unzip:unzip:unzip'
        'install:coreutils:coreutils'
        'find:findutils:findutils'
        'cmp:diffutils:diffutils'
        '/usr/share/bash-completion/bash_completion:bash-completion:bash-completion'
    )
    [[ $PKG == apt ]] && wanted+=('/etc/ssl/certs/ca-certificates.crt:ca-certificates:ca-certificates')
    (( INSTALL_FONT )) && wanted+=('fc-cache:fontconfig:fontconfig')

    local missing=() entry probe apt_pkg dnf_pkg
    for entry in "${wanted[@]}"; do
        IFS=: read -r probe apt_pkg dnf_pkg <<< "$entry"
        if [[ $probe == /* ]]; then [[ -e $probe ]] && continue
        else has "$probe" && continue
        fi
        if [[ $PKG == apt ]]; then missing+=("$apt_pkg"); else missing+=("$dnf_pkg"); fi
    done

    if (( ${#missing[@]} == 0 )); then skip 'All required packages are present.'; return 0; fi

    if (( ! CAN_ROOT )); then
        fail "Missing packages (${missing[*]}) but no root or sudo. Ask an admin, or re-run with --skip-packages."
        return 1
    fi
    if (( DRY_RUN )); then would "$PKG install ${missing[*]}"; return 0; fi

    skip "Installing: ${missing[*]}"
    if [[ $PKG == apt ]]; then
        # A single broken third-party repo makes 'apt-get update' fail while the
        # packages we need are still available, so carry on and let install decide.
        as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>"$TMP_DIR/apt-update.log" ||
            fail "apt-get update reported errors (often a broken third-party repo); trying the install anyway."
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" \
            >"$TMP_DIR/pkg.log" 2>&1
    else
        # Everything needed is in BaseOS/AppStream on RHEL 8+, so no EPEL.
        as_root dnf install -y "${missing[@]}" >"$TMP_DIR/pkg.log" 2>&1
    fi || { fail 'Package installation failed:'; tail -n 20 "$TMP_DIR/pkg.log" | sed 's/^/      /'; return 1; }
    ok "Installed: ${missing[*]}"
}

install_binary() {
    # install_binary <name> <staged file>
    if (( DRY_RUN )); then would "install $BIN_DIR/$1"; return 0; fi
    mkdir -p -- "$BIN_DIR" && install -m 0755 -- "$2" "$BIN_DIR/$1"
}

tool_needed() {
    # tool_needed <command>: true when it should be (re)installed
    local path
    path=$(command -v "$1" 2>/dev/null) || return 0
    if (( UPDATE )); then
        [[ $path == "$BIN_DIR/$1" ]] && return 0
        skip "$1 is installed outside ~/.local/bin ($path); leaving it alone."
        return 1
    fi
    skip "$1 is already installed ($path)."
    return 1
}

install_oh_my_posh() {
    tool_needed oh-my-posh || return 0
    if (( DRY_RUN )); then would "download oh-my-posh (latest) to $BIN_DIR"; return 0; fi
    local asset="posh-linux-$ARCH" base='https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download'
    download "$base/$asset" "$TMP_DIR/$asset" &&
    download "$base/checksums.txt" "$TMP_DIR/omp-checksums.txt" || { fail 'Oh My Posh download failed.'; return 1; }
    ( cd "$TMP_DIR" && grep " $asset\$" omp-checksums.txt | sha256sum -c --quiet - ) ||
        { fail 'Oh My Posh checksum mismatch; not installed.'; return 1; }
    install_binary oh-my-posh "$TMP_DIR/$asset" && ok "Oh My Posh $("$BIN_DIR/oh-my-posh" version 2>/dev/null) installed."
}

install_eza() {
    tool_needed eza || return 0
    if (( DRY_RUN )); then would "download eza (latest) to $BIN_DIR"; return 0; fi
    # Static musl build on x86_64 so it runs on older glibc (RHEL 8).
    local asset
    if [[ $ARCH == amd64 ]]; then asset='eza_x86_64-unknown-linux-musl.tar.gz'
    else asset='eza_aarch64-unknown-linux-gnu.tar.gz'
    fi
    download "https://github.com/eza-community/eza/releases/latest/download/$asset" "$TMP_DIR/$asset" ||
        { fail 'eza download failed.'; return 1; }
    mkdir -p "$TMP_DIR/eza" && tar -xzf "$TMP_DIR/$asset" -C "$TMP_DIR/eza" || { fail 'eza archive could not be unpacked.'; return 1; }
    install_binary eza "$(find "$TMP_DIR/eza" -type f -name eza | head -n1)" && ok "eza $("$BIN_DIR/eza" --version 2>/dev/null | sed -n 2p) installed."
}

install_fzf() {
    tool_needed fzf || return 0
    if (( DRY_RUN )); then would "download fzf (latest) to $BIN_DIR"; return 0; fi
    local tag version asset
    tag=$(github_latest_tag junegunn/fzf) || { fail 'Could not resolve the latest fzf release.'; return 1; }
    version=${tag#v}
    asset="fzf-$version-linux_$ARCH.tar.gz"
    local base="https://github.com/junegunn/fzf/releases/download/$tag"
    download "$base/$asset" "$TMP_DIR/$asset" &&
    download "$base/fzf_${version}_checksums.txt" "$TMP_DIR/fzf-checksums.txt" || { fail 'fzf download failed.'; return 1; }
    ( cd "$TMP_DIR" && grep " $asset\$" fzf-checksums.txt | sha256sum -c --quiet - ) ||
        { fail 'fzf checksum mismatch; not installed.'; return 1; }
    mkdir -p "$TMP_DIR/fzf" && tar -xzf "$TMP_DIR/$asset" -C "$TMP_DIR/fzf" &&
    install_binary fzf "$TMP_DIR/fzf/fzf" && ok "fzf $version installed."
}

install_speedtest() {
    tool_needed speedtest || return 0
    if (( DRY_RUN )); then would "download Ookla Speedtest CLI to $BIN_DIR"; return 0; fi
    local arch=x86_64; [[ $ARCH == arm64 ]] && arch=aarch64
    local asset="ookla-speedtest-1.2.0-linux-$arch.tgz"
    download "https://install.speedtest.net/app/cli/$asset" "$TMP_DIR/$asset" ||
        { fail 'Speedtest CLI download failed.'; return 1; }
    mkdir -p "$TMP_DIR/speedtest" && tar -xzf "$TMP_DIR/$asset" -C "$TMP_DIR/speedtest" &&
    install_binary speedtest "$TMP_DIR/speedtest/speedtest" && ok 'Speedtest CLI installed.'
}

install_tools() {
    step 'Command-line tools'
    if (( SKIP_TOOLS )); then skip 'Skipped (--skip-tools).'; return 0; fi
    if [[ $ARCH == unsupported ]]; then fail "Unsupported CPU architecture: $(uname -m)"; return 1; fi
    has curl || { fail 'curl is required.'; return 1; }
    local rc=0
    install_oh_my_posh || rc=1
    install_eza        || rc=1
    if (( INSTALL_EXTRAS )); then
        install_fzf       || rc=1
        install_speedtest || rc=1
    fi
    return $rc
}

install_blesh() {
    step 'ble.sh'
    if (( SKIP_BLESH )); then skip 'Skipped (--skip-blesh).'; return 0; fi
    if [[ -r $BLESH_DIR/ble.sh ]] && (( ! UPDATE )); then skip "Already installed at $BLESH_DIR."; return 0; fi
    if (( DRY_RUN )); then would "install ble.sh (nightly) to $BLESH_DIR"; return 0; fi
    has xz || { fail 'xz is required to unpack ble.sh (install the xz package).'; return 1; }

    download 'https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz' "$TMP_DIR/ble.tar.xz" ||
        { fail 'ble.sh download failed.'; return 1; }
    tar -xJf "$TMP_DIR/ble.tar.xz" -C "$TMP_DIR" || { fail 'ble.sh archive could not be unpacked.'; return 1; }
    local src
    src=$(find "$TMP_DIR" -maxdepth 1 -type d -name 'ble-nightly*' | head -n1)
    if ! bash "$src/ble.sh" --install "$DATA_HOME" >"$TMP_DIR/blesh.log" 2>&1; then
        fail 'ble.sh install failed:'
        sed 's/^/      /' "$TMP_DIR/blesh.log"
        return 1
    fi
    ok "ble.sh installed at $BLESH_DIR"
}

install_theme() {
    step "Oh My Posh theme ($THEME)"
    local dest="$POSH_DIR/$THEME.omp.json"

    # This repo's own themes are always compared and refreshed, so theme
    # changes arrive with a normal re-run.
    if fetch_repo_file "themes/$THEME.omp.json" "$TMP_DIR/theme.json" 2>/dev/null; then
        :
    elif [[ -f $dest ]] && (( ! UPDATE )); then
        skip "Already stored at $dest"
        return 0
    elif (( DRY_RUN )); then
        would "download Oh My Posh theme '$THEME' to $dest"
        return 0
    else
        local url="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/$THEME.omp.json"
        download "$url" "$TMP_DIR/theme.json" || { fail "Theme '$THEME' not found in this repo or at $url"; return 1; }
        skip "Source: $url"
    fi

    if has jq && ! jq empty "$TMP_DIR/theme.json" 2>/dev/null; then
        fail 'The theme is not valid JSON; not installed.'; return 1
    fi
    install_file "$TMP_DIR/theme.json" "$dest"
}

install_profile() {
    step 'Bash profile'
    fetch_repo_file darthshell.bash "$TMP_DIR/darthshell.bash" || { fail 'Could not get darthshell.bash.'; return 1; }
    bash -n "$TMP_DIR/darthshell.bash" || { fail 'darthshell.bash has a syntax error; not installed.'; return 1; }
    install_file "$TMP_DIR/darthshell.bash" "$DARTH_DIR/darthshell.bash" || return 1

    if [[ -f $DARTH_DIR/local.bash ]]; then
        skip "Keeping your settings: $DARTH_DIR/local.bash"
    elif fetch_repo_file config/local.bash.example "$TMP_DIR/local.bash"; then
        install_file "$TMP_DIR/local.bash" "$DARTH_DIR/local.bash"
    fi
}

HOOK_BEGIN='# >>> darthshell >>>'
HOOK_END='# <<< darthshell <<<'

install_hook() {
    step '~/.bashrc hook'
    if [[ -f $BASHRC ]] && grep -qF "$HOOK_BEGIN" "$BASHRC"; then
        skip 'Already present.'
    elif (( DRY_RUN )); then
        would "append the darthshell block to $BASHRC"
    else
        [[ -f $BASHRC ]] && backup_file "$BASHRC"
        {
            printf '\n%s\n' "$HOOK_BEGIN"
            printf '# Added by setup.sh (https://github.com/TheDarthAdmin/Bash-Setup). Keep this block last.\n'
            printf '[ -r "%s" ] && . "%s"\n' '${XDG_CONFIG_HOME:-$HOME/.config}/darthshell/darthshell.bash' '${XDG_CONFIG_HOME:-$HOME/.config}/darthshell/darthshell.bash'
            printf '%s\n' "$HOOK_END"
        } >> "$BASHRC" && ok "Added to $BASHRC"
    fi

    # Login shells (SSH, WSL) read ~/.bash_profile first; make sure it reaches ~/.bashrc.
    if [[ -f $HOME/.bash_profile ]] && ! grep -Eq '\.bashrc' "$HOME/.bash_profile"; then
        if (( DRY_RUN )); then
            would "make ~/.bash_profile source ~/.bashrc"
        else
            backup_file "$HOME/.bash_profile"
            printf '\n# Added by darthshell setup.sh\n[ -f ~/.bashrc ] && . ~/.bashrc\n' >> "$HOME/.bash_profile"
            ok '~/.bash_profile now sources ~/.bashrc'
        fi
    fi
}

install_font() {
    step 'Hack Nerd Font'
    if (( ! INSTALL_FONT )); then
        skip 'Not requested. Over SSH and in WSL the font belongs on the machine you type on.'
        return 0
    fi
    local dir="$DATA_HOME/fonts/HackNerdFont"
    if compgen -G "$dir/*.ttf" >/dev/null && (( ! UPDATE )); then skip "Already installed at $dir"; return 0; fi
    if (( DRY_RUN )); then would "install Hack Nerd Font to $dir"; return 0; fi
    has unzip || { fail 'unzip is required.'; return 1; }
    download 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip' "$TMP_DIR/Hack.zip" ||
        { fail 'Font download failed.'; return 1; }
    mkdir -p "$dir" && unzip -oq "$TMP_DIR/Hack.zip" '*.ttf' -d "$dir" || { fail 'Font unpack failed.'; return 1; }
    has fc-cache && fc-cache -f "$dir" >/dev/null 2>&1
    ok "Installed at $dir"
}

uninstall_hook() {
    step 'Uninstall'
    if [[ ! -f $BASHRC ]] || ! grep -qF "$HOOK_BEGIN" "$BASHRC"; then
        skip 'No darthshell block in ~/.bashrc.'
    elif (( DRY_RUN )); then
        would "remove the darthshell block from $BASHRC"
    else
        backup_file "$BASHRC"
        local tmp="$TMP_DIR/bashrc"
        awk -v b="$HOOK_BEGIN" -v e="$HOOK_END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$BASHRC" > "$tmp" &&
            cat "$tmp" > "$BASHRC" && ok 'Removed the darthshell block from ~/.bashrc.'
    fi
    skip 'Left in place (delete by hand if you want them gone):'
    skip "  $DARTH_DIR  $POSH_DIR  $BLESH_DIR"
    skip "  $BIN_DIR/{oh-my-posh,eza,fzf,speedtest}"
}

diagnose() {
    step 'System'
    skip "Distro       : $OS_NAME (id=$OS_ID like=${OS_LIKE:-none} version=$OS_VERSION)"
    skip "Package mgr  : ${PKG:-none detected}"
    skip "Architecture : $(uname -m) -> $ARCH"
    skip "WSL          : $IS_WSL${WSL_DISTRO_NAME:+ ($WSL_DISTRO_NAME)}"
    skip "Bash         : $BASH_VERSION$( ((BASH_VERSINFO[0] < 5)) && printf ' (no per-section timings before bash 5)')"
    skip "Root / sudo  : euid=$EUID sudo=$(has sudo && echo yes || echo no)"
    skip "Script from  : ${LOCAL_ROOT:-<download: $REPO_RAW>}"

    step 'Tools'
    local t
    for t in curl git jq xz gawk unzip oh-my-posh eza fzf speedtest; do
        if has "$t"; then ok "$t : $(command -v "$t")"; else skip "$t : not found"; fi
    done
    [[ -f /usr/share/bash-completion/bash_completion ]] && ok 'bash-completion : present' || skip 'bash-completion : not found'

    step 'Files'
    for t in "$DARTH_DIR/darthshell.bash" "$DARTH_DIR/local.bash" "$POSH_DIR/$THEME.omp.json" "$BLESH_DIR/ble.sh"; do
        if [[ -e $t ]]; then ok "$t"; else skip "$t (missing)"; fi
    done
    if [[ -f $BASHRC ]] && grep -qF "$HOOK_BEGIN" "$BASHRC"; then ok '~/.bashrc hook present'; else skip '~/.bashrc hook missing'; fi
    if [[ -f $HOME/.bash_profile ]]; then
        if grep -Eq '\.bashrc' "$HOME/.bash_profile"; then ok '~/.bash_profile sources ~/.bashrc'
        else fail '~/.bash_profile does not source ~/.bashrc (login shells will skip the profile)'
        fi
    fi
    case ":$PATH:" in *":$BIN_DIR:"*) ok "$BIN_DIR is on PATH" ;; *) skip "$BIN_DIR not on PATH yet (the profile adds it)" ;; esac
}

summary() {
    step 'Result'
    local t
    for t in oh-my-posh eza; do
        if has "$t" || [[ -x $BIN_DIR/$t ]]; then ok "$t"; else fail "$t missing"; fi
    done
    if (( INSTALL_EXTRAS )); then
        for t in fzf speedtest; do
            if has "$t" || [[ -x $BIN_DIR/$t ]]; then ok "$t"; else fail "$t missing"; fi
        done
    fi
    if (( ! SKIP_BLESH )); then
        [[ -r $BLESH_DIR/ble.sh ]] && ok 'ble.sh' || fail 'ble.sh missing'
    fi
    [[ -f $POSH_DIR/$THEME.omp.json ]] && ok "theme $THEME" || fail "theme $THEME missing"
    [[ -f $DARTH_DIR/darthshell.bash ]] && ok 'profile' || fail 'profile missing'
    grep -qF "$HOOK_BEGIN" "$BASHRC" 2>/dev/null && ok '~/.bashrc hook' || fail '~/.bashrc hook missing'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    DRY_RUN=0; DIAGNOSE=0; INSTALL_EXTRAS=0; INSTALL_FONT=0; UPDATE=0; UNINSTALL=0
    SKIP_PACKAGES=0; SKIP_TOOLS=0; SKIP_BLESH=0
    THEME=darthadmin; BRANCH=main

    while (( $# )); do
        case $1 in
            -n|--dry-run)     DRY_RUN=1 ;;
            --diagnose)       DIAGNOSE=1 ;;
            --install-extras) INSTALL_EXTRAS=1 ;;
            --install-font)   INSTALL_FONT=1 ;;
            --update)         UPDATE=1 ;;
            --uninstall)      UNINSTALL=1 ;;
            --skip-packages)  SKIP_PACKAGES=1 ;;
            --skip-tools)     SKIP_TOOLS=1 ;;
            --skip-blesh)     SKIP_BLESH=1 ;;
            --theme)          THEME=${2:?--theme needs a name}; shift ;;
            --theme=*)        THEME=${1#*=} ;;
            --branch)         BRANCH=${2:?--branch needs a name}; shift ;;
            --branch=*)       BRANCH=${1#*=} ;;
            -h|--help)        usage; return 0 ;;
            *)                printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; return 2 ;;
        esac
        shift
    done

    if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
        echo "Bash 4.4 or newer is required (this is $BASH_VERSION)." >&2
        return 1
    fi

    detect_environment

    printf '\n%sBash setup for Linux and WSL%s\n' "$C_BOLD" "$C_RST"
    printf '%s----------------------------%s\n' "$C_SKIP" "$C_RST"
    printf '%s%s, bash %s%s%s\n' "$C_SKIP" "$OS_NAME" "$BASH_VERSION" "$( ((DRY_RUN)) && printf '  [dry-run: no changes]')" "$C_RST"

    if (( DIAGNOSE )); then diagnose; return 0; fi
    if (( UNINSTALL )); then uninstall_hook; return 0; fi

    local failed=0
    install_packages || failed=1
    install_tools    || failed=1
    install_blesh    || failed=1
    install_theme    || failed=1
    install_font     || failed=1
    install_profile  || failed=1
    install_hook     || failed=1
    (( DRY_RUN )) || summary

    printf '\n'
    if (( failed )); then
        printf '%sFinished with warnings (see above). Run with --diagnose for details.%s\n' "$C_FAIL" "$C_RST"
    else
        printf '%sDone. Start a new shell, or run: exec bash%s\n' "$C_OK" "$C_RST"
    fi
    if (( IS_WSL )); then
        printf '%sWSL: colours, font and background come from Windows Terminal (see README).%s\n' "$C_SKIP" "$C_RST"
    fi
    printf '\n'
    return $failed
}

main "$@"
