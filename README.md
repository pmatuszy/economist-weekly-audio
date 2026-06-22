# economist-weekly-audio

Download The Economist weekly audio edition, split into chapters, add artwork, speed up and normalize speech for listening, and pack results.

**Topics:** `economist`, `the-economist`, `theeconomist`, `audio`, `ffmpeg`, `bash`, `mp3`, `audiobook`, `weekly-edition`

## Setup

1. Clone this repository.
2. Create your local config (not committed to git):

   ```bash
   cp economist.conf.example economist.local.conf
   ```

3. Edit `economist.local.conf`:

   | Variable | Required | Description |
   |----------|----------|-------------|
   | `ECONOMIST_RSS_URL` | yes | Your personal Economist audio RSS URL |
   | `HEALTHCHECK_URL` | no | Healthchecks.io ping base URL (no `/start` or `/fail` suffix). Leave empty to disable. |
   | `ECONOMIST_BASE_DIR` | no | Data root (default: `/worek/economist/theEconomist`) |
   | `FFMPEG_PATH` | no | ffmpeg binary (default: `/usr/local/bin/ffmpeg`) |
   | `ECONOMIST_FILE_OWNER` | no | e.g. `user:group` for `chown`; empty to skip |

4. Install dependencies: `curl`, `wget`, `ffmpeg`, `ffprobe`, `rar`, `rename`, `xmllint` (optional), `curl-impersonate` (for artwork).

## Usage

Run the full pipeline:

```bash
./scripts/0-economist-runme.sh
```

Optional edition date:

```bash
./scripts/0-economist-runme.sh 2025-09-13
```

Individual steps (normally called by `0-economist-runme.sh`):

| Script | Step |
|--------|------|
| `1-economist-sciagnij.sh` | Download MP3 from RSS |
| `2-economist-obrob.sh` | Split chapters, artwork, RAR |
| `3-zmien-szybkosc-podbij-glosnosc.sh` | Speed + loudness (ffmpeg) |
| `4-wszystko-obrobione-przenies-wyniki.sh` | Move to `_obrobione` |

Override config path:

```bash
ECONOMIST_CONF=/path/to/my.conf ./scripts/0-economist-runme.sh
```

## Secrets

Never commit `economist.local.conf`. It is listed in `.gitignore`.

If you previously had URLs in scripts that were published anywhere, rotate your Healthchecks UUID and regenerate your Economist feed URL.

## Layout

```
economist-weekly-audio/
├── economist.conf.example    # template (safe to commit)
├── economist.local.conf      # your secrets (gitignored)
├── scripts/
│   ├── _load-config.sh
│   ├── 0-economist-runme.sh
│   └── ...
```
