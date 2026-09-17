# Bash Setup for Linux Servers & WSL

The Bash twin of [TheDarthAdmin/Powershell](https://github.com/TheDarthAdmin/Powershell):
the same prompt, colours, key bindings and helpers, for Linux servers and WSL.

- **Oh My Posh** with the `darthadmin` theme (the same prompt as in PowerShell),
  stored locally so it works offline
- **ble.sh** for grey inline suggestions from history and syntax highlighting,
  the Bash equivalent of PSReadLine predictions
- **eza** listings with icons and git status (Terminal-Icons / PowerColorLS)
- **fzf** fuzzy search for files and history (optional)
- **History hygiene**: tokens, passwords, secrets and bearer headers never reach
  `~/.bash_history`
- Microsoft 365 helpers (`jwt-decode`, `entra-tenant`), server helpers
  (`sysinfo`, `ports`, `please`) and WSL helpers (`open`, `clip`, `winhome`)

The setup is safe to run more than once. It skips what is already in place and
backs up any file it changes.

---

## Requirements

| | |
|---|---|
| Distros | Ubuntu 20.04+, Debian 11+, RHEL / Rocky / AlmaLinux 8+, Fedora |
| CPU | x86_64 or aarch64 |
| Shell | Bash 4.4+ |
| Rights | `sudo` only for missing distro packages; everything else installs in your home folder |

---

## Install

On a server or in WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/TheDarthAdmin/Bash-Setup/main/setup.sh | bash
exec bash
```

With options:

```bash
curl -fsSL https://raw.githubusercontent.com/TheDarthAdmin/Bash-Setup/main/setup.sh | bash -s -- --install-extras
```

Or from a clone:

```bash
git clone git@github.com:TheDarthAdmin/Bash-Setup.git
cd Bash-Setup
./setup.sh --dry-run   # see the plan first
./setup.sh
```

> Piping a script from the internet into `bash` runs whatever is at that URL.
> Read it first — that goes for this one too. The script only runs once it has
> been downloaded completely, so a dropped connection cannot run half of it.

Run it once per user account. For root, run it from a root shell (`sudo -i`).

### Options

| Option | Effect |
|---|---|
| `-n`, `--dry-run` | Show what would happen without changing anything |
| `--diagnose` | Print detected distro, tools and files, then exit |
| `--install-extras` | Also install fzf and the Ookla Speedtest CLI |
| `--install-font` | Install Hack Nerd Font (Linux desktops only, see below) |
| `--update` | Re-download Oh My Posh, eza, fzf, ble.sh and the theme |
| `--theme <name>` | Oh My Posh theme to store locally (default `darthadmin`; built-in names like `kali` work too) |
| `--branch <name>` | Branch to download repo files from (default `main`) |
| `--skip-packages` | Do not touch distro packages (no sudo needed) |
| `--skip-tools` | Do not install the Oh My Posh / eza / fzf binaries |
| `--skip-blesh` | Do not install ble.sh |
| `--uninstall` | Remove the hook from `~/.bashrc` (files are kept) |

---

## What gets installed where

| What | Where |
|---|---|
| Distro packages (only missing ones) | `curl git jq tar xz gawk unzip bash-completion` and basics |
| Oh My Posh, eza, fzf, speedtest | `~/.local/bin` |
| ble.sh | `~/.local/share/blesh` |
| Theme | `~/.config/oh-my-posh/darthadmin.omp.json` |
| Profile | `~/.config/darthshell/darthshell.bash` |
| Your settings (never overwritten) | `~/.config/darthshell/local.bash` |
| Hook | a marked block at the end of `~/.bashrc` |

Oh My Posh and fzf are checked against their published SHA-256 checksums. eza
uses a static build on x86_64 so it also runs on RHEL 8's older glibc. If a
tool is already installed system-wide, the setup leaves it alone.

Login shells (SSH, WSL) read `~/.bash_profile` first. If yours does not load
`~/.bashrc`, the setup adds the line that does.

---

## The profile

Same house rules as the PowerShell profile: it never breaks the shell, never
installs anything, never touches the network at startup, and prints nothing on
a normal start. Without a real terminal (`scp`, scripts, CI) ble.sh is skipped
automatically.

### Prompt

The `darthadmin` theme in `themes/` is shared with the PowerShell repo:

```
┌──(sdg💀MSI)-[~/projects]-[main]                    12ms  
└─$
```

A normal user gets a blue frame with a red name and `$`. As root the whole
frame turns red, the name goes bold and the prompt ends in `#`, so an elevated
shell is impossible to miss. Colours are fixed hex values, so the prompt looks
the same in any terminal.

### Keys

| Key | Action |
|---|---|
| `↑` / `↓` | Search history for what you have already typed |
| `→` | Accept the grey suggestion (ble.sh) |
| `Tab` | Completion menu |
| `F7` | Clear screen |
| `Alt+S` | Save the current line to history without running it |
| `Ctrl+T` / `Ctrl+R` / `Alt+C` | fzf: files, history, cd (with `--install-extras`) |

### Commands

Run `darth-help` for the live list. The PowerShell names from the Windows
profile work as aliases too.

| Command | PowerShell name | What it does |
|---|---|---|
| `pls`, `ll`, `la`, `lt`, `l` | `pls` | Listings with icons and git status |
| `mkcd <dir>` | `mkcd` | Create a folder and move into it |
| `..`, `...` | `..`, `...` | Up one or two folders |
| `is-root` | `Test-IsAdmin` | Exit 0 when running as root |
| `please` | | Re-run the previous command with sudo |
| `extract <archive>` | | Unpack any common archive |
| `sysinfo` | | One-screen summary: OS, kernel, uptime, load, memory, disk, IPs |
| `ports` | | Listening ports (with processes when root) |
| `jwt-decode [token]` | `ConvertFrom-Jwt` | Decode an access/ID token; reads stdin too |
| `entra-tenant <domain>` | `Get-EntraTenantId` | Tenant ID, region and cloud for a domain |
| `wanip` | `Get-WanIp` | Public IP address |
| `speedtest-run` | `Start-Speedtest` | Bandwidth test (Ookla CLI) |
| `edit-profile` | `Edit-Profile` | Open your `local.bash` |
| `profile-load-time` | `Get-ProfileLoadTime` | Startup cost; `--breakdown` per section |
| `darth-help` | `Get-ProfileCommand` | List all of the above |

WSL only: `open <path|url>`, `clip` / `pbcopy`, `pbpaste`, `winhome`.

Examples:

```bash
entra-tenant contoso.com
az account get-access-token --query accessToken -o tsv | jwt-decode | jq '{aud, scp, roles, expLocal, isExpired}'
sysinfo
```

`jwt-decode` decodes only; it does not validate the signature.

### History hygiene

Commands matching these patterns are never saved to history, in both ble.sh
and plain readline mode: `--password`, `--secret`, `--client-secret`,
`--token`, `--api-key` (and variants), `*PASSWORD*=`, `*SECRET*=`, `*TOKEN*=`,
`*API_KEY*=` assignments, JWTs, Azure SAS signatures, `AccountKey=`, bearer
headers and `sshpass -p`. Starting a command with a space also keeps it out.

History is written after every command, so tmux panes and parallel SSH
sessions do not lose each other's commands.

---

## WSL and Windows Terminal

In WSL the colour scheme, font and background come from Windows Terminal, not
from Linux. Run the [Windows setup](https://github.com/TheDarthAdmin/Powershell)
once: besides the Hack Nerd Font it gives every WSL profile the DarthAdmin
colour scheme and the same background as the PowerShell tabs. That matters
because the Ubuntu and Debian packages ship their own Terminal colour scheme,
which would otherwise win.

The profile also tells Windows Terminal your current folder, so **Duplicate
tab** and new panes open where you are.

### Over SSH

The font lives on the machine you type on. Windows Terminal with Hack Nerd Font
shows the icons on any server you SSH into. From a client without a Nerd Font,
set `DARTH_ICONS=0` in `local.bash`. `--install-font` is only useful on a Linux
desktop.

---

## Customising

Edit `~/.config/darthshell/local.bash` (`edit-profile`). It is loaded before
the profile, so settings there win, and updates never touch it.

```bash
DARTH_POSH_THEME=darthadmin                          # then: setup.sh --theme <name>
DARTH_BLESH=0                                        # plain readline, no ble.sh
DARTH_ICONS=0                                        # no icons in listings
DARTH_HISTORY_EXTRA_IGNORE=('*my-tool --key*')       # more history patterns

darthshell_post() {                                  # your own aliases and functions
    alias k='kubectl'
}
```

---

## Updating, rolling back, uninstalling

```bash
./setup.sh --update        # latest tools, ble.sh, theme, and this repo's profile
./setup.sh --uninstall     # remove the ~/.bashrc hook
```

Every file the setup changes is kept next to the original as
`<file>.bak-<timestamp>`:

```bash
ls ~/.bashrc.bak-* ~/.config/darthshell/*.bak-*
```

---

## Troubleshooting

Start with `./setup.sh --diagnose`.

**Boxes or question marks in the prompt.** Your terminal is not using a Nerd
Font. In Windows Terminal set the font to `Hack Nerd Font`.

**No prompt, just `$`.** Check `oh-my-posh` is on your PATH in a new shell and
that `~/.bashrc` still ends with the darthshell block.

**No grey suggestions.** Check `echo $BLE_VERSION` prints a version. ble.sh
needs a real terminal, so it stays off in `bash -c`, scripts and `scp`.

**Slow start.** `profile-load-time --breakdown` shows which part costs most
(Bash 5+).

**Package installation fails on apt.** A broken third-party repository makes
`apt-get update` fail; the setup warns and tries the install anyway. Fix or
remove the broken repository, or use `--skip-packages`.

---

## Development

```bash
shellcheck setup.sh darthshell.bash config/local.bash.example
```

Every push runs ShellCheck and a full install on Ubuntu 22.04 and 24.04,
Debian 12, Fedora, Rocky Linux 9 and AlmaLinux 8, including a second run to
check nothing reinstalls.

---

## Licence

MIT — see [`LICENSE`](LICENSE).
