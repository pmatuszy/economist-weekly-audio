# economist-weekly-audio

Download The Economist weekly audio edition, split into chapters, add artwork, speed up and normalize speech for listening, and pack results.

**Topics:** `economist`, `the-economist`, `theeconomist`, `audio`, `ffmpeg`, `bash`, `mp3`, `audiobook`, `weekly-edition`

## Publish to GitHub

When creating the repository (requires [GitHub CLI](https://cli.github.com/)):

```bash
gh repo create economist-weekly-audio --public --source=. --remote=origin --push \
  --description "Download The Economist weekly audio edition, split into chapters, add artwork, speed up for listening." \
  --add-topic economist --add-topic the-economist --add-topic theeconomist \
  --add-topic audio --add-topic ffmpeg --add-topic bash --add-topic mp3 \
  --add-topic audiobook --add-topic weekly-edition
```

If the repo already exists, set metadata with:

```bash
gh repo edit --description "Download The Economist weekly audio edition, split into chapters, add artwork, speed up for listening." \
  --add-topic economist --add-topic the-economist --add-topic theeconomist \
  --add-topic audio --add-topic ffmpeg --add-topic bash --add-topic mp3 \
  --add-topic audiobook --add-topic weekly-edition
```

## Setup

1. Clone this repository.
2. Provide config — pick one:

   **A. Private config repo** (recommended if you use GitHub for secrets):

   ```bash
   git clone https://github.com/pmatuszy/economist-weekly-audio.git
   git clone git@github.com:pmatuszy/economist-weekly-audio-private.git   # private — you only
   ```

   Keep both repos as siblings; scripts auto-load `../economist-weekly-audio-private/economist.local.conf`.

   **B. Local file** (no private repo):

   ```bash
   cp economist.conf.example economist.local.conf
   # edit economist.local.conf
   ```

3. Config variables:

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

- **Public repo:** never commit `economist.local.conf` (gitignored).
- **Private repo:** [economist-weekly-audio-private](https://github.com/pmatuszy/economist-weekly-audio-private) — your RSS URL and healthcheck pings, visible only to you.

Others using the public repo copy `economist.conf.example` or maintain their own private config repo.

If you previously had URLs in scripts that were published anywhere, rotate your Healthchecks UUID and regenerate your Economist feed URL.

## Layout

```
economist-weekly-audio/              # public
├── economist.conf.example
├── economist.local.conf             # optional local copy (gitignored)
└── scripts/

economist-weekly-audio-private/      # private sibling clone
└── economist.local.conf             # your secrets on GitHub, not public
```
