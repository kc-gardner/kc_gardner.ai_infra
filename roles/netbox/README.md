# netbox

Runs [NetBox](https://netboxlabs.com/docs/netbox/) on one host in Podman containers that systemd manages through [Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html). It uses the [netbox-docker](https://github.com/netbox-community/netbox-docker) image, with PostgreSQL, Valkey and nginx each in their own container.

The host only needs Podman. The same images run on Fedora and RHEL 9 and 10, so there is nothing distribution-specific to maintain.

## Containers

| Service | Container | Image | Job |
| --- | --- | --- | --- |
| `netbox-postgres` | `netbox-postgres` | `postgres:18-alpine` | Database, in the `netbox-postgres` volume |
| `netbox-valkey` | `netbox-valkey` | `valkey:9.1-alpine` | Task queue and cache, in the `netbox-valkey` volume |
| `netbox` | `netbox` | `netboxcommunity/netbox` | The application. Migrates the database when it starts |
| `netbox-worker` | `netbox-worker` | same | Background jobs |
| `netbox-nginx` | `netbox-nginx` | `nginx:1.30-alpine` | HTTPS on 443, redirect from 80 |

They share a private `netbox` network. Only nginx publishes ports. Valkey has no password because nothing outside that network can reach it.

The services start in order: `netbox` waits for the database and Valkey to be healthy, and the worker and nginx wait for `netbox` to answer its login page. They are ordinary systemd services, so `systemctl status netbox` and `journalctl -u netbox` work, and they start at boot.

## What it does

- Checks the operating system, memory (2 GB), secrets and server names
- Installs Podman and checks it is version 5 or later
- Writes `/etc/netbox`: `netbox.env` and `postgres.env` (readable by root only, they hold the secrets), `zz_role.py` for extra configuration, `nginx.conf` and the certificate in `tls/`
- Uses your certificate or makes a self-signed one for the names in `netbox_server_names`
- Installs the Quadlet units in `/etc/containers/systemd` and checks that Podman's generator accepts them
- Pulls any image that is missing
- Starts the services, restarting only those whose image or configuration changed
- Applies a changed `netbox_db_password` to the database role
- Checks that the services are active, the login page answers through nginx, and NetBox reports `netbox_version`

The first superuser is created by the container when it starts, if `netbox_superuser_password` is set and the user does not exist.

Podman publishes ports with its own firewall rules, so the role does not touch firewalld.

## Upgrades

Change `netbox_version` and `netbox_docker_version` to a pair from the [netbox-docker releases](https://github.com/netbox-community/netbox-docker/releases) and rerun. The container is recreated from the new image and migrates the database before it serves anything.

Going back to an older image is not a rollback: the database has already been migrated. Take a backup first. The role does not take one.

```bash
sudo podman exec netbox-postgres pg_dump -U netbox -Fc netbox > netbox.dump
```

Do not change `netbox_postgres_image` to another major version on an existing install. PostgreSQL cannot open a data directory made by a different major version; it needs a dump and restore.

## Plugins

The image has no way to install plugins at run time. Build an image from the netbox-docker one that adds them, push it to a registry the host can reach, and set `netbox_image` to it. Enable the plugins with `netbox_configuration_extra`.

## Variables

See [defaults/main.yaml](defaults/main.yaml).

| Variable | Default | Purpose |
| --- | --- | --- |
| `netbox_version`, `netbox_docker_version` | `4.7.5`, `5.1.2` | Pick the image tag `v4.7.5-5.1.2` |
| `netbox_image` | from the two above | Override to use your own image |
| `netbox_postgres_image`, `netbox_valkey_image`, `netbox_nginx_image` | see above | |
| `netbox_server_names` | FQDN, hostname, default IPv4 address | `ALLOWED_HOSTS`, CSRF origins, nginx `server_name`, certificate names. The first is the certificate's common name |
| `netbox_secret_key` | none, required | At least 50 characters. Changing it logs everyone out |
| `netbox_api_token_pepper` | none, required | At least 50 characters. Changing it invalidates every v2 API token |
| `netbox_db_password` | none, required | Password of the PostgreSQL role |
| `netbox_db_name`, `netbox_db_user` | `netbox` | Only used when the database is first created |
| `netbox_superuser_name`, `_email`, `_password` | `admin`, `admin@example.com`, empty | First superuser. An empty password creates none. An existing user's password is never reset |
| `netbox_time_zone` | `UTC` | |
| `netbox_workers` | `4` | Granian worker processes |
| `netbox_env` | `{}` | Extra environment variables for any setting the image reads from its environment |
| `netbox_configuration_extra` | empty | Python for settings with no environment variable, such as `PLUGINS` |
| `netbox_tls_cert_file`, `netbox_tls_key_file` | empty | Certificate and key already on the host, copied into `/etc/netbox/tls` on each run. Empty: a self-signed certificate is made |
| `netbox_tls_selfsigned_days` | `3650` | |
| `netbox_http_port`, `netbox_https_port` | `80`, `443` | Host ports |
| `netbox_client_max_body_size` | `25m` | Largest upload nginx accepts |
| `netbox_config_dir` | `/etc/netbox` | Configuration on the host |

After renewing a provided certificate, rerun the role: it copies the new files and restarts nginx.

## Example

```yaml
- name: Deploy a NetBox server
  hosts: netbox
  become: true

  vars_files:
    - vars/netbox.yaml   # secrets, not in git

  vars:
    netbox_server_names:
      - netbox.example.com

  roles:
    - kc_gardner.ai_infra.netbox
```

`openssl rand -base64 48` makes a suitable secret key or pepper.

## Useful commands

```bash
sudo systemctl status netbox netbox-worker netbox-nginx netbox-postgres netbox-valkey
sudo journalctl -u netbox -f
sudo podman exec -it netbox /opt/netbox/netbox/manage.py nbshell
```

## Requirements

Collection `community.crypto` on the controller. The host needs to reach Docker Hub, or wherever your images are.

## Tested

Fedora 44 with Podman 5.8 and NetBox 4.7.5. RHEL 9 and 10 are not tested.
