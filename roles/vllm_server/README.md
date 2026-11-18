# vllm_server

Runs vLLM, an OpenAI-compatible model server, in Docker on an NVIDIA GPU host.
Each instance is one container serving one model on its own port, managed as its own Docker Compose project in `/opt/vllm/<name>/compose.yaml`.

Models must already be on the host; the `hf_models` role downloads them.

The default image is upstream vLLM (`vllm/vllm-openai`), pinned by tag and digest, which is what NVIDIA's [DGX Spark vLLM playbook](https://build.nvidia.com/spark/vllm/instructions) runs.
NVIDIA's NGC build (`nvcr.io/nvidia/vllm:<yy.mm>-py3`) works too: set `image` on an instance.

## What it does

- Checks the instance list: valid names, unique names and ports, and the instances' GPU memory shares adding up to no more than `vllm_server_gpu_memory_limit`
- Checks Docker Compose and the NVIDIA Container Toolkit are installed, and each model folder has a `config.json`
- Refuses to replace a container with an instance's name that it did not create, such as one started with `docker run`, unless `vllm_server_replace_unmanaged` is true
- Stops and removes instances with `state: absent`
- For each present instance, one at a time:
  - Writes its compose file. A changed file recreates the container; an unchanged one leaves it running.
  - Starts it and waits until its healthcheck passes, which means the model is loaded
  - Asks `/v1/models` on its port and checks the served name
  - Reports vLLM's memory summary from the container log

Instances start one after another because vLLM measures free GPU memory as it starts, and two loading at once can each count the other's memory as used.
Containers restart on their own after a reboot (`restart: unless-stopped`).
The compose file clears the image's entrypoint (the upstream one is `vllm serve`) and runs `vllm serve` itself, so either image works.

## The settings

These are the ones worth understanding. The rest of `vllm serve`'s options go in `extra_args`.

| Setting | vLLM flag | What it does |
| --- | --- | --- |
| `served_name` | `--served-model-name` | The model name clients put in requests. Keep it stable and you can change the model underneath without touching clients. |
| `gpu_memory_utilization` | `--gpu-memory-utilization` | Share of GPU memory the container takes when it starts: the weights, then a pool (the KV cache) that holds each request's context. |
| `max_model_len` | `--max-model-len` | Longest single request, prompt plus reply, in tokens. |
| `max_num_seqs` | `--max-num-seqs` | Requests worked on at the same time; others wait in a queue. |
| `prefix_caching` | `--enable-prefix-caching` | Reuses work for prompts that start the same way: system prompts, earlier chat turns, agent loops. |
| `reasoning_parser` | `--reasoning-parser` | Moves the model's thinking into a separate `reasoning_content` field. |
| `tool_call_parser` | `--enable-auto-tool-choice --tool-call-parser` | Turns the model's tool calls into OpenAI-style `tool_calls`. |
| `language_model_only` | `--language-model-only` | Skips a multimodal model's vision encoder: text only, less memory. |

### How the memory settings fit together

`gpu_memory_utilization` sets the budget. The weights come out of it first, and the rest is the KV cache pool.
Every token of every request in progress takes space in that pool, so `max_model_len` and `max_num_seqs` compete for it.
vLLM prints how it worked out at startup, and the role reports it. For example (illustrative numbers):

```
GPU KV cache size: 1,583,104 tokens
Maximum concurrency for 262,144 tokens per request: 6.04x
```

Here the second line would mean six requests of the full 262,144 tokens fit at once.
If it is below `max_num_seqs`, long requests queue even when slots are free. Raise `gpu_memory_utilization` or lower `max_model_len`.
If vLLM will not start because the model does not fit, it says so in `docker logs <name>`.

On a DGX Spark (GB10) the GPU and the operating system share the same 128 GB, so `gpu_memory_utilization` is a share of the whole machine.
Keep the instances' total under `vllm_server_gpu_memory_limit` (0.9) so the host has room.
Each instance also uses about 3 GB outside its share, for its CUDA context and processes.

The check only adds up this role's instances. Anything else using the GPU, such as a GPUStack worker or a container started by hand, is not counted: leave room for it in `vllm_server_gpu_memory_limit`, or keep one tool in charge of each host.

### Parser values

