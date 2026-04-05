#!/usr/bin/env python3
"""
Trigger Sonarr/Radarr searches for all HEVC-encoded episodes and movies
to allow quality profile upgrades to H.264 for Apple TV direct play.

Uses the same env vars as the arr-quality-profiles vault.yml:
  export SONARR_URL="http://sonarr.lan"
  export SONARR_API_KEY="..."
  export RADARR_URL="http://radarr.lan"
  export RADARR_API_KEY="..."
"""

import os
import sys
import time
import requests

SONARR_URL = os.environ.get("SONARR_URL", "http://sonarr.lan").rstrip("/")
SONARR_KEY = os.environ.get("SONARR_API_KEY", "")
RADARR_URL = os.environ.get("RADARR_URL", "http://radarr.lan").rstrip("/")
RADARR_KEY = os.environ.get("RADARR_API_KEY", "")

HEVC_CODECS = {"x265", "h265", "hevc"}
BATCH_SIZE  = 100
RATE_LIMIT  = 1  # seconds between batches


def is_hevc(media_info: dict) -> bool:
    codec = media_info.get("videoCodec", "").lower()
    return any(h in codec for h in HEVC_CODECS)


def sonarr_search():
    if not SONARR_KEY:
        print("[sonarr] SONARR_API_KEY not set — skipping")
        return

    headers = {"X-Api-Key": SONARR_KEY}

    print("[sonarr] Fetching series list...")
    series = requests.get(f"{SONARR_URL}/api/v3/series", headers=headers).json()
    print(f"[sonarr] {len(series)} series found")

    hevc_episode_ids = []

    for show in series:
        files = requests.get(
            f"{SONARR_URL}/api/v3/episodefile",
            params={"seriesId": show["id"]},
            headers=headers,
        ).json()

        hevc_files = [f for f in files if is_hevc(f.get("mediaInfo", {}))]
        if not hevc_files:
            continue

        print(f"[sonarr] {show['title']}: {len(hevc_files)} HEVC file(s)")

        for f in hevc_files:
            episodes = requests.get(
                f"{SONARR_URL}/api/v3/episode",
                params={"episodeFileId": f["id"]},
                headers=headers,
            ).json()
            hevc_episode_ids.extend(ep["id"] for ep in episodes)

    if not hevc_episode_ids:
        print("[sonarr] No HEVC episodes found")
        return

    print(f"\n[sonarr] Triggering search for {len(hevc_episode_ids)} HEVC episodes...")
    for i in range(0, len(hevc_episode_ids), BATCH_SIZE):
        batch = hevc_episode_ids[i : i + BATCH_SIZE]
        resp = requests.post(
            f"{SONARR_URL}/api/v3/command",
            headers=headers,
            json={"name": "EpisodeSearch", "episodeIds": batch},
        )
        print(f"[sonarr] Batch {i // BATCH_SIZE + 1}: {resp.status_code} — episodes {i+1}-{i+len(batch)}")
        if i + BATCH_SIZE < len(hevc_episode_ids):
            time.sleep(RATE_LIMIT)

    print("[sonarr] Done")


def radarr_search():
    if not RADARR_KEY:
        print("[radarr] RADARR_API_KEY not set — skipping")
        return

    headers = {"X-Api-Key": RADARR_KEY}

    print("\n[radarr] Fetching movie list...")
    movies = requests.get(f"{RADARR_URL}/api/v3/movie", headers=headers).json()
    print(f"[radarr] {len(movies)} movies found")

    hevc_movie_ids = []

    for movie in movies:
        if not movie.get("hasFile"):
            continue
        file_id = movie.get("movieFile", {}).get("id")
        if not file_id:
            continue

        f = requests.get(
            f"{RADARR_URL}/api/v3/moviefile/{file_id}", headers=headers
        ).json()

        if is_hevc(f.get("mediaInfo", {})):
            print(f"[radarr] {movie['title']}: HEVC")
            hevc_movie_ids.append(movie["id"])

    if not hevc_movie_ids:
        print("[radarr] No HEVC movies found")
        return

    print(f"\n[radarr] Triggering search for {len(hevc_movie_ids)} HEVC movies...")
    resp = requests.post(
        f"{RADARR_URL}/api/v3/command",
        headers=headers,
        json={"name": "MoviesSearch", "movieIds": hevc_movie_ids},
    )
    print(f"[radarr] {resp.status_code}")
    print("[radarr] Done")


if __name__ == "__main__":
    if not SONARR_KEY and not RADARR_KEY:
        print("Error: set SONARR_API_KEY and/or RADARR_API_KEY environment variables")
        sys.exit(1)

    sonarr_search()
    radarr_search()
    print("\nAll searches triggered. Sonarr/Radarr will grab H.264 releases where available.")
