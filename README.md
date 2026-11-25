# vid-cli

a Small ani-cli "like" tool but for both youtube and anime

- Search YouTube, fuzzy-pick a result, and play it in `mpv`.
- Paste a video, playlist or channel URL; playlists and channels open a
  multi-select menu.
- Download video or audio with `yt-dlp`.
- Keep a plain-text history and replay it with `-c`.
- Browse anime with the public AniList GraphQL API: synopsis, genres,
  studio, next airing time, the official trailer, official per-episode
  links, and AniList's official streaming links.

YouTube access is performed **only** by the `yt-dlp` binary. There is no
custom extractor or HTML scraping. Anime metadata comes **only** from
AniList. Anime mode plays only YouTube episodes and trailers, and opens
only links that AniList marks as official.

## Showcase page

`index.html` is a self-contained landing page for the project. It presents
the features, usage examples, anime mode and install commands, and links
back to this README and the man page. Open the file directly in a browser;
it needs no server, build step, external fonts or third-party assets.

## Requirements

Required: `sh` (POSIX), `curl`, `jq`, `yt-dlp`, `mpv`, `fzf`.

Optional: `rofi` (external menu), `ffmpeg` (merging downloads and audio
extraction), `vlc` (alternate player).

Install hints:

```sh
# Debian / Ubuntu
sudo apt install curl jq yt-dlp mpv fzf ffmpeg rofi

# macOS (Homebrew)
brew install curl jq yt-dlp mpv fzf ffmpeg rofi

# Arch
sudo pacman -S curl jq yt-dlp mpv fzf ffmpeg rofi

# Termux
pkg install curl jq yt-dlp mpv fzf ffmpeg rofi
```

Package availability varies by repository and release. On Termux, `mpv`
may need a graphical environment such as Termux:X11. `ffmpeg` and `rofi`
are optional; install them only if you need them.

`vid-cli` checks required dependencies at startup, prints exactly which
ones are missing, and exits with status 2. It never installs anything.

## Install

```sh
make install                 # /usr/local/bin and /usr/local/share/man/man1
PREFIX="$HOME/.local" make install
```

Manual install:

```sh
install -d "$HOME/.local/bin" "$HOME/.local/share/man/man1"
install -m 755 vid-cli "$HOME/.local/bin/vid-cli"
install -m 644 vid-cli.1 "$HOME/.local/share/man/man1/vid-cli.1"
```

Uninstall with `make uninstall` (honours `PREFIX` and `DESTDIR`).

### Windows (Git Bash)

`vid-cli` needs a POSIX shell. Use Git Bash, which provides `sh` and `dash`,
and install the dependencies with Winget:

```sh
winget install --id yt-dlp.yt-dlp -e
winget install --id junegunn.fzf -e
winget install --id jqlang.jq -e
winget install --id shinchiro.mpv -e   # current mpv, machine scope
```

The Microsoft Store mpv also works. vid-cli resolves streams with yt-dlp and
passes direct URLs, so mpv's own ytdl hook is not used. Official episode
links open through `rundll32` when `xdg-open` is unavailable.

From Git Bash:

```sh
sh vid-cli "lofi hip hop"
```

`make` is not included with Git Bash; use the manual `install` commands
above, or run the script in place.

Run it:

```sh
vid-cli "lofi hip hop"
```

## Usage

```sh
vid-cli "query"                         # search and play
vid-cli -q 720 "query"                  # request 720p
vid-cli -a "query"                      # audio only in mpv
vid-cli -d "query"                      # download to $HOME/Videos/vid-cli
vid-cli -d -a "query"                   # audio download (needs ffmpeg)
vid-cli -n 25 --sort date "query"       # 25 results, YouTube date filter
vid-cli --sort views "query"            # client-side views sort
vid-cli --subs "query"                  # English subtitles if available
vid-cli --subs=fr "query"               # French subtitles
vid-cli "https://youtu.be/VIDEO_ID"     # play a URL directly
vid-cli "https://www.youtube.com/playlist?list=..."   # multi-select
vid-cli -c                              # history menu
vid-cli --anime "Cowboy Bebop"          # AniList browser
vid-cli -v "query"                      # VLC instead of mpv
vid-cli -h                              # all flags and environment variables
```

Run `vid-cli` with no query on a terminal to open the startup page. It
shows the current quality, player and history count, then offers four
actions: search YouTube, search anime, continue from history, and quit.
Both searches ask for free text with the same fzf prompt used elsewhere.
Without a terminal (for example in a script or pipeline), no query prints
usage and exits 1. Setting `VID_CLI_EXTERNAL_MENU=1` forces the interactive
startup page even when stdin is not a terminal.

`vid-cli --anime` without a title asks for an anime name on a terminal;
without a terminal it prints usage and exits 1.

