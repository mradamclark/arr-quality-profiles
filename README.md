# arr-quality-profiles

Ansible playbook to configure Sonarr and Radarr quality profiles optimized for **Apple TV 4K (1st gen) direct play**. Based on [TRaSH Guides](https://trash-guides.info/) with custom scoring tuned for direct play without transcoding.

For each service it configures:
- **Custom formats** — regex rules that tag releases by codec, source, and size
- **Quality profile** ("Custom 720/1080p") — scores each format to rank releases, with upgrade behavior enabled
- **Quality definitions** — per-tier size caps in MB/minute to reject oversized files

Releases are scored to prefer WEBDL sources, Dolby Vision/HDR10, and direct-play audio (DD+ Atmos, EAC3, AC3/AAC). DTS is penalized since it requires transcoding. CAM, BR-DISK, AV1, and known low-quality release groups are effectively banned.

See [docs/quality-profiles.md](docs/quality-profiles.md) for the full scoring table, size limits, and upgrade examples.

## Services

Each service is configured via its URL and API key environment variables. A service is skipped if its API key is not set.

| Service | URL variable | Key variable | Default URL |
|---------|-------------|--------------|-------------|
| Sonarr | `SONARR_URL` | `SONARR_API_KEY` | `http://localhost:8989` |
| Radarr | `RADARR_URL` | `RADARR_API_KEY` | `http://localhost:7878` |
| Seerr | `SEERR_URL` | `SEERR_API_KEY` | `http://localhost:5055` |

Sonarr and Radarr configure quality profiles and custom formats. Seerr is synced after both — it reads the active profile IDs from Sonarr and Radarr and updates its server entries so requests use the correct profile.

## Quick Start

```bash
export SONARR_API_KEY="your-sonarr-api-key"
export RADARR_API_KEY="your-radarr-api-key"
export SEERR_API_KEY="your-seerr-api-key"

ansible-playbook playbook.yml
```

To target a specific service:

```bash
ansible-playbook playbook.yml --tags sonarr
ansible-playbook playbook.yml --tags radarr
ansible-playbook playbook.yml --tags seerr
```

## Migrating Existing Content

The playbook configures profiles and formats but does not move existing library content. Use the included migration script as a one-time step after the playbook has run:

```bash
export SONARR_API_KEY="your-sonarr-api-key"
export RADARR_API_KEY="your-radarr-api-key"

./arr-migrate.sh
```

Migration runs in batches of 100 items with progress output. See [docs/quality-profiles.md](docs/quality-profiles.md) for full usage.

## Structure

```
arr-quality-profiles/
├── playbook.yml                    # Entry point — runs quality config for Sonarr, Radarr, and Seerr
├── arr-migrate.sh                  # One-time script to migrate existing content to the profile
├── vars/
│   ├── connection.yml              # Service URLs and API keys (read from environment variables)
│   ├── shared-quality.yml          # Shared format definitions and scores (Sonarr + Radarr)
│   ├── sonarr.yml                  # Sonarr-specific formats, scores, allowed qualities, size limits
│   └── radarr.yml                  # Radarr-specific formats, scores, allowed qualities, size limits
├── tasks/
│   ├── arr-quality.yml             # Shared task that configures either service via API
│   └── seerr-quality-sync.yml      # Syncs active profile IDs and API keys into Seerr (optional)
└── docs/
    └── quality-profiles.md         # Full documentation: scoring, sizes, upgrade examples
```

## Requirements

- Ansible
- Sonarr and/or Radarr running and accessible
- `curl` and `jq` (for `arr-migrate.sh` only)
