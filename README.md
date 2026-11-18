# kc_gardner.ai_infra

Ansible roles for running a small self-hosted AI stack: model serving with vLLM and GPUStack, a chat UI, the NVIDIA container runtime, and the lab around them (KVM hosts and guests, NetBox, inventory reports and Ubuntu patching).

The roles were written for a home lab with an NVIDIA DGX Spark (GB10) as the GPU host and Fedora and RHEL virtual machines for everything else. Each role's README says what it was tested on and what it was not.

## Roles

### AI

| Role | What it does |
| --- | --- |
| [vllm_server](roles/vllm_server/README.md) | Runs vLLM OpenAI-compatible servers in Docker Compose on an NVIDIA GPU host |
| [hf_models](roles/hf_models/README.md) | Downloads Hugging Face models to a host with Docker, for `vllm_server` to serve |
| [gpustack](roles/gpustack/README.md) | Runs the GPUStack server in a rootless Podman container managed by the user's systemd (Quadlet) |
| [open_webui](roles/open_webui/README.md) | Runs Open WebUI in Docker Compose, connected to OpenAI-compatible APIs such as vLLM |
| [nvidia_docker_runtime](roles/nvidia_docker_runtime/README.md) | Registers the NVIDIA Container Runtime with Docker, without restarting running containers |

### Lab

| Role | What it does |
| --- | --- |
| [kvm_host](roles/kvm_host/README.md) | Configures a headless Fedora host to run KVM/libvirt virtual machines |
| [kvm_guest](roles/kvm_guest/README.md) | Creates Fedora, Ubuntu, openSUSE and Enterprise Linux VMs from cloud images on a KVM/libvirt host |
| [netbox](roles/netbox/README.md) | Runs NetBox in Podman containers managed by systemd (Quadlet), with PostgreSQL, Valkey and nginx |
| [system_inventory](roles/system_inventory/README.md) | Collects hardware, OS and health data from hosts and writes JSON and CSV reports |
| [ubuntu_updates](roles/ubuntu_updates/README.md) | Installs all or security-only updates on Ubuntu and manages unattended-upgrades |

## Installing

```bash
ansible-galaxy collection install git+https://github.com/kc-gardner/kc_gardner.ai_infra.git
```

Or in a `requirements.yaml`:

```yaml
collections:
  - name: https://github.com/kc-gardner/kc_gardner.ai_infra.git
    type: git
    version: main
```

This also installs the collections the roles use: `ansible.posix`, `community.crypto`, `community.docker`, `community.general` and `community.libvirt`. It needs ansible-core 2.15 or later; some roles ask for 2.17, see their `meta/main.yaml`.

## Using

Call a role by its full name:

```yaml
- name: Deploy a GPUStack server
  hosts: gpustack
  become: true

  roles:
    - kc_gardner.ai_infra.gpustack
```

[playbooks/](playbooks) has an example playbook for each role. They expect inventory groups named `gpu_hosts`, `kvm_hosts`, `gpustack`, `netbox` and `ubuntu`; change `hosts:` to suit yours. Roles that need secrets load them from `playbooks/vars/<name>.yaml`, which git ignores. Copy the matching `.example.yaml` and fill it in.

## Running in Ansible Automation Platform

The roles keep nothing on the machine that runs Ansible except where listed here, so they work from an execution environment. What to set up:

- **Collections.** Put this collection in the project's `collections/requirements.yml` as shown above; the controller installs it and its dependencies when the project syncs. Or build them into the execution environment.
- **Playbooks.** A job template runs playbooks from the project repository, so copy the ones you need from [playbooks/](playbooks) into your project.
- **Secrets.** The example playbooks read `vars/<name>.yaml` files that git ignores. In AAP, leave those out and supply the same variables from a custom credential type, a survey or the job template's extra variables. Without them the roles stop with a message naming the missing variable.
- **`kvm_guest` SSH keys.** Set `kvm_guest_ssh_authorized_keys` as a variable. The example playbook reads `~/.ssh/id_ed25519.pub`, which an execution environment does not have.
- **`kvm_guest` RHEL images.** `rhel` and `rhel9` copy the image from the machine running Ansible. In AAP, put the images on a web server the KVM host can reach and point the catalog at them with `kvm_guest_os_catalog_overrides` (`image_url`), as the other operating systems do.
- **`system_inventory` reports.** They are written on the machine running Ansible, under `$PWD/reports`. In an execution environment that directory is discarded when the job ends. Set `system_inventory_report_dir` to a path mounted into the execution environment (the job settings' "Paths to expose to isolated jobs").

The roles declare ansible-core 2.17 in their metadata and were only run with a newer ansible-core from the command line. Nothing here has been run in AAP, and the execution environments shipped with AAP 2.5 carry ansible-core 2.16, so test there before relying on it.

## License

[MIT](LICENSE)
