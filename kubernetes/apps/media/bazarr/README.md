# Bazarr

Bazarr downloads text subtitles (SRT) for the shows and movies that Sonarr and Radarr manage.
It writes each `.srt` file next to its video file, and Plex picks it up as an external
subtitle track.

## Why

Blu-ray rips usually contain only PGS subtitles. PGS subtitles are images, and most Plex
clients cannot draw them, so Plex burns them into the video. On the iGPU, the burn-in adds
`hwupload` and `overlay_vaapi` steps to the VAAPI pipeline. That pipeline then runs out of
frame buffers, and the picture breaks up. The Plex log shows this as:

```
[hevc @ ...] get_buffer() failed
Error submitting packet to decoder: Out of memory
[hevc @ ...] Could not find ref with POC ...
```

This is a failure, not a speed limit. The iGPU decodes and encodes 10-bit HEVC in hardware
without problems when there is no burn-in. Clients draw text subtitles themselves, so with an
SRT track the video direct-plays, or the transcode has no overlay step. Hardware transcoding
stays on.

To find which subtitle tracks a file has:

```bash
kubectl -n media exec deploy/plex -- "/usr/lib/plexmediaserver/Plex Transcoder" \
  -hide_banner -i "/media/tv/<show>/<season>/<file>.mkv" 2>&1 | grep Subtitle
```

`hdmv_pgs_subtitle` means image-based subtitles.

## Paths

Bazarr mounts `media-tv` at `/tv` and `media-movies` at `/movies`, which are the same paths
that Sonarr and Radarr use. Thus Bazarr needs no path mappings. Plex mounts the same volumes
read-only at `/media/tv` and `/media/movies`.

Bazarr does not cover the legacy `plex-library` share (`/tv`, `/movies`, `/concerts` in the
Plex pod), because Sonarr and Radarr do not manage it.

## URL base

Bazarr has no URL base setting in its environment variables, but it reads Dynaconf overrides.
`DYNACONF_GENERAL__BASE_URL=/bazarr` sets `general.base_url`, so the app serves at `/bazarr/`
with no `stripPrefix` middleware. The probes use `/bazarr/api/system/ping`.

## Setup in the UI

The settings below are kept in the config volume, not in git, because they include the
OpenSubtitles login. Do them once, at `/bazarr` on the media domain.

1. **Settings → Languages:** make a profile with English only. Make it the default profile
   for series and for movies.
2. **Settings → Providers:** add OpenSubtitles.com and enter the account login. A free
   account has a daily download limit.
3. **Settings → Sonarr:** host `sonarr.media`, port `8989`, base URL `/sonarr`, and the
   Sonarr API key (Sonarr → Settings → General).
4. **Settings → Radarr:** host `radarr.media`, port `7878`, base URL `/radarr`, and the
   Radarr API key.
5. On a series or movie page, select **Search** to download the missing subtitles. For the
   full library, use **Wanted → Search All**, but note the provider's daily limit.

In Plex, select the SRT track in the player's subtitle menu. If the new file does not show,
refresh the item's metadata.
