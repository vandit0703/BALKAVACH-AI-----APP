# Production SSH credential exposure: finding and remediation plan

**Status: plan only. No connection to any server was made and no credential, key, firewall or server setting was changed.**
Every step below needs the owner's explicit authorisation and is to be run by the owner (or by me only if told to, step by step).

## 1. What was found (local files only)

| Item | Where | Why it matters |
|---|---|---|
| `notes.txt` and `servecmd.txt` at the repository root contain a pasted terminal transcript of an interactive **`root` login with a password** to an Ubuntu 24.04 server (host IP, host-key fingerprint, the `root@host` prompt and a file listing). The password itself is not echoed in the transcript, but the **login method and target are**. | repository root (both files are in `.gitignore`) | A password-authenticated `root` login means the host accepts password logins for root: the highest-value brute-force/credential-stuffing target. The transcript also gives an attacker the IP and confirms what is there (`balkavach-backup`). |
| The same host shows "2 updates / 3 security updates available" and "System restart required". | transcript | The server is behind on patches. |
| The files are untracked/ignored, so they are **not** in Git history as far as `git ls-files` shows. | `git ls-files` | Verified for the current tree; **history was not scanned**. |

Not found: an actual password, private key or token value in either file (the password prompt shows no value).
This was verified by reading both files with values redacted; contents are not reproduced here on purpose.

## 2. Immediate, low-risk actions (no server access needed)

1. **Delete or move `notes.txt` and `servecmd.txt` out of the repository folder** (they are scratch notes; `servecmd.txt` is only a terminal paste). Keep the `.gitignore` entries.
2. Treat the host IP and fingerprint as known to anyone who has seen these files (shared screens, backups, cloud-synced folders, AI-assistant sessions). Check where this working folder is synced or backed up.
3. Scan Git **history** for the same content before anyone pushes or shares the repository:
   `git log --all --full-history -- notes.txt servecmd.txt` and `git grep -n "ssh root@" $(git rev-list --all)` (read-only).
4. Confirm whether the password used in that session was reused anywhere else.

## 3. Server hardening plan (requires your authorisation; run on the server)

Order matters so you cannot lock yourself out. Keep one root session open until the last step succeeds.

1. **Back up first** (you already have `balkavach-backup`); take a provider snapshot if available.
2. **Create a named admin user** with sudo and **SSH key authentication**:
   `adduser deploy && usermod -aG sudo deploy`; add your public key to `/home/deploy/.ssh/authorized_keys` (mode 0600, dir 0700). Use an `ed25519` key protected by a passphrase.
3. **Test** a second terminal: `ssh deploy@host` with the key, then `sudo -v`.
4. **Disable root and password logins** in `/etc/ssh/sshd_config.d/99-hardening.conf`:
   ```
   PermitRootLogin no
   PasswordAuthentication no
   KbdInteractiveAuthentication no
   PubkeyAuthentication yes
   MaxAuthTries 3
   LoginGraceTime 20
   ```
   `sshd -t` to validate, then `systemctl reload ssh`. Keep the existing session open and test a fresh login before closing it.
5. **Rotate the root password** (`passwd root`) to a long random value stored in a password manager, even though root login is now disabled; lock it if not needed (`passwd -l root`).
6. **Firewall**: `ufw default deny incoming`, allow only required ports (SSH from your IP range if static, 443/80 if the host serves HTTP). Install `fail2ban` (sshd jail) as defence in depth.
7. **Patch**: `apt update && apt upgrade`, then schedule the pending reboot in a maintenance window; enable `unattended-upgrades` for security updates.
8. **Audit**: check `last`, `/var/log/auth.log` (and `journalctl -u ssh`) for unknown successful logins or repeated failures; review `~/.ssh/authorized_keys` for every account; check for unexpected cron jobs/users/listening ports (`ss -tlnp`).
9. **Secrets on the host**: move service credentials into root-owned `0600` env files used by systemd (`EnvironmentFile=`); never store them in the home directory or shell history. Rotate any secret that was ever pasted into that host's shell history or this repository's notes.
10. **Record** the new access procedure in the team runbook (who has keys, how to revoke).

## 4. If the API is on Render instead

If production traffic is served by Render (`docs/youtube-operations.md` says so), this VPS may be a backup or an old host. Decide whether it is still needed; if not, **decommission it** (export the backup, destroy the instance) instead of hardening an unused target.

## 5. What I will and will not do

* I will not connect to the host, change any credential or run any command there without your explicit instruction.
* I can prepare ready-to-paste command blocks, a short runbook, and a Git-history scan script on request.
* Open question for you: is this VPS production, staging, a backup box, or retired?
