# ubuntu_updates

Keeps Ubuntu servers updated: installs either every available update or only security updates, reports what changed, and optionally reboots.
It also manages unattended-upgrades, Ubuntu's built-in automatic updates.

## Coming from RHEL

| RHEL | Ubuntu | In this role |
| --- | --- | --- |
| `dnf check-update` | `apt update && apt list --upgradable` | check mode (`--check`) |
| `dnf update` | `apt full-upgrade` | `ubuntu_updates_type: all` |
| `dnf update --security` | `unattended-upgrade` limited to the `-security` pocket | `ubuntu_updates_type: security` |
| `needs-restarting -r` | `/var/run/reboot-required` exists | always checked; `ubuntu_updates_reboot` acts on it |
| `dnf-automatic` | unattended-upgrades and the `apt-daily` timers | `ubuntu_updates_automatic` |
| `dnf versionlock` / `exclude=` | `apt-mark hold` | not managed; `ubuntu_updates_unattended_blacklist` covers unattended runs |

apt has no `--security` flag. Ubuntu ships security fixes in a separate pocket (`noble-security`), and `unattended-upgrade` is the supported way to install only those, taking the dependencies they need from the right places.
Unlike RHEL, Ubuntu Server installs security updates automatically every day by default. This role keeps that on unless you turn it off.

## What it does

- Checks that the host is Ubuntu and the settings are valid
- Installs `unattended-upgrades` and writes two files in `/etc/apt/apt.conf.d`:
  - `20auto-upgrades`: turns the daily automatic runs on or off
  - `52ansible-unattended-upgrades`: which origins and packages the unattended runs may touch, automatic reboots and mail reports. The package's own `50unattended-upgrades` is left alone; this file replaces its lists.
- Refreshes the package lists if they are older than `ubuntu_updates_cache_valid_time`
- Installs updates:
  - `all`: `apt-get dist-upgrade` (`full-upgrade`), or `apt-get upgrade` with `ubuntu_updates_upgrade: safe`
  - `security`: `unattended-upgrade --verbose`, which only installs from `ubuntu_updates_unattended_origins`
- Removes packages no longer needed (`apt autoremove`), including old kernels
- Lists the packages it updated
- Reports whether a reboot is required and which packages need it, and reboots when `ubuntu_updates_reboot` is true

Waits up to `ubuntu_updates_lock_timeout` seconds when the `apt-daily` timers are already running apt, which is common on freshly booted hosts.

## Variables

See [defaults/main.yaml](defaults/main.yaml).

| Variable | Default | Purpose |
| --- | --- | --- |
| `ubuntu_updates_type` | `all` | `all` or `security` |
| `ubuntu_updates_upgrade` | `dist` | For `all`: `dist` (`full-upgrade`, can add and remove packages) or `safe` (`upgrade`, never removes, may hold some updates back) |
| `ubuntu_updates_autoremove` | `true` | Remove unneeded packages and old kernels |
| `ubuntu_updates_reboot` | `false` | Reboot when an update requires it |
| `ubuntu_updates_reboot_timeout` | `600` | Seconds to wait for the host to come back |
| `ubuntu_updates_cache_valid_time` | `3600` | Skip `apt update` if the lists are newer than this |
| `ubuntu_updates_lock_timeout` | `300` | Seconds to wait for another apt run to finish |
| `ubuntu_updates_unattended_origins` | `-security` and the Ubuntu Pro ESM security pockets | Origins for `security` runs and automatic runs |
| `ubuntu_updates_unattended_blacklist` | `[]` | Regular expressions for packages the unattended runs skip |
| `ubuntu_updates_automatic` | `true` | Daily automatic updates |
| `ubuntu_updates_automatic_reboot` / `_time` | `false` / `02:00` | Let the automatic runs reboot, and when |
| `ubuntu_updates_mail` | `""` | Mail the automatic runs' reports here; needs a working MTA |
| `ubuntu_updates_mail_report` | `on-change` | `on-change`, `only-on-error` or `always` |

`ubuntu_updates_unattended_origins` is shared by `security` runs and automatic runs. To have both include bug-fix updates as well, add `"${distro_id}:${distro_codename}-updates"`.

## Usage

```yaml
- hosts: ubuntu
  become: true
  roles:
    - role: kc_gardner.ai_infra.ubuntu_updates
```

Security updates only, rebooting if needed, a few hosts at a time:

```yaml
- hosts: ubuntu
  become: true
  serial: 2
  roles:
    - role: kc_gardner.ai_infra.ubuntu_updates
      ubuntu_updates_type: security
      ubuntu_updates_reboot: true
```

To see what would be updated without changing anything, run with `--check`.
For `security` this runs `unattended-upgrade --dry-run`.

## Notes

- `unattended-upgrade` skips a package whose update would ask about a changed configuration file. Run with `ubuntu_updates_type: all` to install it; apt keeps your version of the file.
- Ubuntu phases some updates, releasing them to a growing share of machines over a few days. apt holds a phased update back on hosts not yet in the rollout, so hosts may get the same update on different days.
- Services still running old libraries after an update are handled by `needrestart`, which Ubuntu runs after apt. Kernel and core library updates need a reboot, which the role reports.

## Testing

Run on Ubuntu 24.04 and Ubuntu 26.04 (a KVM guest), including a reboot.
Not tested on 22.04.

A KVM guest made by the `kvm_guest` role powers off instead of rebooting the first time it reboots after creation, because `virt-install --cloud-init` starts it with `on_reboot=destroy`. Start it again and later reboots work normally.
