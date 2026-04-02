# Sonarr/Radarr Quality Profile Configuration

Automated quality profile configuration optimized for **Apple TV 4K (1st gen, A1842)** direct play. Based on [TRaSH Guides](https://trash-guides.info/) with custom scoring tuned for this device.

## Target Device

Apple TV 4K 1st generation (A1842) supports direct play of:

- **Video**: H.264, H.265/HEVC, HDR10, Dolby Vision (profile 5)
- **Audio**: DD+ Atmos, DD+ (EAC3), DD (AC3), AAC
- **Not supported** (requires transcoding): DTS, DTS-HD, DTS:X, TrueHD, AV1

## How It Works

The playbook configures each service via its API. All three services are optional — each is enabled by setting its API key environment variable. For Sonarr and Radarr the configuration has three layers:

### 1. Custom Formats (release matching)

Custom formats are regex-based rules that tag releases by properties detected in the release name. Each format is assigned a score on the quality profile.

### 2. Quality Profile ("Custom 720/1080p")

A single profile used by all series and movies. It defines:
- **Allowed qualities**: Which resolution/source tiers are acceptable
- **Format scores**: How much each custom format contributes to a release's total score
- **Upgrade behavior**: Sonarr/Radarr will replace an existing file if a new release scores higher

### 3. How Upgrades Work

When Sonar/Radarr already has a file for an item, it compares every new release's score against the existing file's score and upgrades when the new release is meaningfully better.

**An upgrade triggers when:**
1. The new release scores higher than `minUpgradeFormatScore` above the current file (set to 1 — any improvement qualifies)
2. The new release's quality tier is at or above the profile's cutoff (set to `1002`/Unknown — any quality tier can upgrade)
3. The new release is in the allowed qualities list

**The cutoff** is the quality tier at which Sonarr stops looking for better quality. With cutoff set to Unknown, Sonarr always considers upgrades regardless of tier. Setting it to `WEB 1080p` would stop upgrades once a 1080p WEB file exists.

**What prevents upgrade chasing:** size tiebreaker scores are intentionally small (+20 max) so a slightly larger or smaller file never overrides a codec improvement. A genuine codec or source improvement is required to trigger a grab.

**One caveat:** with `minUpgradeFormatScore: 1`, Sonarr upgrades on even a 1-point difference. If two releases are otherwise equal but land in different size buckets, Sonarr will grab the marginally better-scored one. This is fine in practice since size scores are small relative to codec scores.

### 4. Quality Definitions (size limits)

Per-quality size caps in MB/minute that reject releases exceeding the limit.

## Scoring Ladder

Releases are ranked by the sum of all matching custom format scores. Higher total = better release.

### Shared (Sonarr + Radarr)

| Format | Score | Why |
|--------|------:|-----|
| WEBDL | +75 | Untouched stream, no re-encode artifacts |
| Dolby Vision | +50 | Best HDR for Apple TV |
| DD+ Atmos | +30 | Direct-play surround (no sound system, tiebreaker) |
| HDR10 | +25 | Direct-play HDR fallback |
| DD+ (EAC3) | +25 | Direct play, good surround |
| x265/HEVC | +25 | Better compression, direct play on ATV4K |
| DD (AC3) | +20 | Direct play, basic surround |
| AAC | +15 | Direct play stereo |
| Proper/Repack | +5 | Fixes over original release |
| Multi/Dual Audio | -100 | Wastes space, rarely needed |
| DTS (any) | -200 | Requires Plex transcoding |

### Blocked Formats (score: -10,000)

These are effectively banned — a release would need impossible positive scores to overcome the penalty.

| Format | Why blocked |
|--------|-------------|
| CAM/TS | Unwatchable quality |
| BR-DISK | Raw disc, not a video file |
| AV1 | Not supported on Apple TV 4K 1st gen |
| x265 (HD) at 720p | Poor quality x265 encodes at 720p |
| Hardcoded Subs | Burned-in subtitles can't be toggled |
| 3D | Not useful for Apple TV |
| LQ (Low Quality) | Known bad release groups (YIFY, YTS, RARBG, etc.) |

### Size Tiebreakers (Sonarr)

When two releases have similar codec scores, size nudges the result. The scores are intentionally small so they never override a better codec match. Sweet spot is 500MB–1.5GB per episode.

| Size range | Score |
|-----------|------:|
| 500MB–1GB | +20 |
| <500MB | +10 |
| 1–1.5GB | +10 to +15 |
| 1.5–2GB | 0 to +5 |
| >2GB | -5 and below |
| >4GB | -80 and below |

### Size Tiebreakers (Radarr)

Sweet spot is 2–5GB per movie.

| Size range | Score |
|-----------|------:|
| 2–5GB | +15 to +20 |
| 1–2GB | +15 |
| <1GB | +5 |
| 5–7GB | +5 |
| 7–10GB | -20 |
| 10–15GB | -50 |
| >15GB | -100 |

## Upgrade Example

Existing file: `show.s01e01.1080p.WEBRip.HDR10.H265` (no audio tag detected)
- HDR10 (+25) + x265 (+25) = **50 total**

New release: `show.s01e01.1080p.WEBDL.DDP5.1.Atmos.H265`
- DD+ Atmos (+30) + WEBDL (+75) + x265 (+25) = **130 total**

Result: **upgrade triggered** — the new release scores 80 points higher, primarily because of the direct-play audio codec and untouched WEBDL source.

A DTS release would score -200, so even a WEBDL DTS release (-200 + 75 = -125) would lose to a plain WEBRip with DD+ (+25). This ensures Plex never needs to transcode audio for the Apple TV.

## Quality Size Limits

Size caps prevent grabbing excessively large files. Values are in MB/minute.

### Sonarr (per episode, ~45 min runtime)

| Quality | Max (MB/min) | ~Max per Episode |
|---------|-------------:|-----------------:|
| HDTV-720p | 34 | ~1.5 GB |
| WEBDL/WEBRip-720p | 34 | ~1.5 GB |
| HDTV-1080p | 46 | ~2 GB |
| WEBDL/WEBRip-1080p | 68 | ~3 GB |

### Radarr (per movie, ~120 min runtime)

| Quality | Max (MB/min) | ~Max per Movie |
|---------|-------------:|---------------:|
| HDTV/WEB-720p | 34 | ~4 GB |
| Bluray-720p | 43 | ~5 GB |
| HDTV/WEB/Bluray-1080p | 60 | ~7 GB |

## Allowed Qualities

### Sonarr
SDTV, WEB 480p, HDTV-720p, HDTV-1080p, WEB 720p (WEBRip + WEBDL), WEB 1080p (WEBRip + WEBDL)

### Radarr
Same as Sonarr plus: Bluray-720p, Bluray-1080p

Remux and 4K qualities are disabled — the Apple TV 4K 1st gen handles 1080p content best, and Remux files are excessively large.

## Files

| File | Purpose |
|------|---------|
| `vars/connection.yml` | Sonarr/Radarr/Seerr URLs and API keys |
| `vars/shared-quality.yml` | Shared format definitions and scores (Sonarr + Radarr) |
| `vars/sonarr.yml` | Sonarr-specific formats, scores, allowed qualities, and size limits |
| `vars/radarr.yml` | Radarr-specific formats, scores, allowed qualities, and size limits |
| `tasks/arr-quality.yml` | Shared task — loads service vars then configures via API |
| `tasks/seerr-quality-sync.yml` | Syncs active profile IDs and API keys into Seerr (optional) |
| `playbook.yml` | Runs the task for Sonarr, Radarr, and optionally Seerr |
| `arr-migrate.sh` | One-time migration script to move existing content to the profile |

## Running

```bash
# Configure all services
export SONARR_API_KEY="your-sonarr-api-key"
export RADARR_API_KEY="your-radarr-api-key"
export SEERR_API_KEY="your-seerr-api-key"
ansible-playbook playbook.yml

# Configure only one service
ansible-playbook playbook.yml --tags sonarr
ansible-playbook playbook.yml --tags radarr
ansible-playbook playbook.yml --tags seerr

# Dry run (check what would change without applying)
ansible-playbook playbook.yml --check --diff
```

URLs default to localhost — override with `SONARR_URL`, `RADARR_URL`, or `SEERR_URL` if your services are elsewhere.

The tasks are idempotent — existing custom formats are updated in place. Safe to re-run after changing scores.

## Migrating Existing Content

The playbook configures profiles and formats but does not move existing library content. Run the migration script as a one-time step after the playbook:

```bash
export SONARR_API_KEY="your-sonarr-api-key"
export RADARR_API_KEY="your-radarr-api-key"

# Migrate both
./arr-migrate.sh

# Or one at a time
./arr-migrate.sh sonarr
./arr-migrate.sh radarr
```

URLs default to localhost. Override with `SONARR_URL` or `RADARR_URL` if needed.

Migration runs in batches of 100 items and prints progress per batch. `BATCH_SIZE` and `PROFILE_NAME` can be overridden via environment variable if needed.
