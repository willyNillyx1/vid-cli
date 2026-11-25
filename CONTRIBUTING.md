# Contributing

Keep changes small and in the style of the existing script. One POSIX
shell file, named functions, no build step.

## Code style

- `#!/bin/sh` and `set -u`; the script must pass `dash -n` and
  `shellcheck`.
- No `eval`, no arrays, no `[[ ]]`, no unquoted user input. Detected
  exceptions are the documented `VID_CLI_YTDLP_ARGS` whitespace split and
  `case` patterns on menu action names.
- Prefer `printf`, `[ ]`, `case`, and quoted expansions. Avoid `local`.
- All menus go through `pick()` with newline-separated,
  tab-delimited `id<TAB>display` records. Do not call `fzf` or `rofi`
  directly from a feature.
- YouTube requests must go through `yt_list()`/`ytdlp()` and yt-dlp
  only. Do not parse YouTube HTML or add extractors.
- Anime requests must go through `anilist_query()`. Do not add any other
  anime source, scraper, mirror, or player deobfuscator.
- Keep temporary files inside `$TMP_WORK` when possible. Any temporary
  file created elsewhere must be registered in `cleanup()` so the existing
  EXIT/INT/TERM/HUP traps remove it.
- Normal messages go to stderr with `msg`; fatal errors use `die` and the
  documented exit codes (1 usage, 2 dependency, 3 network/API, 4 empty).

## Adding a menu action

1. Add a line to the relevant `printf` menu, for example in `anime_menu`:
   `action<TAB>5. Do the thing`.
2. Add a matching `case` branch that calls a named function, not inline
   network or player logic.
3. If it opens a URL, it must come from AniList and be type `STREAMING`.
   Pass it through `open_url` after the http(s) check.
4. If it plays video, call `play` (or `download`) with a URL that came
   from yt-dlp or from an AniList YouTube trailer id.
5. Add an offline test with the fake binaries. Record the new argument
   in the fake only if necessary.

## Tests

```sh
make check
make test
```

`tests/run.sh` creates fake `yt-dlp`, `mpv`, `fzf`, `curl`, `ffmpeg` and
`xdg-open` binaries in a temporary directory, prepends them to `PATH`, and
uses `tests/fixtures/anilist.json`. It must not touch the network, the real
home directory, or the real history/cache. Use `assert_eq`,
`assert_status` and `assert_contains` from the test script.

If you add a new exit path, state its status in `README.md`, the man page
and the test summary where useful.