Paste a `youtube.com`, `youtu.be`, `m.youtube.com` or
`music.youtube.com` URL. Only `http://` and `https://` URLs are accepted,
and only on those hosts; other URLs are rejected before anything is
passed to yt-dlp. A scheme-less `youtube.com/...` or `youtu.be/...` input
is treated as a URL and normalized to `https://`.

Playlists and channels are limited to the first 100 entries per
expansion. Select several with TAB and confirm with ENTER. Each selected
video is played in turn; after playback a menu offers next, previous,
replay, select and quit.

### Flags

| Flag | Meaning |
| --- | --- |
| `-q`, `--quality LEVEL` | `360`, `480`, `720` (default), `1080`, `best` or `worst`. Mapped to a yt-dlp format string. Playback uses adaptive video+audio when available; downloads merge them with ffmpeg. |
| `-a`, `--audio` | Audio only. mpv uses `--no-video`; downloads use `-x`. |
| `-d`, `--download` | Download instead of playing. |
| `-n`, `--number N` | Search result count (default 15). |
| `-c`, `--continue` | History menu, newest first. |
| `--subs[=LANG]` | Download and load subtitles when available (default `en`). |
| `--sort MODE` | `relevance`, `date` or `views`. Date uses `ytsearchdate`; views is sorted client-side and says so. |
| `--no-history` | Do not write history. |
| `-v`, `--vlc` | Use VLC instead of mpv. Both receive yt-dlp-resolved streams. |
| `--anime` | Anime mode (AniList). Prompts for a title on a terminal when none is given. |
| `-h`, `--help` | Usage, flags and environment variables. |
| `-V`, `--version` | Version. |
| `-U`, `--update` | Update instructions only; the script never modifies itself. |
| `--` | End options. |

### Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `VID_CLI_PLAYER` | `mpv` | Player binary. A name containing `vlc` selects VLC mode. |
| `VID_CLI_DL_DIR` | `$HOME/Videos/vid-cli` | Download directory. |
| `VID_CLI_HIST_DIR` | `${XDG_STATE_HOME:-$HOME/.local/state}/vid-cli` | History directory. |
| `VID_CLI_RESULTS` | `15` | Default result count. |
| `VID_CLI_EXTERNAL_MENU` | `0` | `1` uses rofi; falls back to fzf if rofi is absent. |
| `VID_CLI_YTDLP_ARGS` | empty | Extra yt-dlp arguments, split on whitespace. Example: `--limit-rate 2M`. |
| `NO_COLOR` | unset | Disable ANSI colors when set, even to an empty value. |
| `XDG_CACHE_HOME` | `$HOME/.cache` | AniList cache and temporary work directories. |
| `XDG_STATE_HOME` | `$HOME/.local/state` | Default location for history. |

`VID_CLI_YTDLP_ARGS` is the one intentional word-splitting boundary:
it exists to pass multiple yt-dlp arguments from the environment. It is
split with globbing disabled, never evaluated, and never used to build a
shell command line. Quote handling inside that variable is not supported;
one argument must not contain spaces. vid-cli itself adds no login,
paywall, DRM or region workarounds through this or any other option.

### Files

- History: `$VID_CLI_HIST_DIR/histfile` (default under XDG state).
  Format: `timestamp<TAB>mode<TAB>id_or_url<TAB>title`, newest first,
  capped at 500 lines. Anime entries use `anime:<AniList id>`.
- AniList cache: `$XDG_CACHE_HOME/vid-cli/anilist-*.json`, with a matching
  `.ts` stamp. Entries are reused for 10 minutes.
- Temporary files: `$XDG_CACHE_HOME/vid-cli/tmp.XXXXXX`, plus short-lived
  AniList request files in the same directory; all are removed by a trap.
- Downloads: `$VID_CLI_DL_DIR`.

Nothing is written outside the XDG directories and the download
directory. No telemetry, analytics or background update checks are used.

## Anime mode

```sh
vid-cli --anime "Cowboy Bebop"
```

Matches are shown as `Romaji (English) | format | episodes | season year |
score`. Selecting one fetches its details (also cached) and shows the
synopsis with HTML tags removed, genres, main studio, status and the next
airing episode converted to local time. The action menu then offers:

1. **Browse official episodes** — AniList's `streamingEpisodes` list, with
   the service name and episode title. YouTube episodes play in your
   player; links to licensed services such as Crunchyroll open in the
   browser. If AniList has no per-episode links, a clear fallback message
   points to the series-level links instead.
2. Play the official YouTube trailer.
3. Print and open AniList's official `STREAMING` links.
4. Search YouTube for official clips/PVs.
5. Quit.

AniList errors are reported without a stack trace. HTTP 429 is retried
once with a short delay: a numeric `Retry-After` of at most 30 seconds is
honoured, and a missing or non-numeric value defaults to 5 seconds. Longer
limits are not retried; outages and longer rate limits produce a friendly
message and exit status 3. Responses are cached for 10 minutes to avoid
unnecessary requests.

## Decisions

These are the simple choices made where the specification left room:

