# nvidia_docker_runtime

Registers the NVIDIA Container Runtime with Docker, so containers can ask for the GPU with `--runtime nvidia`.
It does what `nvidia-ctk runtime configure --runtime=docker` does, but keeps the rest of `daemon.json`, and it applies the change with a reload instead of a restart, so running containers are not touched.

## Why a host needs this

There are two ways a Docker container gets an NVIDIA GPU:

| | CDI | NVIDIA runtime |
| --- | --- | --- |
| Asked for with | `--device nvidia.com/gpu=all`, or `driver: nvidia` in Compose | `--runtime nvidia` |
| Set up by | the toolkit, which writes the device specs to `/var/run/cdi/nvidia.yaml` | an entry under `runtimes` in `/etc/docker/daemon.json` |
| Shows in `docker info` | `CDI spec devices` | `Runtimes: ... nvidia` |

DGX OS (checked on a DGX Spark with DGX OS 7.4.0) installs Docker and the NVIDIA Container Toolkit, and sets up CDI, but has no `daemon.json`, so the runtime is not registered.
CDI is enough for the `vllm_server` and `open_webui` roles. Some tools want the runtime: GPUStack's worker starts with `--runtime nvidia`, and its install check looks for `nvidia` in `docker info`'s runtimes.
Registering it adds a second way in; CDI keeps working as before.

## What it does

- Checks Docker is running, the toolkit is installed and `nvidia-container-runtime` is on the PATH
- Reads `/etc/docker/daemon.json` (a missing or empty file counts as no settings) and stops if it is not a JSON object
- Adds `runtimes.nvidia`, keeping every other setting and runtime. With `nvidia_docker_runtime_default: true` it also sets `default-runtime`.
- Writes the file only when the settings change, keeping a backup of the old one next to it
- Reloads Docker (`systemctl reload docker`, which sends dockerd a SIGHUP). `runtimes` and `default-runtime` are among the settings dockerd applies on a reload.
- Checks `docker info` now lists the runtime, and stops with a message if it does not. It never restarts Docker itself.
- Optional: runs `nvidia-smi -L` in a container through the runtime, to prove it reaches the GPU
- `state: absent` removes the runtime again, and `default-runtime` if it pointed at it

## Variables

See [defaults/main.yaml](defaults/main.yaml).

| Variable | Default | Purpose |
| --- | --- | --- |
| `nvidia_docker_runtime_state` | `present` | `present` or `absent` |
| `nvidia_docker_runtime_default` | `false` | Make it Docker's default runtime, so every container uses it |
| `nvidia_docker_runtime_name` | `nvidia` | The name used with `--runtime` |
| `nvidia_docker_runtime_path` | `nvidia-container-runtime` | The runtime binary, looked up on dockerd's PATH |
| `nvidia_docker_runtime_daemon_json` | `/etc/docker/daemon.json` | Docker's configuration file |
| `nvidia_docker_runtime_test_image` | `""` | Image to run `nvidia-smi -L` in after registering; empty skips the test |

## Usage

```yaml
- hosts: gpu01
  become: true
  roles:
    - role: kc_gardner.ai_infra.nvidia_docker_runtime
      # Already on the host, so the test downloads nothing.
      nvidia_docker_runtime_test_image: nvcr.io/nvidia/vllm:26.08-py3
```

Run with `--check --diff` first to see the new `daemon.json`.

## Notes

- Leave `nvidia_docker_runtime_default` off unless something needs it. As the default, every container, GPU or not, starts through the NVIDIA runtime.
- If the reload does not pick the runtime up, `systemctl restart docker` will. With `live-restore` off (the default), a restart stops every running container and starts the ones with a restart policy again, and a vLLM container then reloads its model.
- The test image needs no NVIDIA tools of its own: with `NVIDIA_VISIBLE_DEVICES=all` the runtime mounts `nvidia-smi` into the container.

## Testing

Run on a DGX Spark (GB10, DGX OS 7.4.0, Ubuntu 24.04, arm64, Docker 29.6.2, NVIDIA Container Toolkit 1.20.1), which had no `daemon.json`:

- Check mode showed the new `daemon.json`, the same as `nvidia-ctk runtime configure --runtime=docker --dry-run`
- The run created it and reloaded Docker. `docker info` then listed `runc io.containerd.runc.v2 nvidia` with `runc` still the default, and the vLLM and Open WebUI containers kept running without a restart.
- GPUStack's worker install check then passed, and its worker (started with `--runtime nvidia`) served a model

The settings logic was tested against `daemon.json` files that were missing, empty, already set, holding other settings and runtimes, and not a JSON object, for `present` and `absent` and with and without `nvidia_docker_runtime_default`.

Not yet tested: `state: absent` on a host, and a reload that does not pick the runtime up.
