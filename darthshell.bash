# shellcheck shell=bash
# ---------------------------------------------------------------------------
# darthshell.bash -- Bash profile for Linux servers and WSL
# https://github.com/TheDarthAdmin/Bash-Setup
#
# The Bash twin of MyPwshProfile.ps1, with the same house rules:
#   * It never breaks the shell. Every optional piece checks before it runs.
#   * It never installs anything. setup.sh installs; this file only loads.
#   * It never touches the network at startup.
#   * It stays quiet. Nothing is printed on a normal start.
#
# Your own settings go in ~/.config/darthshell/local.bash, which setup.sh
# never overwrites. Run darth-help to list what this profile adds.
# ---------------------------------------------------------------------------

# Interactive shells only.
[[ $- == *i* ]] || return 0

DARTHSHELL_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/darthshell"

# Section timings (bash 5+ only, EPOCHREALTIME is free; no subshells).
DARTH_LOAD_SECTIONS=()
DARTH_LOAD_MS=()
__darth_t0=${EPOCHREALTIME-}
__darth_mark() {
    [[ -n ${EPOCHREALTIME-} && -n ${__darth_t0-} ]] || return 0
    local now=$EPOCHREALTIME
    DARTH_LOAD_SECTIONS+=("$1")
    DARTH_LOAD_MS+=($(( (${now//[!0-9]/} - ${__darth_t0//[!0-9]/}) / 1000 )))
    __darth_t0=$now
}

__darth_has() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Settings -- override any of these in local.bash
# ---------------------------------------------------------------------------
: "${DARTH_POSH_THEME:=darthadmin}"   # Oh My Posh theme (stored locally by setup.sh)
: "${DARTH_BLESH:=1}"           # 1 = ble.sh predictions/highlighting, 0 = plain readline
: "${DARTH_ICONS:=1}"           # 1 = Nerd Font icons in listings (your *client* needs the font)

# Command lines matching any of these glob patterns are never saved to history
# (Bash's HISTIGNORE, which ble.sh honours too). They are the Bash version of
# PSReadLine's sensitive-history filter plus the Microsoft 365 extras from the
# PowerShell profile. Add your own to DARTH_HISTORY_EXTRA_IGNORE in local.bash.
DARTH_HISTORY_IGNORE=(
    '*--password[= ]*' '*--passwd[= ]*' '*--pass[= ]*' '*--secret[= ]*'
    '*--client-secret[= ]*' '*--token[= ]*' '*--api-key[= ]*' '*--apikey[= ]*'
    '*PASSWORD*=*' '*PASSWD*=*' '*SECRET*=*' '*TOKEN*=*' '*API_KEY*=*' '*APIKEY*=*'
    '*eyJ*.eyJ*'            # JWT (access/ID tokens)
    '*[?&]sig=*'            # Azure SAS signature
    '*AccountKey=*'         # storage connection strings
    '*[Bb]earer *'          # Authorization headers
    '*sshpass -p*'
)
DARTH_HISTORY_EXTRA_IGNORE=()

# shellcheck source=/dev/null
[[ -r $DARTHSHELL_HOME/local.bash ]] && source "$DARTHSHELL_HOME/local.bash"

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac

__darth_mark 'Settings'

# ---------------------------------------------------------------------------
# ble.sh (Bash Line Editor): the PSReadLine of Bash
# ---------------------------------------------------------------------------
# Loaded early and attached at the very end of this file, as ble.sh requires.
# Skipped when there is no real terminal (scp, CI, piped input) or TERM=dumb.
__darth_blesh=0
if [[ $DARTH_BLESH == 1 && -z ${BLE_VERSION-} && -t 0 && -t 1 && ${TERM:-dumb} != dumb ]] &&
   [[ -r $HOME/.local/share/blesh/ble.sh ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.local/share/blesh/ble.sh" --attach=none && __darth_blesh=1
fi
__darth_mark 'ble.sh'

# ---------------------------------------------------------------------------
# bash-completion
# ---------------------------------------------------------------------------
if [[ -z ${BASH_COMPLETION_VERSINFO-} ]]; then
    for __darth_f in /usr/share/bash-completion/bash_completion /etc/bash_completion; do
        # shellcheck source=/dev/null
        [[ -r $__darth_f ]] && { source "$__darth_f"; break; }
    done
fi
__darth_mark 'bash-completion'

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
shopt -s histappend cmdhist checkwinsize
HISTCONTROL=ignoreboth          # a leading space also keeps a command out of history
HISTSIZE=10000
HISTFILESIZE=20000

__darth_join_ignore() {
    local IFS=:
    local patterns="${DARTH_HISTORY_IGNORE[*]}${DARTH_HISTORY_EXTRA_IGNORE[*]:+:${DARTH_HISTORY_EXTRA_IGNORE[*]}}"
    case ":${HISTIGNORE-}:" in
        *":${DARTH_HISTORY_IGNORE[0]}:"*) ;;                       # already added (profile re-sourced)
        *) HISTIGNORE="${HISTIGNORE:+$HISTIGNORE:}$patterns" ;;
    esac
}
__darth_join_ignore

# Runs before every prompt: appends new history to disk right away, so parallel
# sessions (tmux panes, several SSH logins) do not lose commands.
__darth_prompt_pre() {
    local status=$?
    builtin history -a

    # WSL: tell Windows Terminal the current folder, so "Duplicate tab" and
    # new panes open in the same directory.
    if [[ -n ${WSL_DISTRO_NAME-} ]]; then
        local winpath
        if [[ $PWD =~ ^/mnt/([a-z])(/.*)?$ ]]; then
            winpath="${BASH_REMATCH[1]^^}:${BASH_REMATCH[2]:-/}"
        else
            winpath="//wsl.localhost/$WSL_DISTRO_NAME$PWD"
        fi
        # shellcheck disable=SC1003  # ESC + backslash is the string terminator, not a quote escape
        printf '\e]9;9;%s\e\\' "${winpath//\//\\}"
    fi
    return "$status"
}

if [[ " ${PROMPT_COMMAND[*]-} " != *" __darth_prompt_pre "* ]]; then
    PROMPT_COMMAND=(__darth_prompt_pre "${PROMPT_COMMAND[@]}")
fi
__darth_mark 'History'

# ---------------------------------------------------------------------------
# Key bindings and colours
# ---------------------------------------------------------------------------
# Alt+S: put the current line in history without running it.
__darth_save_line() {
    [[ -n $READLINE_LINE ]] && builtin history -s "$READLINE_LINE"
    READLINE_LINE=''
    READLINE_POINT=0
}

bind 'set completion-ignore-case on'        2>/dev/null
bind 'set show-all-if-ambiguous on'         2>/dev/null
bind 'set menu-complete-display-prefix on'  2>/dev/null
bind 'set colored-stats on'                 2>/dev/null
bind 'set colored-completion-prefix on'     2>/dev/null
bind 'set mark-symlinked-directories on'    2>/dev/null

if (( __darth_blesh )); then
    # Up/Down search history by what is already typed; F7 clears the screen.
    ble-bind -f up   'history-search-backward hide-status:immediate-accept:empty=history-move:point=end'
    ble-bind -f down 'history-search-forward hide-status:immediate-accept:empty=history-move:point=end'
    ble-bind -f f7   clear-screen
    ble-bind -x M-s  __darth_save_line

    # Match the DarthAdmin Windows Terminal scheme.
    ble-face -s auto_complete       fg='#4B5160'
    ble-face -s command_builtin     fg='#E5C07B'
    ble-face -s command_file        fg='#E5C07B'
    ble-face -s command_alias       fg='#E5C07B'
    ble-face -s command_function    fg='#E5C07B'
    ble-face -s command_keyword     fg='#C678DD'
    ble-face -s argument_option     fg='#8A93A3'
    ble-face -s syntax_quoted       fg='#98C379'
    ble-face -s syntax_quotation    fg='#98C379'
    ble-face -s syntax_varname      fg='#E06C75'
    ble-face -s syntax_param_expansion fg='#E06C75'
    ble-face -s syntax_delimiter    fg='#56B6C2'
    ble-face -s syntax_comment      fg='#5C6370'
    ble-face -s syntax_error        fg='#FF5C70'
    ble-face -s filename_directory  fg='#61AFEF'
    ble-face -s menu_complete_selected bg='#3A1A22'
    ble-face -s region              bg='#3A1A22'
else
    bind '"\e[A": history-search-backward'  2>/dev/null
    bind '"\e[B": history-search-forward'   2>/dev/null
    bind '"\eOA": history-search-backward'  2>/dev/null
    bind '"\eOB": history-search-forward'   2>/dev/null
    bind 'TAB: menu-complete'               2>/dev/null
    bind '"\e[Z": menu-complete-backward'   2>/dev/null
    bind '"\e[18~": clear-screen'           2>/dev/null
    bind -x '"\es": __darth_save_line'      2>/dev/null
fi
__darth_mark 'Key bindings'

# ---------------------------------------------------------------------------
# Oh My Posh
# ---------------------------------------------------------------------------
if __darth_has oh-my-posh && [[ ${TERM:-dumb} != dumb ]]; then
    __darth_theme="${XDG_CONFIG_HOME:-$HOME/.config}/oh-my-posh/$DARTH_POSH_THEME.omp.json"
    [[ -r $__darth_theme ]] || __darth_theme=$DARTH_POSH_THEME
    eval "$(oh-my-posh init bash --config "$__darth_theme" 2>/dev/null)"

    # Oh My Posh keeps PROMPT_COMMAND as an array. Bash older than 5.1 (RHEL 8,
    # Ubuntu 20.04) only runs the first element, so join it into one string.
    if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1) )) &&
       (( ${#PROMPT_COMMAND[@]} > 1 )); then
        __darth_pc=$(IFS=';'; printf '%s' "${PROMPT_COMMAND[*]}")
        unset PROMPT_COMMAND
        # shellcheck disable=SC2178  # deliberately a string on old bash
        PROMPT_COMMAND=$__darth_pc
    fi
fi
__darth_mark 'Oh My Posh'

# ---------------------------------------------------------------------------
# fzf (optional: setup.sh --install-extras)
# ---------------------------------------------------------------------------
# Ctrl+T: pick files into the command line. Ctrl+R: fuzzy history. Alt+C: cd.
if __darth_has fzf; then
    export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height 40% --layout reverse --border --color=bg+:#3A1A22,hl:#E0314B,hl+:#FF5C70,pointer:#E0314B,marker:#E0314B,prompt:#61AFEF,info:#5C6370}"
    if (( __darth_blesh )); then
        ble-import -d integration/fzf-completion
        ble-import -d integration/fzf-key-bindings
    elif __darth_fzf_init=$(fzf --bash 2>/dev/null); then
        eval "$__darth_fzf_init"   # fzf 0.48+; older builds lack --bash and are skipped
    fi
fi
__darth_mark 'fzf'

# ---------------------------------------------------------------------------
# Listings: eza (the Terminal-Icons / PowerColorLS equivalent)
# ---------------------------------------------------------------------------
# Distro .bashrc files define these as aliases; aliases beat functions, and an
# alias would even break the function definitions below. Clear them first.
unalias ls l ll la lt pls 2>/dev/null

if __darth_has eza; then
    DARTH_EZA_OPTS=(--group-directories-first)
    [[ $DARTH_ICONS == 1 ]] && DARTH_EZA_OPTS+=(--icons=auto)

    # eza lists nothing (or waits) when stdin is not a terminal and no path is
    # given, e.g. inside 'watch' or a script. Add '.' in that case.
    __darth_eza() {
        local arg
        if [[ ! -t 0 ]]; then
            for arg in "$@"; do [[ $arg != -* ]] && { command eza "${DARTH_EZA_OPTS[@]}" "$@"; return; }; done
            set -- "$@" .
        fi
        command eza "${DARTH_EZA_OPTS[@]}" "$@"
    }
    function ls  { __darth_eza "$@"; }
    function l   { __darth_eza -a "$@"; }
    function ll  { __darth_eza -l --git "$@"; }
    function la  { __darth_eza -la --git "$@"; }
    function lt  { __darth_eza --tree --level=2 "$@"; }
    function pls { __darth_eza -la --git --header "$@"; }
else
    alias ls='ls --color=auto'
    alias l='ls -CF --color=auto'
    alias ll='ls -l --color=auto'
    alias la='ls -la --color=auto'
    alias pls='ls -la --color=auto'
fi
alias grep='grep --color=auto'
__darth_mark 'Listings'

# ---------------------------------------------------------------------------
# Tab completion for tools that generate their own scripts
# ---------------------------------------------------------------------------
# Generated once and cached; regenerated when the tool binary is newer than the
# cache. Nothing is spawned on a normal start.
__darth_cached_completion() {
    local cmd=$1; shift
    local bin cache
    bin=$(command -v "$cmd" 2>/dev/null) || return 0
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/darthshell/completions/$cmd.bash"
    if [[ ! -s $cache || $bin -nt $cache ]]; then
        if ! { mkdir -p "${cache%/*}" && "$@" > "$cache" 2>/dev/null; }; then
            rm -f "$cache"
            return 0
        fi
    fi
    # shellcheck source=/dev/null
    source "$cache"
}
__darth_cached_completion kubectl  kubectl completion bash
__darth_cached_completion helm     helm completion bash
__darth_cached_completion gh       gh completion -s bash
__darth_cached_completion oh-my-posh oh-my-posh completion bash

if __darth_has dotnet; then
    _darth_dotnet_complete() {
        local cur="${COMP_WORDS[COMP_CWORD]}" IFS=$'\n'
        local candidates
        read -d '' -ra candidates < <(dotnet complete --position "$COMP_POINT" "$COMP_LINE" 2>/dev/null)
        read -d '' -ra COMPREPLY < <(compgen -W "${candidates[*]:-}" -- "$cur")
    }
    complete -f -F _darth_dotnet_complete dotnet
fi
__darth_mark 'Completions'

# ---------------------------------------------------------------------------
# Navigation and file helpers
# ---------------------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'

# Create a folder (and parents) and move into it.
function mkcd {
    [[ $# -eq 1 ]] || { echo 'usage: mkcd <dir>' >&2; return 2; }
    mkdir -p -- "$1" && cd -- "$1" || return
}

# True (exit 0) when running as root.
is-root() { [[ $EUID -eq 0 ]]; }

# Re-run the previous command with sudo.
please() {
    local last
    # -2: the newest history entry is this 'please' itself.
    last=$(HISTTIMEFORMAT='' fc -ln -2 -2 2>/dev/null) || return 1
    last=${last#"${last%%[![:space:]]*}"}
    echo "sudo $last" >&2
    eval "sudo $last"
}

# Unpack most archive types by extension.
extract() {
    [[ -f ${1-} ]] || { echo 'usage: extract <archive>' >&2; return 2; }
    case $1 in
        *.tar.bz2|*.tbz2) tar xjf "$1" ;;
        *.tar.gz|*.tgz)   tar xzf "$1" ;;
        *.tar.xz|*.txz)   tar xJf "$1" ;;
        *.tar.zst)        tar --zstd -xf "$1" ;;
        *.tar)            tar xf "$1" ;;
        *.bz2)            bunzip2 "$1" ;;
        *.gz)             gunzip "$1" ;;
        *.xz)             unxz "$1" ;;
        *.zip)            unzip "$1" ;;
        *.7z)             7z x "$1" ;;
        *) echo "extract: don't know how to unpack '$1'" >&2; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Server helpers
