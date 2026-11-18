# gpustack

Runs the [GPUStack](https://docs.gpustack.ai/) server on one host in a rootless Podman container that the owning user's systemd manages through [Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html).

Nothing of GPUStack runs as root. The container belongs to an unprivileged user (`gpustack` by default), root inside the container is that user outside it, and the image and data sit under the user's home.

This is the server only: the UI, the API, the gateway and the embedded PostgreSQL, all in the one `gpustack/gpustack` image. It serves no models itself. Workers on the GPU hosts do that, see [Workers](#workers).

## What it does

- Checks the operating system and the variables
- Installs Podman and checks it is version 4.4 or later
- Creates `gpustack_user` if it does not exist, checks it has subordinate UIDs and GIDs, and enables lingering so its services run without a login and start at boot
- Opens `gpustack_port` in firewalld when firewalld is running
- Writes `~/.config/gpustack/gpustack.env` (readable by the user only) and the Quadlet units `gpustack.container` and `gpustack-data.volume` in `~/.config/containers/systemd`, and checks that Podman's generator accepts them
- Pulls the image into the user's image store if it is missing
- Starts `gpustack.service` in the user's systemd, restarting it only when the units or the environment changed
- Checks the service is active and the UI answers on `gpustack_port`

## Ports

A rootless container cannot publish a port below 1024, so the UI is on 8080 by default. The container still listens on 80 inside.

To use port 80, set `gpustack_port: 80`. The role then lowers `net.ipv4.ip_unprivileged_port_start` to 80 in `/etc/sysctl.d/90-gpustack.conf`, which lets every user on the host bind ports from 80 up.

## Working with the service

It is a user service, so root's `systemctl status gpustack` does not see it. From an account with sudo:

```bash
sudo systemctl --user -M gpustack@ status gpustack
```

```bash
sudo journalctl _SYSTEMD_USER_UNIT=gpustack.service -f
```

```bash
sudo -iu gpustack podman logs -f gpustack
```

```bash
sudo -iu gpustack podman exec gpustack cat /var/lib/gpustack/initial_admin_password
```

The last one shows the generated `admin` password, when `gpustack_bootstrap_password` was left empty. `sudo -iu gpustack systemctl --user ...` does not work: sudo opens no login session, so there is no bus to reach the user's systemd through.

## Taking over an existing install

Set `gpustack_user` to the user that already runs GPUStack under rootless Podman. The role replaces that user's `gpustack.container` and keeps using the `gpustack-data` volume, so clusters, workers and models carry over. The service restarts, and moves to `gpustack_version` if the old unit ran another one.

## Upgrades

Change `gpustack_version` and rerun. The container is recreated from the new image and migrates its database when it starts. Going back to an older image is not a rollback: the database has already been migrated. Back up the volume first; the role does not.

```bash
sudo -iu gpustack podman volume export gpustack-data -o gpustack-data.tar
```

## Workers

The role does not set up workers. In the GPUStack UI, add a worker to a cluster and run the command it shows on the GPU host. On DGX OS (DGX Spark and other GB10 machines) the worker's `--runtime nvidia` needs the [nvidia_docker_runtime](../nvidia_docker_runtime/README.md) role first.

The worker must reach the server on `gpustack_port`, and the server must reach the worker on 10150.

## Variables

See [defaults/main.yaml](defaults/main.yaml).

| Variable | Default | Purpose |
| --- | --- | --- |
| `gpustack_version` | `2.3.1` | Picks the image tag `v2.3.1` |
| `gpustack_image` | from the version | Override to use another registry or image |
| `gpustack_user` | `gpustack` | Unprivileged user that owns and runs the container |
| `gpustack_port` | `8080` | Host port for the UI and API |
| `gpustack_firewall_enabled` | `true` | Open `gpustack_port` in firewalld when it is running |
| `gpustack_bootstrap_password` | `""` | Password of `admin` when GPUStack first creates it. Empty: generated |
| `gpustack_server_external_url` | `""` | URL clients reach the server at. Once set, only that host name is accepted |
| `gpustack_env` | `{}` | Extra `GPUSTACK_*` environment variables |
| `gpustack_extra_ports` | `[]` | Extra `PublishPort=` values, e.g. `8443:443` for HTTPS |
| `gpustack_extra_volumes` | `[]` | Extra `Volume=` values, e.g. a certificate directory |

## Example

```yaml
- name: Deploy a GPUStack server
  hosts: gpustack
  become: true
  gather_facts: true

  roles:
    - kc_gardner.ai_infra.gpustack
```

## Check mode

`--check` works once `gpustack_user` exists. Before that the later tasks have no home directory to work in.

## Tested

On a new RHEL 9.8 VM (Podman 5.8.2, SELinux enforcing, firewalld not running) with the defaults:

- The first run created the `gpustack` user, pulled the image and started GPUStack 2.3.1; the UI answered on 8080 about a minute after the service started, from the VM and from the LAN
- A second run changed nothing
- After a reboot the service started by itself and the UI answered
- The container had the 65535 open-files limit and had written `initial_admin_password`

Against a VM where GPUStack 2.3.0 already ran from a hand-written rootless Quadlet unit under another user, with `gpustack_user` set to that user, only as `--check --diff`: it showed the unit being replaced and nothing else changing.

Not run: taking over an existing install for real, an upgrade between versions, opening the port in firewalld, HTTPS through `gpustack_extra_ports`, `gpustack_port` below 1024, logging in, and registering a worker.