1. The search list comes from `yt-dlp --flat-playlist --print`. YouTube
   search entries often have no upload date in flat mode, so that column
   can show `?`; `--sort date` uses the `ytsearchdate` filter.
2. `--sort views` sorts the fetched results on the client because yt-dlp
   has no views search filter. A message states this.
3. Multi-selected videos are played one at a time with a post-play menu,
   not as one long mpv playlist. This makes next/previous/replay work.
4. Anime titles are displayed as romaji with the English title in
   parentheses; the native title is not appended.
5. rofi receives the full `id<TAB>display` line because it lacks fzf's
   hidden-column support. fzf hides the id with `--with-nth=2..`.
6. `--subs` has an optional argument. A following short token that looks
   like a language code is consumed. For a query that could look like a
   language tag (for example `it` or `lo-fi`), use
   `--subs=en -- "query"` to avoid ambiguity.
7. Both players receive streams resolved by yt-dlp. When yt-dlp returns
   separate video and audio, mpv gets the audio as `--audio-file`. VLC mode
   uses a single-file format because VLC cannot attach a separate audio URL.
8. Audio downloads require ffmpeg. Video downloads fall back to a
   single-file format when ffmpeg is absent.
9. Anime trailer action always plays the trailer. `-d` affects the
   official episode browser (for YouTube episodes) and the YouTube clip
   search action.
10. A playlist/channel expansion shows at most 100 entries.
11. URL host validation accepts exact hosts and the listed subdomains
    only; lookalike domains such as `youtube.com.example` are rejected.
12. The tool never self-updates. `-U` only prints commands you can run.
13. On MSYS/Cygwin, paths passed to native programs inside option values
    (yt-dlp `-o`, mpv `--sub-file`) are converted with `cygpath -m`.

## Legal

You are responsible for complying with YouTube's Terms of Service and
with your local copyright law. vid-cli is for personal use. It does not
host, mirror or redistribute content. It does not bypass paywalls, DRM,
login walls or geographic restrictions. If yt-dlp reports that a video is
unavailable, private, age-gated or region-locked, vid-cli shows a message
and moves on.

Anime mode contains no third-party streaming scrapers and never decrypts
or proxies a stream. It uses AniList metadata plus the official
per-episode and series links that AniList lists. Respect the terms of
those services.

## Troubleshooting

### yt-dlp is outdated

YouTube changes frequently. Update yt-dlp first:

```sh
sudo apt update && sudo apt install yt-dlp     # Debian/Ubuntu
brew upgrade yt-dlp                             # macOS
sudo pacman -Syu yt-dlp                         # Arch
pkg upgrade yt-dlp                              # Termux
python -m pip install -U yt-dlp                 # pip installs
```

Then retry. `vid-cli -U` prints these commands; it does not run them.

### mpv cannot play

- Confirm `mpv` and `yt-dlp` run by themselves.
- Test stream resolution with `yt-dlp -f "bv*+ba/b" -g URL`.
- If a requested resolution is unavailable, try `-q best` or `-q 720`.
- Playback does not need `ffmpeg`; install it for merged downloads and audio
  extraction.
- For VLC, try `-q 720` or `-q best`; VLC mode is limited to single-file
  streams.
- On Windows, run from Git Bash. The Store mpv build is old but works because
  vid-cli passes direct stream URLs instead of using mpv's ytdl hook.
- If a video is private, age-gated or region-locked, vid-cli cannot and
  will not bypass that. It reports the failure and continues with the
  next queue item.

### Termux notes

```sh
pkg install curl jq yt-dlp mpv fzf ffmpeg
pkg install rofi          # optional; needs a graphical session
```

- Use `termux-open` (installed by Termux) for opening AniList streaming
  links and official episode pages; vid-cli detects it automatically.
- mpv needs a working display, for example Termux:X11.
- Downloads default to `$HOME/Videos/vid-cli`; grant storage access if
  you want them elsewhere under shared storage.
- Termux may need `pkg upgrade` after large package updates.

### Menus and cancellation

Ctrl-C in fzf/rofi exits quietly with status 0 (or 130 when interrupted
by the terminal signal) and no extra error output. If there are no search
results, vid-cli prints a message and exits with status 4.

### History

Set `VID_CLI_HIST_DIR` to move the history. Use `--no-history` for a
private session. History is plain TSV and can be inspected or trimmed
with ordinary text tools.

## Development and tests

```sh
make check     # dash -n vid-cli, then shellcheck if installed
make test      # offline tests with fake yt-dlp, mpv, fzf and curl
```

The tests use a saved AniList response at
`tests/fixtures/anilist.json`, fake binaries (including `xdg-open`) placed
first on `PATH`, and temporary XDG directories. No network access is
required. See
`CONTRIBUTING.md` for code style and how to add a menu action.

## Exit status

`0` success or menu cancel, `1` usage/unsupported URL, `2` missing
dependency, `3` network/API or playback/download failure, `4` nothing
found.