# ---------------------------------------------------------------------------
# One-screen summary of this machine. Runs only when you call it.
sysinfo() {
    local os kernel up load mem disk ips
    # shellcheck source=/dev/null
    os=$( . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}" )
    kernel=$(uname -r)
    up=$( { uptime -p || uptime; } 2>/dev/null )
    load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
    mem=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " used / " $2}')
    disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " used / " $2 " (" $5 ")"}')
    ips=$( { hostname -I || ip -o -4 addr show scope global | awk '{print $4}'; } 2>/dev/null | xargs)
    printf '%-9s %s\n' Host "${HOSTNAME:-unknown}" OS "$os" Kernel "$kernel" Uptime "${up:-n/a}" \
        Load "${load:-n/a}" Memory "${mem:-n/a}" 'Disk /' "${disk:-n/a}" IPs "${ips:-n/a}"
    [[ -n ${WSL_DISTRO_NAME-} ]] && printf '%-9s %s\n' WSL "$WSL_DISTRO_NAME"
    return 0
}

# Listening TCP/UDP ports and the processes behind them.
ports() {
    if __darth_has ss; then
        if is-root; then ss -tulpn; else ss -tuln; echo '(run as root to see process names)' >&2; fi
    else
        netstat -tuln 2>/dev/null || echo 'ports: neither ss nor netstat is installed' >&2
    fi
}

