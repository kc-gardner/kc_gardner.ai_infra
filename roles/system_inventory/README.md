# system_inventory

Collects hardware, OS and health data from each host and writes two reports on the controller:

| File | Contents |
| --- | --- |
| `inventory.json` | Everything collected, one object per host, sorted by host name |
| `inventory.csv` | One row per host with the summary columns, for a spreadsheet |

The role changes nothing on the managed hosts. It runs on RHEL 9 and 10 and Fedora; other Linux hosts work but the dnf checks are skipped.

## What it collects

- **System:** OS, version, kernel, architecture, time zone; vendor, model, serial and BIOS version; virtualization role (host or guest) and type
- **CPU and memory:** CPU model, sockets, cores per socket, vCPUs; RAM and swap
- **Storage:** each mounted filesystem's device, type, size, free space and percent used (types in `system_inventory_exclude_fstypes` are skipped)
- **Network:** default IPv4 address, interface and MAC; all IPv4 addresses
- **Health:** uptime and last boot (UTC), SELinux mode, firewalld state, failed systemd units, installed package count, pending updates, and whether a reboot is needed (`dnf needs-restarting -r`)

Every health check is best-effort. When a check can't run, the field reads `unknown`, `n/a` or `not checked` instead of failing the host. An unregistered RHEL host, for example, can't reach its repos, so its update count is `unknown`.

## Variables

See [defaults/main.yaml](defaults/main.yaml), or `ansible-doc -t role kc_gardner.ai_infra.system_inventory`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `system_inventory_report_dir` | `$PWD/reports/system_inventory` | Where the reports are written on the controller |
| `system_inventory_check_updates` | `true` | Count pending updates. Reads repo metadata, so it is the slowest check. |
| `system_inventory_collect_packages` | `true` | Count installed packages |
| `system_inventory_exclude_fstypes` | `[tmpfs, devtmpfs, squashfs, overlay, iso9660]` | Filesystem types left out of the report |
| `system_inventory_gather_timeout` | `30` | Seconds allowed for fact gathering per host |

Each host's record is also left in `system_inventory_record`, so later plays can use it.

## Notes

- Both reports are rewritten on every run with only the hosts in that run. A run with `--limit` or `-e target=` replaces the full report with that subset.
- Run with `become: true`: the serial number and BIOS facts need root.
- Keep `reports/` out of git: the reports list serial numbers and addresses.
- In AAP the default directory is inside the execution environment and is discarded with it. Set `system_inventory_report_dir` to a path mounted into the execution environment.

## Example

[playbooks/gather_system_inventory.yaml](../../playbooks/gather_system_inventory.yaml):

```yaml
- name: Collect system inventory
  hosts: "{{ target | default('all') }}"
  become: true
  gather_facts: false   # the role gathers the subsets it needs

  roles:
    - kc_gardner.ai_infra.system_inventory
```

```bash
ansible-playbook playbooks/gather_system_inventory.yaml
ansible-playbook playbooks/gather_system_inventory.yaml -e target=dns01
ansible-playbook playbooks/gather_system_inventory.yaml -e system_inventory_check_updates=false
```