| Model family | `reasoning_parser` | `tool_call_parser` |
| --- | --- | --- |
| Qwen3.8 | `qwen3` | `qwen3_xml` |
| Qwen3, Qwen3.5, Qwen3.6 | `qwen3` | `qwen3_coder` (or `hermes` for older Qwen3 chat models) |
| DeepSeek R1 / V3 | `deepseek_r1` | `deepseek_v3` |
| Llama 3.x | | `llama3_json` |
| Mistral | | `mistral` |

The model card on Hugging Face usually gives the right `vllm serve` flags.

## Variables

See [defaults/main.yaml](defaults/main.yaml).

| Variable | Default | Purpose |
| --- | --- | --- |
| `vllm_server_instances` | `[]` | Containers to run, see below |
| `vllm_server_defaults` | see defaults | Applied to every instance |
| `vllm_server_models_dir` | `/opt/models` | Host folder of models, mounted read-only at `/models` |
| `vllm_server_cache_dir` | `/opt/vllm-cache` | Compile caches of vLLM, FlashInfer and Triton, in `vllm/`, `flashinfer/` and `triton/`, shared by the instances |
| `vllm_server_compose_dir` | `/opt/vllm` | Each instance's compose file goes in `<this>/<name>/` |
| `vllm_server_gpu_memory_limit` | `0.9` | Most the instances' `gpu_memory_utilization` may add up to |
| `vllm_server_start_timeout` | `1800` | Seconds to wait for an instance to load its model |
| `vllm_server_replace_unmanaged` | `false` | Remove a same-named container this role did not create |

Each entry in `vllm_server_instances`:

| Key | Default | Purpose |
| --- | --- | --- |
| `name` | required | Container and Compose project name: lowercase letters, digits, `-` and `_` |
| `model` | required | Folder under `vllm_server_models_dir` |
| `port` | required | Host port for the API |
| `served_name` | `name` | Model name for clients |
| `image` | `vllm/vllm-openai:v0.28.0@sha256:…` | vLLM image |
| `gpu_memory_utilization` | `0.5` | Share of GPU memory |
| `max_model_len` | `32768` | Longest request in tokens |
| `max_num_seqs` | `4` | Requests at the same time |
| `prefix_caching` | `true` | Reuse work for shared prompt starts |
| `reasoning_parser` | `""` | Off when empty |
| `tool_call_parser` | `""` | Off when empty |
| `language_model_only` | `false` | Skip the vision encoder |
| `extra_args` | `[]` | More `vllm serve` arguments |
| `env` | `{}` | Environment variables for the container |
| `extra_volumes` | `[]` | More bind mounts, `host:container[:opts]` |
| `security_opt` | `[]` | Docker security options, e.g. `seccomp=unconfined` for an image that uses io_uring |
| `state` | `present` | `absent` stops and removes the container |

## Usage

Two models side by side on one host:

```yaml
- hosts: gpu01
  become: true
  roles:
    - role: kc_gardner.ai_infra.hf_models
      hf_models:
        - repo: Qwen/Qwen3.6-35B-A3B-FP8
        - repo: Qwen/Qwen3.8-27B-FP8
    - role: kc_gardner.ai_infra.vllm_server
      vllm_server_instances:
        - name: vllm
          model: Qwen3.6-35B-A3B-FP8
          served_name: qwen3.6
          port: 8000
          gpu_memory_utilization: 0.55
          max_model_len: 262144
          reasoning_parser: qwen3
          tool_call_parser: qwen3_coder
          language_model_only: true
        - name: qwen38
          model: Qwen3.8-27B-FP8
          served_name: qwen3.8
          port: 8001
          gpu_memory_utilization: 0.3
          max_model_len: 65536
          max_num_seqs: 2
          reasoning_parser: qwen3
          tool_call_parser: qwen3_xml
```

Clients use `http://gpu01:8000/v1` or `:8001/v1` with any API key, and the `served_name` as the model.

### Taking over a container started by hand

A container named like an instance but started with `docker run` makes the role stop with a message.
Run once with `vllm_server_replace_unmanaged: true` and the role removes it and starts its own with the same name.
The model is unavailable while the new container loads, usually a few minutes.

## Notes

- The API is open to anyone who can reach the port. To require a key, add `extra_args: ["--api-key", "{{ vault_vllm_api_key }}"]`; the key then appears in the compose file and `docker inspect`.
- `docker compose -f /opt/vllm/<name>/compose.yaml logs -f` or `docker logs -f <name>` follows an instance's log.
- vLLM listens on port 8000 inside every container; `port` is the host side.
- The report ends in "(re)created" when an instance's container was created or recreated, and in "started" when a stopped container was only started. Check mode says "would be" and does not wait for the healthcheck, since a dry run cannot start the container.
- The first start of a model compiles kernels and can take over ten minutes. They are cached in `vllm_server_cache_dir`, so later starts are faster. A new image or vLLM version compiles them again.