# ---------------------------------------------------------------------------
# Microsoft 365 / Entra helpers
# ---------------------------------------------------------------------------
__darth_b64url_decode() {
    local s=${1//-/+}
    s=${s//_//}
    case $(( ${#s} % 4 )) in 2) s+='==' ;; 3) s+='=' ;; esac
    printf '%s' "$s" | base64 -d 2>/dev/null
}

# Decode a JWT (access or ID token). Reads the token from an argument or stdin.
# Decodes only: the signature is NOT validated.
jwt-decode() {
    local token=${1-}
    [[ -n $token ]] || token=$(cat)
    token=${token#Bearer }
    token=${token//[[:space:]]/}
    local header payload rest
    IFS=. read -r header payload rest <<< "$token"
    [[ -n $payload ]] || { echo 'jwt-decode: that does not look like a JWT' >&2; return 1; }

    local h p
    h=$(__darth_b64url_decode "$header")
    p=$(__darth_b64url_decode "$payload")

    if __darth_has jq; then
        jq -n --argjson h "$h" --argjson p "$p" '
            $p
            + (if $p.exp then {expLocal: ($p.exp | strflocaltime("%Y-%m-%d %H:%M:%S %Z")),
                               isExpired: ($p.exp < now)} else {} end)
            + (if $p.iat then {iatLocal: ($p.iat | strflocaltime("%Y-%m-%d %H:%M:%S %Z"))} else {} end)
            + {_header: $h}'
    else
        printf '%s\n%s\n' "$h" "$p"
    fi
}

# Look up the Entra tenant ID, region and cloud for a domain, anonymously.
entra-tenant() {
    [[ -n ${1-} ]] || { echo 'usage: entra-tenant <domain>' >&2; return 2; }
    local json
    json=$(curl -fsS --max-time 10 "https://login.microsoftonline.com/$1/v2.0/.well-known/openid-configuration") ||
        { echo "entra-tenant: no Entra tenant found for '$1'" >&2; return 1; }
    if __darth_has jq; then
        jq --arg d "$1" '{Domain: $d,
                          TenantId: (.issuer | capture("microsoftonline.com/(?<id>[^/]+)/").id),
                          RegionScope: .tenant_region_scope,
                          CloudInstance: .cloud_instance_name}' <<< "$json"
    else
        grep -o '"issuer":"[^"]*"' <<< "$json"
    fi
}

# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------
wanip() { curl -fsS --max-time 5 https://ifconfig.me/ip && echo; }

# Bandwidth test with the official Ookla CLI (setup.sh --install-extras).
speedtest-run() {
    if __darth_has speedtest; then
        speedtest --accept-license --accept-gdpr "$@"
    else
        echo 'speedtest-run: Ookla Speedtest CLI not found. Run setup.sh --install-extras.' >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# WSL helpers
# ---------------------------------------------------------------------------
if [[ -n ${WSL_DISTRO_NAME-} ]]; then
    # Open a file, folder or URL with Windows.
    open() { explorer.exe "$(wslpath -w "${1:-.}")" 2>/dev/null; return 0; }
    # Copy stdin to / paste from the Windows clipboard.
    alias clip='clip.exe'
    alias pbcopy='clip.exe'
    alias pbpaste='powershell.exe -NoProfile -Command Get-Clipboard | tr -d "\r"'
    # Jump to your Windows user folder.
    winhome() {
        local p
        p=$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')") && cd "$p" || return
    }
fi

# ---------------------------------------------------------------------------
# Profile helpers
# ---------------------------------------------------------------------------
edit-profile() {
    "${VISUAL:-${EDITOR:-$(command -v nano || command -v vi)}}" "$DARTHSHELL_HOME/local.bash"
}

# Startup cost of this profile. --breakdown shows per-section timings from the
# current session (bash 5+).
profile-load-time() {
    if [[ ${1-} == --breakdown ]]; then
        if (( ${#DARTH_LOAD_SECTIONS[@]} == 0 )); then
            echo 'No timings recorded (needs bash 5 or newer).' >&2
            return 1
        fi
        local i
        for i in "${!DARTH_LOAD_SECTIONS[@]}"; do
            printf '%-16s %5s ms\n' "${DARTH_LOAD_SECTIONS[$i]}" "${DARTH_LOAD_MS[$i]}"
        done
        return 0
    fi
    local n=${1:-3} i start end with=0 without=0
    for ((i = 0; i < n; i++)); do
        start=${EPOCHREALTIME//[!0-9]/}; bash -i -c exit </dev/null >/dev/null 2>&1; end=${EPOCHREALTIME//[!0-9]/}
        with=$(( with + (end - start) / 1000 ))
        start=${EPOCHREALTIME//[!0-9]/}; bash --norc -i -c exit </dev/null >/dev/null 2>&1; end=${EPOCHREALTIME//[!0-9]/}
        without=$(( without + (end - start) / 1000 ))
    done
    printf 'With profile    : %s ms\nWithout profile : %s ms\nProfile cost    : %s ms\n' \
        $(( with / n )) $(( without / n )) $(( (with - without) / n ))
}

# List what this profile adds.
darth-help() {
    cat <<'HELP'
Command              PowerShell name        What it does
-------------------  ---------------------  ---------------------------------------------
pls / ll / la / lt   pls                    Listings with icons and git status (eza)
mkcd <dir>           mkcd                   Create a folder and move into it
.. / ...             .. / ...               Up one or two folders
is-root              Test-IsAdmin           Exit 0 when running as root
please                                      Re-run the previous command with sudo
extract <archive>                           Unpack any common archive
sysinfo                                     One-screen machine summary
ports                                       Listening ports (processes when root)
jwt-decode [token]   ConvertFrom-Jwt        Decode an access/ID token (reads stdin too)
entra-tenant <dom>   Get-EntraTenantId      Tenant ID, region and cloud for a domain
wanip                Get-WanIp              Public IP address
speedtest-run        Start-Speedtest        Bandwidth test (Ookla CLI)
edit-profile         Edit-Profile           Open ~/.config/darthshell/local.bash
profile-load-time    Get-ProfileLoadTime    Startup cost; --breakdown per section
darth-help           Get-ProfileCommand     This list

WSL only: open, clip / pbcopy, pbpaste, winhome

Keys: Up/Down history search - Tab menu complete - F7 clear screen
      Alt+S save line to history without running it
      Right arrow accepts the grey suggestion (ble.sh)
      Ctrl+T files - Ctrl+R history - Alt+C cd (fzf)
HELP
}

# The PowerShell names from the Windows profile, for muscle memory.
alias Test-IsAdmin='is-root'
alias ConvertFrom-Jwt='jwt-decode'
alias Get-EntraTenantId='entra-tenant'
alias Get-WanIp='wanip'
alias Start-Speedtest='speedtest-run'
alias Edit-Profile='edit-profile'
alias Get-ProfileLoadTime='profile-load-time'
alias Get-ProfileCommand='darth-help'

__darth_mark 'Functions'

# ---------------------------------------------------------------------------
# Finish
# ---------------------------------------------------------------------------
# Define darthshell_post in local.bash to run your own code after everything.
if declare -F darthshell_post >/dev/null; then darthshell_post; fi

unset __darth_f __darth_theme __darth_pc __darth_fzf_init
unset -f __darth_join_ignore

# ble.sh must attach last.
if (( __darth_blesh )) && [[ -n ${BLE_VERSION-} ]]; then
    ble-attach
fi
