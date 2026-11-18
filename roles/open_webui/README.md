# open_webui

Runs [Open WebUI](https://openwebui.com), a ChatGPT-style web interface, in Docker Compose, connected to OpenAI-compatible APIs such as the `vllm_server` role's instances.

## Settings live in Open WebUI, not here

Open WebUI saves most of its settings in its own database the first time it starts: connections, whether sign-up is open, the default model and so on.
After that it ignores the environment variables for those settings, and you change them in **Admin Settings**.

This role follows that. It gives a new install sensible starting values, then leaves the settings alone:

| Setting | Starting value | Change it later in |
| --- | --- | --- |
| OpenAI-compatible connections | `open_webui_openai_connections` | Admin Settings > Connections |
| Ollama connection | off (`open_webui_enable_ollama`) | Admin Settings > Connections |
| Anything in `open_webui_env` | as given | wherever Open WebUI puts it |

Rerunning the role with different values does not change an existing install.
Changes to the environment file still recreate the container, but Open WebUI keeps what is in its database.

What the role does own on every run: the image version, the port, the data volume and the secret key.

## What it does

- Checks the settings, including a secret key of at least 32 characters
- Refuses to run while a container it did not create uses the data volume, unless `open_webui_replace_unmanaged` is true. Two copies of Open WebUI must not share one database.
- Writes `/opt/open-webui/compose.yaml` and `open-webui.env`. The environment file holds the secret key and only root can read it.
- When either file changed, so the container is about to be recreated, backs up the database with `sqlite3 .backup` into `open_webui_backup_dir`, keeping the newest `open_webui_backup_keep`
- Creates the data volume if it does not exist; an existing one is reused as is
- Starts Open WebUI, waits for its healthcheck, and reports its version

The container restarts on its own after a reboot (`restart: unless-stopped`) and can reach services on the host as `host.docker.internal`.

## Variables

See [defaults/main.yaml](defaults/main.yaml).

| Variable | Default | Purpose |
| --- | --- | --- |
| `open_webui_image` | `ghcr.io/open-webui/open-webui:v0.11.4` | Pin a release; `:main` is the development branch |
| `open_webui_name` | `open-webui` | Compose project and container name |
| `open_webui_port` | `3000` | Host port for the web interface |
| `open_webui_volume` | `open-webui` | Docker volume with the database, uploads and document index |
| `open_webui_compose_dir` | `/opt/open-webui` | Where the compose and environment files go |
| `open_webui_secret_key` | `""` | Required. Signs login sessions; keep it in Vault |
| `open_webui_openai_connections` | `[]` | New installs only. List of `url` and optional `key` |
| `open_webui_enable_ollama` | `false` | New installs only |
| `open_webui_env` | `{}` | More environment variables |
| `open_webui_backup` | `true` | Back up the database before recreating the container |
| `open_webui_backup_dir` | `/opt/open-webui/backups` | Where backups go |
| `open_webui_backup_keep` | `5` | Backups to keep |
| `open_webui_start_timeout` | `600` | Seconds to wait for Open WebUI to report healthy |
| `open_webui_replace_unmanaged` | `false` | Remove containers this role did not create that use the volume |

## Usage

```yaml
- hosts: gpu01
  become: true
  vars_files:
    - vars/open_webui.yaml   # open_webui_secret_key, git-ignored or in Vault
  roles:
    - role: kc_gardner.ai_infra.open_webui
      open_webui_openai_connections:
        - url: http://host.docker.internal:8000/v1
        - url: http://host.docker.internal:8001/v1
```

Open `http://<host>:3000`. On a new install the first account created becomes the admin, and later sign-ups wait for an admin to approve them.

### Taking over a container started by hand

The role stops with a list of containers that use the volume but were not created by it.
Run once with `open_webui_replace_unmanaged: true`: it backs up the database, removes those containers and starts its own on the same volume.
Chats, users and settings carry over.
Everyone has to log in again once, because the old container's secret key goes with it.

## Upgrading

Change `open_webui_image` to a newer release and rerun.
The role backs up the database first, and Open WebUI updates its database when it starts.
To go back, restore a backup as well as the old image: an older release may not read a database a newer one has updated.

## Restoring a backup

```bash
docker compose -f /opt/open-webui/compose.yaml stop
docker run --rm -v open-webui:/data -v /opt/open-webui/backups:/backup --entrypoint cp \
  ghcr.io/open-webui/open-webui:v0.11.4 /backup/webui-YYYYMMDD-HHMMSS.db /data/webui.db
docker run --rm -v open-webui:/data --entrypoint rm \
  ghcr.io/open-webui/open-webui:v0.11.4 -f /data/webui.db-wal /data/webui.db-shm
docker compose -f /opt/open-webui/compose.yaml start
```

Backups hold the database only (users, chats, settings). Uploaded files and the document index stay in the volume.

## Notes

- A connection's models come from its `/v1/models`, so a model changed in vLLM shows up by itself. Chats started with a model that is gone say so when continued; pick another model in the chat.
- Open WebUI works without a key for a vLLM instance that has no `--api-key`.
- The report ends in "(re)created" when the container was created or recreated, and in "started" when a stopped container was only started. Check mode says "would be" and does not wait for the healthcheck, since a dry run cannot start the container.

## Testing

Run on a DGX Spark (GB10, Ubuntu 24.04, arm64) with `v0.11.4`, alongside a `vllm_server` instance on port 8000:

- A new install created the volume, started Open WebUI and passed its healthcheck, and reached vLLM at `host.docker.internal:8000` with its models listed
- A second run changed nothing
- In check mode, the guard stopped on four containers started by hand that used the volume
- Check mode with the container running and the configuration unchanged reported no change. With a stopped container, check mode used to fail waiting for it ("exited (0)"); it now reports "would be started". The stopped-container cases were tested on a throwaway busybox compose project on the same host, not on Open WebUI: check mode and a real run both listed only `Starting` and reported "started", and a changed compose file listed `Recreate` and reported "(re)created".

Not yet tested: the database backup and pruning, `open_webui_replace_unmanaged: true`, and upgrading to a newer release.
