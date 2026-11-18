# hf_models

Downloads models from Hugging Face into one folder on the host (`/opt/models` by default), ready for the `vllm_server` role to serve.
Downloads run `hf download` inside the vLLM image, so the host needs only Docker.

## What it does

- Checks the model list is valid and folder names are unique
- Creates the models folder, owned by `root:docker` with the setgid bit so new files stay in the `docker` group
- For each present model:
  - Reads which commit is already in the folder (from the `.cache/huggingface` notes `hf download` leaves there)
  - Downloads when the folder is empty, when `revision` is a commit hash that differs from what is there, or when `hf_models_update` is true
  - Checks there is at least `hf_models_min_free_gb` free before starting
  - Runs `docker run --rm --entrypoint "" <image> hf download <repo> --revision <revision> --local-dir /models/<name>`, in the background so long downloads do not time out
  - Checks the folder has a `config.json` and `.safetensors` weights
- Deletes the folder of each model with `state: absent`
- Lists each model with the commit it is on, and what it was before if it changed

Folders not in `hf_models` are left alone.

## When does it download?

| `revision` | Folder missing | Folder present |
| --- | --- | --- |
| a branch or tag (`main`) | download | skip, unless `hf_models_update: true` |
| a 40-character commit hash | download | download if the folder holds a different commit |

`hf download` only fetches files that are missing or changed, so a rerun on a complete folder is quick.
Pin a commit hash for anything you depend on, so a rerun never changes the model under a running server.

## Variables

See [defaults/main.yaml](defaults/main.yaml).

| Variable | Default | Purpose |
| --- | --- | --- |
| `hf_models` | `[]` | Models to manage, see below |
| `hf_models_defaults` | `revision: main`, `state: present` | Applied to every entry |
| `hf_models_dir` | `/opt/models` | Where models live; `vllm_server_models_dir` must match |
| `hf_models_dir_owner` / `_group` / `_mode` | `root` / `docker` / `2775` | Ownership of the models folder |
| `hf_models_image` | `vllm/vllm-openai:v0.28.0@sha256:…` | Image that provides the `hf` command; keep it the same as the `vllm_server` image |
| `hf_models_token` | `""` | Hugging Face token for gated or private models; keep it in Vault |
| `hf_models_update` | `false` | Re-download models that track a branch, to pick up new commits |
| `hf_models_min_free_gb` | `100` | Refuse to start a download with less free space than this |
| `hf_models_download_timeout` | `14400` | Seconds a single download may take |

Each entry in `hf_models`:

| Key | Default | Purpose |
| --- | --- | --- |
| `repo` | required | Hugging Face repo, e.g. `Qwen/Qwen3.6-35B-A3B-FP8` |
| `name` | last part of `repo` | Folder under `hf_models_dir`; this is the `model` a `vllm_server` instance points at |
| `revision` | `main` | Branch, tag or commit hash |
| `state` | `present` | `absent` deletes the folder |

## Usage

```yaml
- hosts: gpu01
  become: true
  roles:
    - role: kc_gardner.ai_infra.hf_models
      hf_models:
        - repo: Qwen/Qwen3.6-35B-A3B-FP8
          revision: 95a723d08a9490559dae23d0cff1d9466213d989
        - repo: Qwen/Qwen3.8-27B-FP8
```

Run with `--check` to see which models would be downloaded.

## Notes

- The token reaches the container through the environment, not the command line, so it is not in the task output or `ps`. Ansible does show environment variables at `-vvv` and above.
- Removing a model that a `vllm_server` instance still uses breaks that instance the next time it restarts. Remove or repoint the instance first.
- The first line of `<folder>/.cache/huggingface/download/config.json.metadata` is the commit the folder holds.

## Testing

Run on a DGX Spark (GB10, Ubuntu 24.04, arm64) with the `nvcr.io/nvidia/vllm:26.08-py3` image, before the default moved to upstream vLLM:

- Downloaded Qwen/Qwen3.8-27B-FP8 (31 GB) pinned to a commit, in about 8 minutes
- A second run found the commit in place and downloaded nothing
- Check mode against an existing Qwen3.6-35B-A3B-FP8 download reported its commit without changing anything

With `vllm/vllm-openai:v0.28.0` and `--entrypoint ""`, a download of Qwen/Qwen3.8-27B (52 GB) ran and had fetched 31 GB when it was stopped on purpose; it has not yet run to the end with this image.

Not yet tested: `state: absent`, `hf_models_update`, a gated model with `hf_models_token`, and the free-space check failing.
