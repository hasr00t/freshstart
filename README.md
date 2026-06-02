# setup

Provision a fresh Kali Linux VM (built for Parallels) into a ready-to-use pentesting workstation with a single script. It updates the system, installs prerequisites, clones and auto-builds a curated set of offensive-security tools from GitHub, installs a handful of packages from `apt`, and sets up a few extras.

## What it does

The script runs in six phases:

1. **VM update** — `apt-get update` + `full-upgrade`. Fatal on failure.
2. **Prerequisites** — installs build/runtime dependencies (`git`, `golang`, `python3-venv`, `build-essential`, `mingw-w64`, etc.). Fatal on failure.
3. **Workspace** — creates `/opt/tools` and configures `GOPATH`/`GOBIN` under `/root/go`.
4. **GitHub tools** — clones (or `git pull`s) ~37 repos into `/opt/tools` and auto-detects how to build each one.
5. **apt tools** — installs `nuclei`, `feroxbuster`, `eyewitness`, `certipy-ad`, `bloodhound`, and `responder`.
6. **Extras** — `pcapy-ng` (in a dedicated venv for PCredz), an impacket fork (`pr_SystemDPAPIdump` branch), and Tailscale via the official installer.

### Auto-build detection

For each cloned repo, the build type is detected in this order, and the first match wins:

| File present | Action |
|---|---|
| `pyproject.toml` | venv + `pip install .` |
| `setup.py` | venv + `pip install .` |
| `requirements.txt` | venv + `pip install -r requirements.txt` |
| `go.mod` | `go build ./...` |
| `Makefile` | `make` |
| none | clone only |

Python tools each get their own `.venv` inside the repo directory, so dependencies stay isolated.

## Requirements

- A Kali Linux VM (designed and tested on Parallels, but the script is distro-agnostic Debian/Kali).
- Root privileges.
- Internet access.

## Usage

```bash
sudo ./kali-setup.sh
```

The script is idempotent: re-running it `git pull`s existing repos instead of re-cloning and skips work that's already done.

## Logs

| Path | Contents |
|---|---|
| `/var/log/kali-setup.log` | Full transcript of every step. |
| `/var/log/kali-setup-failures.log` | Just the failures, with the failing step and exit code. |

Both logs are truncated at the start of each run. A summary is printed at the end showing how many GitHub repos, apt packages, and extras succeeded or failed. Per-tool failures are non-fatal — the script keeps going and reports them at the end. Only the update, prerequisite, and workspace phases abort on failure.

## Included tools

Cloned from GitHub into `/opt/tools`:

- **Coercion / relay**: mitm6, PetitPotam, Coercer, pretender, WebclientServiceScanner
- **AD enumeration / attack**: ldapdomaindump, FindUncommonShares, AD_Miner, PlumHound, ADScan, sccmhunter, pre2k, PKINITtools, GPOddity, Misconfiguration-Manager
- **Credential / share hunting**: DonPAPI, PowerHuntShares, snafflepy, manspider, DPAT
- **Cloud / identity**: ntlmscan, FindMeAccess, MFASweep, GraphRunner
- **Payloads / evasion**: Talon, PowerLessShell, Mangle, ScareCrow, Ivy
- **Recon / scanning**: testssl.sh, nikto, rdp-sec-check, eavesarp-ng, icmp-timestamp, pxethiefy
- **Wordlists**: SecLists
- **Kerberos**: kerbrute

From `apt`: nuclei, feroxbuster, eyewitness, certipy-ad, bloodhound, responder.

## Legal

Intended for authorized security testing, lab use, and education only. Use these tools only against systems you own or have explicit written permission to test.