## Testing

### Upstream image

Run on the same DGX Spark with `vllm/vllm-openai:v0.28.0`, serving nvidia/Qwen3.8-27B-NVFP4:

- Replaced the NGC container: the compose change recreated it, and it loaded and passed its healthcheck in about 6 minutes with the cleared entrypoint and the three cache folders
- With the settings from the [vLLM recipe for DGX Spark](https://recipes.vllm.ai/Qwen/Qwen3.8-27B?hardware=dgx_spark_gb10&variant=nvfp4_nvidia) (`gpu_memory_utilization: 0.7`, `max_num_seqs: 8`, async scheduling, `fastsafetensors`, MTP with 5 draft tokens, and `env: {VLLM_USE_RUST_FRONTEND: "1"}`) it started in about 4 minutes, weights 11 s. The KV cache held about 1.08M tokens (4.11 full-length requests).
- The Rust frontend warns that it ignores `enable_auto_tool_choice`, but a tool call still came back as an OpenAI-style `tool_calls` entry and the reasoning was split out
- One request generated 25.7 tokens/s and four at once 80.9 in total, against 24.1 and 78.2 on NGC 26.08 (vLLM 0.27.1) with MTP 2. Long prompts were 4–7% slower to first token than on NGC.

In v0.28 `qwen3_xml` and `qwen3_coder` load the same tool parser.

### NGC image

The runs below used the NGC image `nvcr.io/nvidia/vllm:26.08-py3`.

Run on a DGX Spark (GB10, Ubuntu 24.04, arm64) with the `nvcr.io/nvidia/vllm:26.08-py3` image (vLLM 0.27.1), serving Qwen3.8-27B-FP8:

- First deploy: created the container, waited about 6 minutes for it to load and pass its healthcheck, and confirmed the served name
- A second run changed nothing and left the container running
- Changing `extra_args` (adding MTP speculative decoding, then changing its draft tokens from 3 to 2) recreated the container each time
- The memory report matched vLLM's log

With `gpu_memory_utilization: 0.6`, `max_model_len: 262144`, FP8 KV cache and MTP with 2 draft tokens, the model uses 28 GB, the KV cache holds about 1.17M tokens (4.47 full-length requests), and one request generates about 16 tokens/s, against 8.4 without MTP.

The preflight checks were tested in check mode: a GPU memory total over the limit, a duplicate port, a missing model folder, an invalid name, and a container with an instance's name started by hand.

### Next to another vLLM on the same host

Run on the same DGX Spark with the image above, while GPUStack served Gemma 4 26B-A4B at `--gpu-memory-utilization 0.5` from its own vLLM container. The playbook was run with its model and instance lists replaced by extra vars: Qwen/Qwen3-0.6B pinned to a commit, as `vllm-test` on port 8002 with `gpu_memory_utilization: 0.1`, `max_model_len: 32768`, the `qwen3` reasoning parser and the `hermes` tool parser.

- `hf_models` downloaded the model, and the instance loaded and passed its healthcheck in about 1.5 minutes (weights 9 s, compile 14 s) while the other vLLM was running. The KV cache held 85,504 tokens (2.61 full-length requests).
- Both answered requests at the same time, and a tool call came back as an OpenAI-style `tool_calls` entry with the reasoning split out
- The 0.1 share took about 15 GB of the host's memory: the 12.1 GiB share plus about 3 GB of CUDA context and process overhead that vLLM does not count. The host did not swap.
- `state: absent` stopped and removed the container and its compose folder, and left the model folder and a stopped instance that was not in the list alone. A second run changed nothing.

### Check mode and the report

Check mode with `vllm` running and its compose file unchanged reported no change. A stopped container used to fail check mode, because the dry run's wait saw it exited; check mode no longer waits. The stopped-container cases were tested on a throwaway busybox compose project on the same host rather than on a vLLM instance: check mode and a real run both listed only `Starting` and reported "started", and a changed compose file listed `Recreate` and reported "(re)created".

Check mode stops at "Ensure each model is downloaded" when a playbook adds a new model, because `hf_models` downloads nothing in check mode.

Not yet tested: two instances from this role at the same time, and `vllm_server_replace_unmanaged: true`.
