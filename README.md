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
   mkdir -p "${profile_location_dir:-$HOME}/github"
   git clone https://github.com/pmatuszy/economist-weekly-audio.git "${profile_location_dir:-$HOME}/github/economist-weekly-audio"
   git clone git@github.com:pmatuszy/economist-weekly-audio-private.git "${profile_location_dir:-$HOME}/github/economist-weekly-audio-private"
   ```

   Keep both repos as siblings under `${profile_location_dir:-$HOME}/github/`. Run `install.sh` to copy config into `${profile_location_dir:-$HOME}/conf/economist.local.conf`.

   **B. Local file** (no private repo):

   ```bash
   cp economist.conf.example economist.local.conf
   chmod 600 economist.local.conf
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
| `1-economist-download.sh` | Download MP3 from RSS |
| `2-economist-process-edition.sh` | Split chapters, artwork, RAR |
| `3-economist-speedup-loudness.sh` | Speed + loudness (ffmpeg) |
| `4-economist-move-results.sh` | Move to `_obrobione` |

Override config path:

```bash
ECONOMIST_CONF=/path/to/my.conf ./scripts/0-economist-runme.sh
```

## Secrets

- **Public repo:** never commit `economist.local.conf` (gitignored).
- **Private repo:** [economist-weekly-audio-private](https://github.com/pmatuszy/economist-weekly-audio-private) — your RSS URL and healthcheck pings, visible only to you.
- **Permissions:** `economist.local.conf` must be mode `0600`. Scripts exit if the file is group- or world-readable.

Others using the public repo copy `economist.conf.example` or maintain their own private config repo.

If you previously had URLs in scripts that were published anywhere, rotate your Healthchecks UUID and regenerate your Economist feed URL.

## Server deployment

### 1. First-time clone

Base directory is `${profile_location_dir:-$HOME}` (set `profile_location_dir` on the server if your layout is not under `$HOME`).

```bash
mkdir -p "${profile_location_dir:-$HOME}/github"
git clone https://github.com/pmatuszy/economist-weekly-audio.git "${profile_location_dir:-$HOME}/github/economist-weekly-audio"
git clone git@github.com:pmatuszy/economist-weekly-audio-private.git "${profile_location_dir:-$HOME}/github/economist-weekly-audio-private"
```

Keep both repos as siblings under `${profile_location_dir:-$HOME}/github/`.

### 2. Interactive install into `bin/` and `conf/`

`install.sh` creates `${profile_location_dir:-$HOME}/conf/` (sibling of `bin/`) and copies `economist.local.conf` there from the private repo when needed.

```bash
cd "${profile_location_dir:-$HOME}/github/economist-weekly-audio"
chmod +x install.sh
./install.sh
```

`install.sh` is interactive: it shows the repo path, config plan, wrappers to create, and asks **Proceed with installation? [y/N/q]** before writing anything. If `conf/economist.local.conf` already exists and the private repo has a copy, it offers to replace it (**20s** timeout, default **no**). If old unnumbered wrappers (`economist-runme.sh`, etc.) exist in `bin/`, it offers to remove them after install.

Pull latest from GitHub and install in one step:

```bash
./install.sh --pull
```

Skip the prompt after you trust the layout:

```bash
./install.sh --pull -y
```

Ensure `${profile_location_dir:-$HOME}/bin` is on your `PATH` (add to your shell profile if needed):

```bash
export PATH="${profile_location_dir:-$HOME}/bin:${PATH}"
```

### 3. Update after changes on GitHub

```bash
cd "${profile_location_dir:-$HOME}/github/economist-weekly-audio"
./install.sh --pull
```

### 4. Run the pipeline

```bash
"${profile_location_dir:-$HOME}/bin/0-economist-runme.sh"
```

Suggested layout:

```
${profile_location_dir:-$HOME}/github/economist-weekly-audio/          # scripts (git clone)
${profile_location_dir:-$HOME}/github/economist-weekly-audio-private/  # config source (git clone)
${profile_location_dir:-$HOME}/conf/economist.local.conf              # installed secrets (mode 600)
${profile_location_dir:-$HOME}/bin/0-economist-runme.sh                # wrapper -> repo script
```

## Layout

```
economist-weekly-audio/              # public
├── economist.conf.example
├── economist.local.conf             # optional local copy (gitignored)
├── install.sh                       # interactive install into bin/ and conf/
└── scripts/

economist-weekly-audio-private/      # private sibling clone (${profile_location_dir:-$HOME}/github/)
└── economist.local.conf             # your secrets on GitHub, not public
```
