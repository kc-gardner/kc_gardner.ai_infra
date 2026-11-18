# kvm_guest

Creates Fedora, Ubuntu, openSUSE, RHEL, Rocky, CentOS Stream or Oracle Linux virtual machines from cloud images on a host set up with the [kvm_host](../kvm_host/README.md) role.

## What it does

- Downloads the cloud image for each OS in use once, into `/var/lib/libvirt/images`. RHEL images are copied from the controller instead.
- Gives each VM its own qcow2 disk layered on that image, sized to `disk_gb`
- Uses cloud-init to set the hostname, create `kvm_guest_user` with your SSH keys and passwordless sudo, and install `qemu-guest-agent`. Password login is disabled.
- Gives each VM a fixed MAC address, and optionally a static IPv4 address (see [Static IPs](#static-ips)). VMs without `ip` use DHCP.
- Optional: registers RHEL VMs with Red Hat Subscription Management on first boot, using an activation key
- Creates the VM with `virt-install` (UEFI, virtio, serial console) and sets autostart
- Lets cloud-init finish the first boot and power the VM off, then starts it again. `virt-install --cloud-init` runs the first boot with the cloud-init ISO attached and `on_reboot=destroy`; restarting switches to the permanent configuration, so later reboots from inside the VM work. Waits up to `kvm_guest_first_boot_timeout` seconds (900).
- Waits for each VM to report an IP address and prints it with its MAC
- `state: absent` stops and undefines the VM and deletes its disk. It does not unregister RHEL VMs; run `sudo subscription-manager unregister` in the VM first, or the system stays listed in your Red Hat account until it goes stale.

Existing VMs are left alone: changing `vcpus`, `memory_mb`, `disk_gb`, `network`, `mac` or `ip` later does not change a VM that already exists.

## Variables

See [defaults/main.yaml](defaults/main.yaml). The main ones:

| Variable | Default | Purpose |
| --- | --- | --- |
| `kvm_guests` | `[]` | VMs to manage: `name`, `os`, plus optional `vcpus`, `memory_mb`, `disk_gb`, `network`, `autostart`, `state`, `os_variant`, `mac`, `ip`, `gateway`, `dns`, `dns_search` |
| `kvm_guest_defaults` | 2 vCPU, 2048 MB, 20 GB, `default` network | Values used when a VM leaves them out |
| `kvm_guest_user` | `ansible` | Login user created in each VM |
| `kvm_guest_ssh_authorized_keys` | `[]` | Public keys for that user (required) |
| `kvm_guest_rhel_image_src` / `kvm_guest_rhel9_image_src` | `""` | Paths on the controller to the RHEL 10 / RHEL 9 KVM guest qcow2 images |
| `kvm_guest_rhsm_org` / `kvm_guest_rhsm_activation_key` | `""` | Register RHEL VMs on first boot. Copy `playbooks/vars/rhsm.example.yaml` to `playbooks/vars/rhsm.yaml` (git-ignored) and fill them in; [deploy_kvm_guest.yaml](../../playbooks/deploy_kvm_guest.yaml) loads it |
| `kvm_guest_os_catalog_overrides` | `{}` | Change an OS's image or add a new OS |
| `kvm_guest_gateway` | `""` | Default gateway for VMs with a static `ip` |
| `kvm_guest_dns_servers` / `kvm_guest_dns_search` | `[]` | DNS servers and search domains for VMs with a static `ip` |

`network` is `default` (NAT, reachable only from the host) or `host-bridge` (on the LAN, from `kvm_host_bridge_enabled`).

## Static IPs

Set `ip` (address with prefix length) to give a VM a static IPv4 address instead of DHCP. The gateway and DNS settings come from `kvm_guest_gateway`, `kvm_guest_dns_servers` and `kvm_guest_dns_search` unless the VM sets `gateway`, `dns` or `dns_search` itself.

```yaml
kvm_guest_gateway: 192.0.2.1
kvm_guest_dns_servers: [192.0.2.117]
kvm_guest_dns_search: [lab.example.com]

kvm_guests:
  - name: netbox01
    os: fedora
    network: host-bridge
    ip: 192.0.2.120/24
```

The role writes a cloud-init `network-config` (version 2) next to the user-data and passes it to `virt-install --cloud-init`. It matches the NIC by its MAC address, so it works whatever the guest names the interface.

Every VM gets a fixed MAC. Without `mac`, it is derived from the KVM host's and the VM's names, so a VM rebuilt with the same name gets the same MAC and a DHCP reservation for it keeps working. The playbook prints each VM's MAC.

The router knows nothing about static addresses. Pick ones outside its DHCP range, or reserve them there too, or the router can hand the same address to another device.

The role checks that addresses and MACs are well formed and not used twice in `kvm_guests`. It does not check the network for addresses already in use.

## Operating systems

| `os` | Image |
| --- | --- |
| `fedora` | Fedora 44 Cloud Base Generic |
| `ubuntu` | Ubuntu 26.04 LTS server cloud image |
| `ubuntu2404` | Ubuntu 24.04 LTS server cloud image |
| `opensuse` | openSUSE Leap 16.0 Minimal VM (Cloud) |
| `tumbleweed` | openSUSE Tumbleweed Minimal VM (Cloud), rolling release |
| `rhel` | RHEL 10 KVM Guest Image, downloaded from the [Red Hat Customer Portal](https://access.redhat.com/downloads) |
| `rhel9` | RHEL 9 KVM Guest Image, downloaded the same way |
| `rocky` | Rocky Linux 10 GenericCloud |
| `centos-stream` | CentOS Stream 10 GenericCloud |
| `oraclelinux` | Oracle Linux 10.1 KVM image. It is 37 GB, so set `disk_gb` to 37 or more |

`disk_gb` must be at least the image's own size; the role checks this before creating the disk.
Catalog entries can also set `runcmd`, commands run once on first boot. Oracle Linux uses it to grow its LVM root, which cloud-init does not do.

To pin a different release, override the entry. For example, Ubuntu 24.04:

```yaml
kvm_guest_os_catalog_overrides:
  ubuntu:
    image_url: https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
    checksum: sha256:https://cloud-images.ubuntu.com/noble/current/SHA256SUMS
```

A base image is only downloaded if its file is missing. To pick up a newer build, delete the file from `/var/lib/libvirt/images` first. Only do this when no VMs are using it, because their disks depend on it.

## Usage

```bash
ansible-playbook -i inventory/hosts.yaml playbooks/deploy_kvm_guest.yaml
```

Log in with `ssh <user>@<ip>` using the address the playbook prints, where `<user>` is `kvm_guest_user`. For VMs on the NAT network, jump through the host: `ssh -J <user>@kvmhost <user>@<ip>`.
Console access: `virsh --connect qemu+ssh://<user>@kvmhost/system console <name>`.
