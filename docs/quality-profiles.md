# Sonarr/Radarr Quality Profile Configuration

Automated quality profile configuration optimized for **Apple TV 4K (1st gen, A1842)** direct play. Based on [TRaSH Guides](https://trash-guides.info/) with custom scoring tuned for this device.

## Target Device

Apple TV 4K 1st generation (A1842) supports direct play of:

- **Video**: H.264, H.265/HEVC, HDR10, Dolby Vision (profile 5)
- **Audio**: DD+ Atmos, DD+ (EAC3), DD (AC3), AAC
- **Not supported** (requires transcoding): DTS, DTS-HD, DTS:X, TrueHD, AV1

## How It Works

The playbook configures each service via its API. All services are optional — each is enabled by setting its API key environment variable. For Sonarr and Radarr the configuration has three layers:

### 1. Custom Formats (release matching)

Custom formats are regex-based rules that tag releases by properties detected in the release name. Each format is assigned a score on the quality profile.

**Important:** The positive detection spec in multi-condition formats (e.g. DD+ but not Atmos) uses `required: true` so the format only matches when the codec is actually present in the release title. Using `required: false` on the positive spec causes the format to match any release that merely satisfies the negative condition — inflating all scores incorrectly.

### 2. Quality Profile ("CustomProfile")

A single profile used by all series and movies. It defines:
- **Allowed qualities**: Which resolution/source tiers are acceptable
- **Format scores**: How much each custom format contributes to a release's total score
- **Cutoff**: The quality tier at which Sonarr/Radarr stops seeking upgrades

**Sonarr cutoff:** `WEB 1080p` — stops upgrading once a WEB-1080p file exists.

**Radarr cutoff:** `WEB 1080p` — stops upgrading once a WEB-1080p movie exists. Bluray-1080p remains an allowed quality so it can be grabbed as a first download if that's the only option available, but Radarr will not automatically upgrade a WEB-1080p to Bluray.

### 3. How Scoring Works

Custom format scores are **within-tier tiebreakers**. Sonarr/Radarr's quality tier ordering (HDTV-720p < HDTV-1080p < WEB-720p < WEB-1080p) takes precedence over scores for upgrade decisions. Scores determine which release wins when two options are in the same quality tier.

**An upgrade triggers when:**
1. The new release's quality tier is above the current file (always preferred regardless of score), OR the new release scores at least `minUpgradeFormatScore` (5) higher within the same tier
2. The new release is in the allowed qualities list
3. The new release scores above `minFormatScore` (0) — releases with net-negative scores are not auto-downloaded

### 4. Quality Definitions (size limits)

Per-quality size caps in MB/minute that reject releases exceeding the limit.

---

## Scoring Reference

### Shared Formats (Sonarr + Radarr)

| Format | Score | Why |
|--------|------:|-----|
| DD+ Atmos | +30 | Best direct-play audio on ATV4K |
| DD+ (EAC3) | +25 | Direct play surround, common on streaming |
| Dolby Vision | +20 | Best HDR for ATV4K |
| DD (AC3) | +20 | Direct play basic surround |
| AAC | +15 | Direct play stereo |
| HDR10 | +10 | Direct play HDR |
| WEBDL | +10 | Untouched stream, prefer over WEBRip within same tier |
| x265/HEVC | +5 | Better compression, direct play on ATV4K |
| Proper/Repack | +5 | Fix over original release |
| Multi/Dual Audio | -100 | Wastes space, rarely needed |
| DTS (any) | -200 | Requires Plex transcoding on ATV4K |

### Blocked Formats (score: -10,000)

Effectively banned — a release would need impossible positive scores to download.

| Format | Why blocked |
|--------|-------------|
| CAM/TS | Unwatchable quality |
| BR-DISK | Raw disc image, not a video file |
| AV1 | Not supported on Apple TV 4K 1st gen |
| x265 (HD) at 720p | Blocked in Sonarr; score overridden to 0 in Radarr (quality tier handles preference) |
| Hardcoded Subs | Burned-in subtitles can't be toggled |
| 3D | Not useful for Apple TV |
| LQ (Low Quality) | Known bad release groups (YIFY, YTS, etc.) |
| Described Audio (AD) | Audio description tracks for visually impaired |

### Size Tiebreakers — Sonarr (TV Episodes)

Sweet spot is ~2GB for a 1080p WEB-DL hour-long episode. Scores nudge toward smaller files within a tier but are small enough that codec differences always dominate.

| Size range | Score |
|-----------|------:|
| 500MB–1GB | +20 |
| <500MB | +10 |
| 1–1.5GB | +10 to +15 |
| 1.5–2GB | +1 to +5 |
| 2–2.1GB | 0 (baseline) |
| 2.1–3GB | -3 to -10 |
| 3–4GB | -15 |
| 4–6GB | -30 |
| >6GB | -60 |

### Size Tiebreakers — Radarr (Movies)

Sweet spot is 2–5GB for a 1080p WEB-DL movie. Radarr's WEB-1080p cutoff means very large Bluray remuxes are not automatically chased.

| Size range | Score |
|-----------|------:|
| 2–4GB | +20 |
| 1–2GB | +15 |
| <1GB | +5 |
| 4–5GB | +10 |
| 5–7GB | 0 (baseline) |
| 7–10GB | -20 |
| 10–15GB | -50 |
| >15GB | -100 |

---

## Upgrade Example

**Existing file:** `Gold.Rush.S16E19.1080p.HEVC.x265-MeGusta` (HDTV-1080p, 808MB)
- x265/HEVC (+5) + Size:700-800MB (+20) = **+25**

**New release:** `Gold.Rush.S16E19.1080p.AMZN.WEB-DL.DDP2.0.H.264-Kitsune` (WEBDL-1080p, 3.5GB)
- DD+ (+25) + WEBDL (+10) + Size:3-4GB (-15) = **+20**

Kitsune is in a **higher quality tier** (WEBDL-1080p > HDTV-1080p) so the upgrade triggers regardless of scores. Within the same tier, Kitsune's DD+ audio (+25) would still beat MeGusta's x265 (+5) even accounting for the size penalty.

**DTS example:** `show.s01e01.1080p.WEBDL.DTS-MA.x265` — DTS scores -200, leaving a net score of -200+10+5 = **-185**. Falls below `minFormatScore: 0` and will not be auto-downloaded.

---

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

---

## Allowed Qualities

### Sonarr
SDTV, WEB 480p, HDTV-720p, HDTV-1080p, WEB 720p (WEBRip + WEBDL), WEB 1080p (WEBRip + WEBDL)

### Radarr
Same as Sonarr plus: Bluray-720p, Bluray-1080p

Remux and 4K qualities are disabled — the Apple TV 4K 1st gen handles 1080p content best, and Remux files are excessively large.

---

## SABnzbd Scheduling and Quota

The optional SABnzbd task configures download scheduling and a daily quota to prevent the entire library from upgrading overnight. It uses the SABnzbd API and does **not** touch server/provider configuration.

### Schedule

| Time | Action |
|------|--------|
| 11:00pm | Resume low priority — backlog and upgrades start downloading |
| 6:00am | Pause low priority — backlog stops |
| 6:01am | Enable quota — resets the daily counter to 500GB |
| 6:02am | Resume — clears any quota-triggered pause so new daytime content can download |

**Why this matters:** New shows and movies grab at normal priority and download any time. Upgrades and backlog grab at low priority (configured in Sonarr/Radarr's download client settings) and only run during the overnight window. The daily quota prevents a library-wide upgrade sweep from consuming excessive bandwidth.

### Default Quota

500GB per day. Adjust `sabnzbd_quota_size` in `vars/sabnzbd.yml` to suit your usenet plan.

When the quota is reached, all downloads pause. The schedule re-enables it at 6:01am the following morning.

---

## Files

| File | Purpose |
|------|---------|
| `vars/connection.yml` | Service URLs and API keys (read from env vars) |
| `vars/shared-quality.yml` | Shared format definitions and scores (Sonarr + Radarr) |
| `vars/sonarr.yml` | Sonarr-specific formats, scores, allowed qualities, and size limits |
| `vars/radarr.yml` | Radarr-specific formats, scores, allowed qualities, and size limits |
| `vars/sabnzbd.yml` | SABnzbd quota and schedule settings |
| `tasks/arr-quality.yml` | Configures custom formats, quality profile, and size limits via API |
| `tasks/sabnzbd.yml` | Configures SABnzbd quota and schedule via API |
| `tasks/seerr-quality-sync.yml` | Syncs active profile IDs and API keys into Seerr (optional) |
| `playbook.yml` | Orchestrates all tasks |
| `arr-migrate.sh` | One-time migration script to move existing content to the profile |

---

## Running

```bash
# Set API keys for the services you want to configure
export SONARR_API_KEY="your-sonarr-api-key"
export RADARR_API_KEY="your-radarr-api-key"
export SABNZBD_API_KEY="your-sabnzbd-api-key"   # optional
export SEERR_API_KEY="your-seerr-api-key"         # optional

# Configure all services
ansible-playbook playbook.yml

# Configure only specific services
ansible-playbook playbook.yml --tags sonarr
ansible-playbook playbook.yml --tags radarr
ansible-playbook playbook.yml --tags sabnzbd
ansible-playbook playbook.yml --tags seerr
```

URLs default to localhost — override with `SONARR_URL`, `RADARR_URL`, `SABNZBD_URL`, or `SEERR_URL` if your services are on a different host.

The tasks are idempotent — safe to re-run after changing scores or settings.

---

## Migrating Existing Content

The playbook configures profiles and formats but does not reassign existing library content. Run the migration script once after the playbook to move all series and movies onto the new profile:

```bash
export SONARR_API_KEY="your-sonarr-api-key"
export RADARR_API_KEY="your-radarr-api-key"

# Migrate both
./arr-migrate.sh

# Or one at a time
./arr-migrate.sh sonarr
./arr-migrate.sh radarr
```

URLs default to localhost. Override with `SONARR_URL` or `RADARR_URL` if needed. Migration runs in batches of 100 items and prints progress. `BATCH_SIZE` and `PROFILE_NAME` can be overridden via environment variable.
