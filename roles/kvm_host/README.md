# kvm_host

Sets up a headless Fedora machine to run KVM/libvirt virtual machines.

## What it does

- Checks that the host is Fedora and that the CPU exposes VT-x/AMD-V
- Installs QEMU/KVM, libvirt, `virt-install`, `guestfs-tools`, UEFI firmware (OVMF) and swtpm (vTPM). No GUI packages are installed.
- Enables the modular libvirt daemon sockets (`virtqemud`, `virtnetworkd`, etc.)
- Adds `kvm_host_users` to the `libvirt` group
- Sets the tuned profile to `virtual-host`
- Defines, starts and autostarts storage pools (custom paths get the SELinux label `virt_image_t`)
- Keeps libvirt's `default` NAT network active and autostarted
- Optional: bridges the physical NIC (`br0`) and defines a `host-bridge` libvirt network so VMs sit on the LAN
- Optional: installs Cockpit with `cockpit-machines` for a web UI on port 9090
- Runs `virt-host-validate qemu` and prints the results

## Variables

See [defaults/main.yaml](defaults/main.yaml). The main ones:

| Variable | Default | Purpose |
| --- | --- | --- |
| `kvm_host_users` | `[]` | Users to add to the `libvirt` group |
| `kvm_host_storage_pools` | `default` → `/var/lib/libvirt/images` | Storage pools to define |
| `kvm_host_bridge_enabled` | `false` | Put the NIC on bridge `br0` |
| `kvm_host_bridge_interface` | default IPv4 interface | NIC to bridge |
| `kvm_host_cockpit_enabled` | `false` | Install the Cockpit web UI |

## Bridge networking

Bridging moves the host's IP address from the NIC onto `br0`, so the network drops for a few seconds.
The change runs as a detached job on the host, which keeps it going if the SSH session drops.
The bridge keeps the NIC's MAC address and IPv4 settings (DHCP or static), so the host keeps its IP.
If `br0` has no IPv4 address within about 60 seconds, the script restores the original connection.

## Usage

```bash
ansible-galaxy collection install git+https://github.com/kc-gardner/kc_gardner.ai_infra.git
ansible-playbook -i inventory/hosts.yaml playbooks/setup_kvm_host.yaml
```

Create a VM from your workstation:

```bash
virt-install --connect qemu+ssh://<user>@kvmhost/system \
  --name test --memory 2048 --vcpus 2 --disk size=20 \
  --os-variant fedora-unknown --network network=default \
  --location https://download.fedoraproject.org/pub/fedora/linux/releases/44/Server/x86_64/os/ \
  --graphics none --extra-args console=ttyS0
```
