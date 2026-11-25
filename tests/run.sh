#!/bin/sh
# Offline tests for vid-cli. Fake yt-dlp, mpv, fzf, curl and ffmpeg are placed
# first on PATH. No network access is used.
set -u

unset CDPATH
ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 1
SH=${SH:-dash}
if ! command -v "$SH" >/dev/null 2>&1; then
    SH='sh'
fi

if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'tests: jq is required' >&2
    exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/vid-cli-test.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
TAB=$(printf '\t')

BIN=$TMP/bin
FAKE=$TMP/fake
LOG=$TMP/log
mkdir -p "$BIN" "$FAKE" "$LOG" "$TMP/home" "$TMP/cache" "$TMP/state" "$TMP/dl"

# ----------------------------- fake binaries -------------------------------

cat >"$BIN/yt-dlp" <<'EOF'
#!/bin/sh
: "${FAKE_LOG:?}" "${FAKE_DATA:?}"
printf '%s\n' "$*" >>"$FAKE_LOG/yt-dlp.args"
case " $* " in
    *" -g "*)
        if [ "${FAKE_RESOLVE_RC:-0}" -ne 0 ]; then
            printf '%s\n' 'fake resolve failure' >&2
            exit "$FAKE_RESOLVE_RC"
        fi
        printf '%s\n' 'https://stream.invalid/video'
        if [ "${FAKE_TWO_STREAMS:-0}" = 1 ]; then
            printf '%s\n' 'https://stream.invalid/audio'
        fi
        exit 0
        ;;
esac
case " $* " in
    *ytsearch*)
        cat "${FAKE_SEARCH_FILE:-$FAKE_DATA/search.tsv}"
        exit "${FAKE_SEARCH_RC:-0}"
        ;;
esac
case " $* " in
    *" -o "*|*" -f "*)
        : >"$FAKE_DATA/downloaded"
        exit "${FAKE_DL_RC:-0}"
        ;;
esac
cat "$FAKE_DATA/playlist.tsv"
exit "${FAKE_LIST_RC:-0}"
EOF

cat >"$BIN/fzf" <<'EOF'
#!/bin/sh
: "${FAKE_LOG:?}" "${FAKE_DATA:?}"
printf '%s\n' "$*" >>"$FAKE_LOG/fzf.args"
# ask() uses fzf as a free-text prompt: --print-query with no input.
case " $* " in
    *" --print-query "*)
        printf '%s\n' "$*" >>"$FAKE_LOG/fzf.ask"
        printf '%s\n' "${FAKE_FZF_QUERY:-cats}"
        exit 0
        ;;
esac
_in="$FAKE_DATA/fzf.$$.in"
cat >"$_in"
if [ ! -s "$_in" ]; then
    rm -f "$_in"
    exit 1
fi
cp "$_in" "$FAKE_DATA/fzf.last"
_mode=${FAKE_FZF_MODE:-first}
_n=0
if [ -f "$FAKE_DATA/fzf.count" ]; then
    _n=$(cat "$FAKE_DATA/fzf.count")
fi
_n=$((_n + 1))
printf '%s\n' "$_n" >"$FAKE_DATA/fzf.count"
case $_mode in
    cancel)
        rm -f "$_in"
        exit 130
        ;;
    all)
        cat "$_in"
        ;;
    allfirst)
        if [ "$_n" -eq 1 ]; then cat "$_in"; else sed -n '1p' "$_in"; fi
        ;;
    last)
        tail -n 1 "$_in"
        ;;
    firstlast)
        if [ "$_n" -eq 1 ]; then sed -n '1p' "$_in"; else tail -n 1 "$_in"; fi
        ;;
    linksquit)
        case $_n in
            1) sed -n '3p' "$_in" ;;
            2) sed -n '1p' "$_in" ;;
            *) tail -n 1 "$_in" ;;
        esac
        ;;
    trailerquit)
        case $_n in
            1) sed -n '2p' "$_in" ;;
            *) tail -n 1 "$_in" ;;
        esac
        ;;
    episodesopen)
        case $_n in
            1) sed -n '1p' "$_in" ;;
            2) sed -n '1p' "$_in" ;;
            *) tail -n 1 "$_in" ;;
        esac
        ;;
    episodesplay)
        case $_n in
            1) sed -n '1p' "$_in" ;;
            2) tail -n 1 "$_in" ;;
            *) tail -n 1 "$_in" ;;
        esac
        ;;
    homeyoutube)
        case $_n in
            1) sed -n '1p' "$_in" ;;
            2) sed -n '1p' "$_in" ;;
            *) tail -n 1 "$_in" ;;
        esac
        ;;
    homeanime)
        case $_n in
            1) sed -n '2p' "$_in" ;;
            2) sed -n '1p' "$_in" ;;
            *) tail -n 1 "$_in" ;;
        esac
        ;;
    homehistory)
        case $_n in
            1) sed -n '3p' "$_in" ;;
            2) sed -n '1p' "$_in" ;;
            *) tail -n 1 "$_in" ;;
        esac
        ;;
    homequit)
        tail -n 1 "$_in"
        ;;
    *)
        sed -n '1p' "$_in"
        ;;
esac
rm -f "$_in"
exit 0
EOF

cat >"$BIN/mpv" <<'EOF'
#!/bin/sh
: "${FAKE_LOG:?}"
printf '%s\n' "$*" >>"$FAKE_LOG/mpv.args"
exit "${FAKE_MPV_RC:-0}"
EOF

cat >"$BIN/ffmpeg" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$BIN/xdg-open" <<'EOF'
#!/bin/sh
: "${FAKE_LOG:?}"
printf '%s\n' "$*" >>"$FAKE_LOG/xdg-open.args"
exit 0
EOF

cat >"$BIN/curl" <<'EOF'
#!/bin/sh
: "${FAKE_LOG:?}" "${FAKE_DATA:?}" "${ANILIST_FIXTURE:?}"
printf 'call\n' >>"$FAKE_LOG/curl.args"
_out=
_hdr=
while [ "$#" -gt 0 ]; do
    case $1 in
        -o) _out=$2; shift 2 ;;
        -D) _hdr=$2; shift 2 ;;
        -w|-d|-H|-X|--connect-timeout|--max-time) shift 2 ;;
        *) shift ;;
    esac
done
_mode=${FAKE_CURL_MODE:-fixture}
_status=200
_body=
if [ "$_mode" = error ]; then
    _status=500
    _body='{"errors":[{"message":"upstream failure"}]}'
elif [ "$_mode" = 429once ]; then
    _n=0
    if [ -f "$FAKE_DATA/curl.count" ]; then _n=$(cat "$FAKE_DATA/curl.count"); fi
    _n=$((_n + 1))
    printf '%s\n' "$_n" >"$FAKE_DATA/curl.count"
    if [ "$_n" -eq 1 ]; then
        _status=429
        _body='{"errors":[{"message":"Too Many Requests"}]}'
    fi
elif [ "$_mode" = 429long ]; then
    _status=429
    _body='{"errors":[{"message":"Too Many Requests"}]}'
fi
if [ -n "$_out" ]; then
    if [ -n "$_body" ]; then
        printf '%s' "$_body" >"$_out"
    else
        cat "$ANILIST_FIXTURE" >"$_out"
    fi
fi
if [ -n "$_hdr" ]; then
    if [ "$_status" = 429 ]; then
        _retry=0
        if [ "$_mode" = 429long ]; then _retry=120; fi
        printf 'HTTP/1.1 429 Too Many Requests\r\nRetry-After: %s\r\n\r\n' "$_retry" >"$_hdr"
    else
        printf 'HTTP/1.1 %s\r\n\r\n' "$_status" >"$_hdr"
    fi
fi
printf '%s' "$_status"
EOF

chmod +x "$BIN/yt-dlp" "$BIN/fzf" "$BIN/mpv" "$BIN/ffmpeg" "$BIN/xdg-open" "$BIN/curl"

# ------------------------------- fake data ---------------------------------

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    'dQw4w9WgXcQ' 'Never Gonna Give You Up' 'Rick Astley' '123' '1234567' '20091025' \
    'aaaaaaaaaaa' 'Second Video' 'Another Channel' '3600' '999' '20240102' \
    'bbbbbbbbbbb' 'Third Video' 'NA' 'NA' 'NA' 'NA' >"$FAKE/search.tsv"
: >"$FAKE/empty.tsv"

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    'aaaaaaaaaaa' 'Playlist One' 'Channel A' '120' '1000' '20240101' \
    'bbbbbbbbbbb' 'Playlist Two' 'Channel B' '240' '2000' '20240102' >"$FAKE/playlist.tsv"

# ------------------------------- helpers -----------------------------------

pass=0
fail=0

ok() {
    pass=$((pass + 1))
    printf 'ok %d - %s\n' "$pass" "$1"
}

notok() {
    fail=$((fail + 1))
    printf 'not ok - %s\n' "$1"
    if [ "$#" -ge 2 ] && [ -n "$2" ]; then
        printf '# %s\n' "$2"
    fi
}

assert_eq() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        notok "$1" "expected [$2], got [$3]"
    fi
}

assert_status() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        notok "$1" "expected exit $2, got $3"
    fi
}

assert_contains() {
    case $3 in
        *"$2"*) ok "$1" ;;
        *) notok "$1" "missing [$2] in [$3]" ;;
    esac
}

assert_not_contains() {
    case $3 in
        *"$2"*) notok "$1" "unexpected [$2] in [$3]" ;;
        *) ok "$1" ;;
    esac
}

unit_env() {
    HOME="$TMP/home"
    XDG_CACHE_HOME="$TMP/cache"
    XDG_STATE_HOME="$TMP/state"
    VID_CLI_HIST_DIR="$TMP/state/vid-cli"
    VID_CLI_DL_DIR="$TMP/dl"
    PATH="$BIN:$PATH"
    NO_COLOR=1
    VID_CLI_YTDLP_ARGS=
    VID_CLI_EXTERNAL_MENU=0
    FAKE_LOG="$LOG"
    FAKE_DATA="$FAKE"
    ANILIST_FIXTURE="$ROOT/tests/fixtures/anilist.json"
    export HOME XDG_CACHE_HOME XDG_STATE_HOME VID_CLI_HIST_DIR VID_CLI_DL_DIR
    export PATH NO_COLOR VID_CLI_YTDLP_ARGS VID_CLI_EXTERNAL_MENU
    export FAKE_LOG FAKE_DATA ANILIST_FIXTURE
    VID_CLI_SOURCE_ONLY=1
    export VID_CLI_SOURCE_ONLY
    # shellcheck source=/dev/null
    . "$ROOT/vid-cli"
}

run_cli() {
    HOME="$TMP/home" \
    XDG_CACHE_HOME="$TMP/cache" \
    XDG_STATE_HOME="$TMP/state" \
    VID_CLI_HIST_DIR="$TMP/state/vid-cli" \
    VID_CLI_DL_DIR="$TMP/dl" \
    VID_CLI_PLAYER=mpv \
    VID_CLI_YTDLP_ARGS='' \
    VID_CLI_EXTERNAL_MENU=0 \
    NO_COLOR=1 \
    FAKE_LOG="$LOG" \
    FAKE_DATA="$FAKE" \
    ANILIST_FIXTURE="$ROOT/tests/fixtures/anilist.json" \
    PATH="$BIN:$PATH" \
    "$SH" "$ROOT/vid-cli" "$@"
}

rm -rf "$TMP/state/vid-cli" "$TMP/cache/vid-cli" "$TMP/work" "$TMP/dl"
mkdir -p "$TMP/work" "$TMP/dl"

# -------------------------------- tests ------------------------------------

# 1. Syntax.
if "$SH" -n "$ROOT/vid-cli"; then
    ok 'POSIX syntax check'
else
    notok 'POSIX syntax check'
fi

# 2. Search parsing and display formatting.
out=$(
    unit_env
    TMP_WORK="$TMP/work"
    mkdir -p "$TMP_WORK"
    yt_search 'cats'
)
rc=$?
assert_status 'search exits 0' 0 "$rc"
first=$(printf '%s\n' "$out" | sed -n '1p')
second=$(printf '%s\n' "$out" | sed -n '2p')
third=$(printf '%s\n' "$out" | sed -n '3p')
expected_first="dQw4w9WgXcQ${TAB}Never Gonna Give You Up | Rick Astley | 2:03 | 1.2M | 2009-10-25"
expected_second="aaaaaaaaaaa${TAB}Second Video | Another Channel | 1:00:00 | 999 | 2024-01-02"
expected_third="bbbbbbbbbbb${TAB}Third Video | ? | ? | ? | ?"
assert_eq 'search formats title/channel/duration/views/date' "$expected_first" "$first"
assert_eq 'search formats long durations' "$expected_second" "$second"
assert_eq 'search replaces missing metadata' "$expected_third" "$third"

# 3. URL allowlist.
valid=$(
    unit_env
    for u in \
        'https://youtu.be/abc' \
        'http://youtube.com/watch?v=abc' \
        'https://www.youtube.com/playlist?list=abc' \
        'https://m.youtube.com/watch?v=abc' \
        'https://music.youtube.com/watch?v=abc'; do
        if is_youtube_url "$u"; then printf 'y'; else printf 'n'; fi
    done
)
assert_eq 'accepts only allowlisted YouTube hosts' 'yyyyy' "$valid"

invalid=$(
    unit_env
    for u in \
        'https://example.com/watch?v=abc' \
        'https://youtube.com.evil.example/watch?v=abc' \
        'https://youtube.com@evil.example/watch?v=abc' \
        'https://notyoutube.com/watch?v=abc'; do
        if is_youtube_url "$u"; then printf 'y'; else printf 'n'; fi
    done
)
assert_eq 'rejects lookalike and non-YouTube hosts' 'nnnn' "$invalid"

run_cli 'https://example.com/watch?v=abc' >"$TMP/out" 2>"$TMP/err"
assert_status 'non-YouTube URL exits 1' 1 "$?"
assert_contains 'non-YouTube URL message' 'only YouTube URLs are supported' "$(cat "$TMP/err")"

run_cli 'ftp://example.com/video' >"$TMP/out" 2>"$TMP/err"
assert_status 'non-http URL exits 1' 1 "$?"
assert_contains 'non-http URL message' 'only YouTube URLs are supported' "$(cat "$TMP/err")"

# 4. Quality mapping.
map=$(
    unit_env
    AUDIO=0
    for q in 360 480 720 1080 best worst; do
        # shellcheck disable=SC2030,SC2034
        QUALITY=$q
        printf '%s=%s\n' "$q" "$(yt_format)"
    done
    # shellcheck disable=SC2034
    AUDIO=1
    printf 'audio=%s\n' "$(yt_format)"
)
assert_contains '360 maps to a height filter' 'height<=360' "$map"
assert_contains '480 maps to a height filter' 'height<=480' "$map"
assert_contains '720 maps to a height filter' 'height<=720' "$map"
assert_contains '1080 maps to a height filter' 'height<=1080' "$map"
assert_contains 'best maps to adaptive video+audio' 'best=bv*+ba/b' "$map"
assert_contains 'worst maps to worst' 'worst=worst' "$map"
assert_contains 'audio maps to bestaudio' 'audio=bestaudio/best' "$map"

defaultq=$(
    unit_env
    QUERY=
    parse_args 'cats'
    # shellcheck disable=SC2031
    printf '%s\n' "$QUALITY"
)
assert_eq 'default quality is 720' '720' "$defaultq"

# MSYS/Cygwin: native programs get Windows paths, not "/c/..." paths.
mkdir -p "$TMP/nativebin"
cat >"$TMP/nativebin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' 'MINGW64_NT-10.0'
EOF
cat >"$TMP/nativebin/cygpath" <<'EOF'
#!/bin/sh
case $1 in
    -m) printf '%s\n' 'C:/Tools/yt-dlp.exe' ;;
    *) printf '%s\n' "$2" ;;
esac
EOF
chmod +x "$TMP/nativebin/uname" "$TMP/nativebin/cygpath"
native=$(
    unit_env
    # shellcheck disable=SC2030
    PATH="$TMP/nativebin:$PATH"
    export PATH
    native_path /c/Tools/yt-dlp.exe
)
assert_eq 'MSYS paths convert for native programs' 'C:/Tools/yt-dlp.exe' "$native"
native=$(
    unit_env
    # shellcheck disable=SC2031
    PATH="$TMP/nativebin:$PATH"
    export PATH
    native_path 'C:\Tools\yt-dlp.exe'
)
assert_eq 'Windows paths are left alone' 'C:\Tools\yt-dlp.exe' "$native"
rm -rf "$TMP/nativebin"

parsed=$(
    unit_env
    QUERY=
    parse_args --subs --no-history 'cats'
    printf '%s|%s|%s\n' "$SUBS" "$USE_HISTORY" "$QUERY"
)
assert_eq '--subs does not consume the next option' '1|0|cats' "$parsed"

parsed=$(
    unit_env
    QUERY=
    parse_args --subs fr 'cats'
    printf '%s|%s|%s\n' "$SUBS" "$SUBS_LANG" "$QUERY"
)
assert_eq '--subs accepts a short language tag' '1|fr|cats' "$parsed"

parsed=$(
    unit_env
    QUERY=
    parse_args --subs 'spider-man'
    printf '%s|%s|%s\n' "$SUBS" "$SUBS_LANG" "$QUERY"
)
assert_eq '--subs leaves hyphenated queries alone' '1|en|spider-man' "$parsed"

rm -f "$LOG/mpv.args" "$LOG/yt-dlp.args"
run_cli -q 480 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'quality playback exits 0' 0 "$?"
assert_contains 'yt-dlp resolves the mapped format' \
    '-f bv*[height<=480]+ba/b[height<=480]/b' "$(cat "$LOG/yt-dlp.args")"
assert_contains 'mpv plays the resolved stream' \
    'https://stream.invalid/video' "$(cat "$LOG/mpv.args")"
assert_not_contains 'mpv does not use its ytdl hook' \
    '--ytdl-format' "$(cat "$LOG/mpv.args")"

FAKE_TWO_STREAMS=1
export FAKE_TWO_STREAMS
rm -f "$LOG/mpv.args"
run_cli 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'separate audio playback exits 0' 0 "$?"
assert_contains 'mpv receives the separate audio stream' \
    '--audio-file=https://stream.invalid/audio' "$(cat "$LOG/mpv.args")"
unset FAKE_TWO_STREAMS

rm -f "$LOG/mpv.args"
run_cli -a 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'audio playback exits 0' 0 "$?"
assert_contains 'audio playback disables video' \
    '--no-video' "$(cat "$LOG/mpv.args")"
assert_not_contains 'audio playback opens no video window' \
    '--force-window' "$(cat "$LOG/mpv.args")"

FAKE_RESOLVE_RC=1
export FAKE_RESOLVE_RC
run_cli 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'stream resolution failure exits 3' 3 "$?"
assert_contains 'stream resolution failure message' \
    'could not resolve a stream' "$(cat "$TMP/err")"
unset FAKE_RESOLVE_RC

fzfargs=$(cat "$LOG/fzf.args")
assert_contains 'fzf hides the id column' '--with-nth=2..' "$fzfargs"
assert_contains 'fzf searches only the display column' '--nth=2..' "$fzfargs"

FAKE_MPV_RC=1
export FAKE_MPV_RC
run_cli 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'playback failure exits 3' 3 "$?"
assert_contains 'playback failure message' 'playback failed' "$(cat "$TMP/err")"
unset FAKE_MPV_RC

rm -f "$LOG/yt-dlp.args"
run_cli -n 7 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'numbered search exits 0' 0 "$?"
assert_contains 'search honors the result count' 'ytsearch7:cats' "$(cat "$LOG/yt-dlp.args")"

rm -f "$LOG/yt-dlp.args"
run_cli --sort date -n 7 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'date-sorted search exits 0' 0 "$?"
assert_contains 'date sort uses ytsearchdate' 'ytsearchdate7:cats' "$(cat "$LOG/yt-dlp.args")"

# 5. History cap, newest first.
histout=$(
    unit_env
    HIST_DIR="$TMP/state/histcap"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    mkdir -p "$HIST_DIR"
    awk 'BEGIN {
        for (i = 500; i >= 1; i--)
            printf "2024-01-01T00:00:00\tyoutube\thttps://www.youtube.com/watch?v=old%d\ttitle %d\n", i, i
    }' >"$HISTFILE"
    i=501
    while [ "$i" -le 505 ]; do
        hist_add youtube "https://www.youtube.com/watch?v=vid$i" "title $i"
        i=$((i + 1))
    done
    printf '%s\n' "$(wc -l <"$HISTFILE" | tr -d ' ')"
    head -n 1 "$HISTFILE" | cut -f4
    tail -n 1 "$HISTFILE" | cut -f4
)
count=$(printf '%s\n' "$histout" | sed -n '1p')
newest=$(printf '%s\n' "$histout" | sed -n '2p')
oldest=$(printf '%s\n' "$histout" | sed -n '3p')
assert_eq 'history caps at 500 lines' '500' "$count"
assert_eq 'history is newest first' 'title 505' "$newest"
assert_eq 'history drops old entries' 'title 6' "$oldest"

# 6. AniList parsing from the saved fixture.
anime=$(
    unit_env
    CACHE_DIR="$TMP/cache/anime-parse"
    anilist_search 'Cowboy Bebop'
)
arc=$?
assert_status 'AniList search exits 0' 0 "$arc"
anime_first=$(printf '%s\n' "$anime" | sed -n '1p')
anime_second=$(printf '%s\n' "$anime" | sed -n '2p')
assert_eq 'AniList search parses fixture fields' \
    "1${TAB}Cowboy Bebop | TV | 26 | 1998 | 86" "$anime_first"
assert_eq 'AniList search shows romaji and English titles' \
    "2${TAB}Shingeki no Kyojin (Attack on Titan) | TV | 25 | 2013 | 84" "$anime_second"

# 6b. The AniList cache avoids a second request inside the TTL.
rm -f "$LOG/curl.args"
cached=$(
    unit_env
    CACHE_DIR="$TMP/cache/anime-cache"
    anilist_search 'cache test' >/dev/null
    anilist_search 'cache test' >/dev/null
    printf 'ok\n'
)
rc=$?
assert_status 'AniList cache calls succeed' 0 "$rc"
assert_eq 'AniList cache reuses the response' 'ok' "$cached"
curl_calls=$(wc -l <"$LOG/curl.args" | tr -d ' ')
assert_eq 'AniList cache makes one request' '1' "$curl_calls"

# 7. AniList 429 retry (Retry-After: 0), no hammering.
rm -f "$FAKE/curl.count" "$LOG/curl.args"
anime429=$(
    unit_env
    CACHE_DIR="$TMP/cache/anime-429"
    FAKE_CURL_MODE=429once
    export FAKE_CURL_MODE
    anilist_search 'rate limit test'
)
rc=$?
assert_status 'AniList 429 retry exits 0' 0 "$rc"
assert_contains 'AniList 429 retry returns data' 'Cowboy Bebop' "$anime429"
curl_calls=$(wc -l <"$LOG/curl.args" | tr -d ' ')
assert_eq 'AniList retries exactly once' '2' "$curl_calls"

# 7b. A long Retry-After is reported without a second request.
rm -f "$FAKE/curl.count" "$LOG/curl.args"
anime429long=$(
    unit_env
    CACHE_DIR="$TMP/cache/anime-429long"
    FAKE_CURL_MODE=429long
    export FAKE_CURL_MODE
    anilist_search 'long rate limit' 2>&1
)
rc=$?
assert_status 'AniList long 429 exits 3' 3 "$rc"
assert_contains 'AniList long 429 message' 'try again in 120 seconds' "$anime429long"
curl_calls=$(wc -l <"$LOG/curl.args" | tr -d ' ')
assert_eq 'AniList long 429 is not retried' '1' "$curl_calls"

# 8. Zero search results.
FAKE_SEARCH_FILE="$FAKE/empty.tsv"
export FAKE_SEARCH_FILE
run_cli 'nothing here' >"$TMP/out" 2>"$TMP/err"
assert_status 'zero results exits 4' 4 "$?"
assert_contains 'zero results message' 'No videos found' "$(cat "$TMP/err")"

FAKE_SEARCH_FILE="$FAKE/empty.tsv"
FAKE_SEARCH_RC=1
export FAKE_SEARCH_FILE FAKE_SEARCH_RC
run_cli 'network failure' >"$TMP/out" 2>"$TMP/err"
assert_status 'search network failure exits 3' 3 "$?"
assert_contains 'search network failure message' 'YouTube request failed' "$(cat "$TMP/err")"
unset FAKE_SEARCH_FILE FAKE_SEARCH_RC

# 9. fzf cancellation.
FAKE_FZF_MODE=cancel
export FAKE_FZF_MODE
run_cli 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'fzf cancel exits cleanly' 0 "$?"
assert_eq 'fzf cancel is quiet' '' "$(cat "$TMP/err")"
FAKE_FZF_MODE=first
export FAKE_FZF_MODE

# 9b. Anime information screen: fields, synopsis, next airing and history.
rm -f "$LOG/mpv.args" "$FAKE/fzf.count" "$FAKE/fzf.last"
menuout=$(
    unit_env
    CACHE_DIR="$TMP/cache/anime-menu"
    TMP_WORK="$TMP/work/anime-menu"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/anime-menu"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=last
    export FAKE_FZF_MODE
    anime_menu 1
)
rc=$?
assert_status 'anime menu exits 0' 0 "$rc"
assert_contains 'anime menu shows next airing' 'Next airing: episode 27' "$menuout"
assert_contains 'anime menu shows synopsis' 'ragtag crew' "$menuout"
assert_eq 'anime menu strips HTML from synopsis' '0' \
    "$(printf '%s\n' "$menuout" | grep -c '<i>')"
assert_eq 'anime menu records an anime history entry' \
    "anime${TAB}anime:1${TAB}Cowboy Bebop" \
    "$(sed -n '1p' "$TMP/state/anime-menu/histfile" | cut -f2-4)"
assert_contains 'anime menu offers official episodes' \
    'Browse official episodes (3)' "$(cat "$FAKE/fzf.last")"
assert_eq 'anime menu puts official episodes first' 'episodes' \
    "$(sed -n '1p' "$FAKE/fzf.last" | cut -f1)"

# 9c. Anime trailer action uses the AniList YouTube id.
rm -f "$LOG/mpv.args" "$LOG/yt-dlp.args" "$FAKE/fzf.count"
trailerout=$(
    unit_env
    CACHE_DIR="$TMP/cache/anime-trailer"
    TMP_WORK="$TMP/work/anime-trailer"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/anime-trailer"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=trailerquit
    export FAKE_FZF_MODE
    anime_menu 1
) 2>"$TMP/trailer.err"
rc=$?
assert_status 'anime trailer exits 0' 0 "$rc"
assert_contains 'anime trailer resolves the YouTube id' 'qig4KOK2R2g' "$(cat "$LOG/yt-dlp.args")"
assert_contains 'anime trailer keeps metadata output' 'Cowboy Bebop' "$trailerout"

# 9d. Official streaming links: only STREAMING entries, opened via xdg-open.
rm -f "$LOG/xdg-open.args" "$FAKE/fzf.count"
linksout=$(
    unit_env
    # shellcheck disable=SC2034
    CACHE_DIR="$TMP/cache/anime-links"
    TMP_WORK="$TMP/work/anime-links"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/anime-links"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=linksquit
    export FAKE_FZF_MODE
    anime_menu 1
) 2>"$TMP/links.err"
rc=$?
assert_status 'anime links exit 0' 0 "$rc"
assert_contains 'anime links list official services' 'Official streaming links' "$linksout"
assert_contains 'anime links include Crunchyroll' 'Crunchyroll' "$linksout"
assert_not_contains 'anime links skip INFO entries' 'Wikipedia' "$linksout"
assert_contains 'anime links open the selected URL' 'crunchyroll.com' "$(cat "$LOG/xdg-open.args")"
assert_not_contains 'anime links open only the selected URL' 'netflix' "$(cat "$LOG/xdg-open.args")"

# 9e. Official episode browser: opens a licensed-service episode.
rm -f "$LOG/xdg-open.args" "$FAKE/fzf.count" "$FAKE/fzf.last"
episodesout=$(
    unit_env
    # shellcheck disable=SC2034
    CACHE_DIR="$TMP/cache/anime-episodes-open"
    TMP_WORK="$TMP/work/anime-episodes-open"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/anime-episodes-open"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=episodesopen
    export FAKE_FZF_MODE
    anime_menu 1
) 2>"$TMP/episodes-open.err"
rc=$?
assert_status 'anime episodes exit 0' 0 "$rc"
assert_contains 'anime episodes list the official count' \
    'Official episodes (from AniList): 3' "$episodesout"
assert_contains 'anime episodes open the selected link' \
    'crunchyroll.com/watch/G7PU4VJEJ' "$(cat "$LOG/xdg-open.args")"
assert_not_contains 'anime episodes open only the selected link' \
    'stray-dog-strut' "$(cat "$LOG/xdg-open.args")"

# 9f. A YouTube episode entry is resolved and played like any video.
rm -f "$LOG/mpv.args" "$LOG/yt-dlp.args" "$LOG/xdg-open.args" "$FAKE/fzf.count"
episodesplay=$(
    unit_env
    # shellcheck disable=SC2034
    CACHE_DIR="$TMP/cache/anime-episodes-play"
    TMP_WORK="$TMP/work/anime-episodes-play"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/anime-episodes-play"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=episodesplay
    export FAKE_FZF_MODE
    anime_menu 1
) 2>"$TMP/episodes-play.err"
rc=$?
assert_status 'anime episode playback exits 0' 0 "$rc"
assert_contains 'anime episode resolves the YouTube id' \
    'youtube.com/watch?v=episode1234' "$(cat "$LOG/yt-dlp.args")"
assert_contains 'anime episode plays in mpv' \
    'https://stream.invalid/video' "$(cat "$LOG/mpv.args")"
assert_contains 'anime episode keeps metadata output' \
    'Cowboy Bebop' "$episodesplay"
assert_not_contains 'anime episode does not open a browser' \
    'youtube.com' "$(cat "$LOG/xdg-open.args" 2>/dev/null || true)"

# 9g. Titles without per-episode links get a clear fallback.
noep=$(
    unit_env
    TMP_WORK="$TMP/work/anime-noep"
    mkdir -p "$TMP_WORK"
    printf '%s\n' '{"data":{"Media":{"streamingEpisodes":[]}}}' \
        >"$TMP_WORK/empty.json"
    anime_episodes "$TMP_WORK/empty.json" 2>&1
)
rc=$?
assert_status 'anime episodes without links exit 4' 4 "$rc"
assert_contains 'anime episodes without links explains why' \
    'no official per-episode links' "$noep"

# 9h. Only the per-title query asks for the (larger) episode payload.
mediaq=$(
    unit_env
    printf '%s\n' "$ANILIST_MEDIA_QUERY"
)
searchq=$(
    unit_env
    printf '%s\n' "$ANILIST_SEARCH_QUERY"
)
assert_contains 'media query requests streaming episodes' \
    'streamingEpisodes' "$mediaq"
assert_not_contains 'search query stays lightweight' \
    'streamingEpisodes' "$searchq"

# 9i. Startup page: banner, free-text prompt and the three actions.
rm -f "$LOG/fzf.ask"
askout=$(
    unit_env
    FAKE_FZF_QUERY='startup query'
    export FAKE_FZF_QUERY
    ask 'Search YouTube'
)
rc=$?
assert_status 'startup ask exits 0' 0 "$rc"
assert_eq 'startup ask returns the typed query' 'startup query' "$askout"
assert_contains 'startup ask uses fzf print-query' \
    '--print-query' "$(cat "$LOG/fzf.ask")"

rm -f "$FAKE/fzf.count" "$FAKE/fzf.last"
homepage=$(
    unit_env
    TMP_WORK="$TMP/work/home"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/home"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=homequit
    export FAKE_FZF_MODE
    home_menu
)
rc=$?
assert_status 'startup page quit exits 0' 0 "$rc"
assert_contains 'startup page shows the banner' 'vid-cli' "$homepage"
assert_contains 'startup page shows the quality' 'Quality: 720' "$homepage"
assert_contains 'startup page offers YouTube' \
    '1. Search YouTube' "$(cat "$FAKE/fzf.last")"
assert_contains 'startup page offers anime' \
    '2. Search anime (AniList)' "$(cat "$FAKE/fzf.last")"
assert_contains 'startup page offers history' \
    '3. Continue from history' "$(cat "$FAKE/fzf.last")"

rm -f "$LOG/yt-dlp.args" "$LOG/mpv.args" "$LOG/fzf.ask" "$FAKE/fzf.count"
# shellcheck disable=SC2034
homeyt=$(
    unit_env
    TMP_WORK="$TMP/work/home-youtube"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/home-youtube"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=homeyoutube
    FAKE_FZF_QUERY='startup cats'
    export FAKE_FZF_MODE FAKE_FZF_QUERY
    home_menu
) 2>"$TMP/home-youtube.err"
rc=$?
assert_status 'startup YouTube flow exits 0' 0 "$rc"
assert_contains 'startup YouTube flow asks for a query' \
    '--print-query' "$(cat "$LOG/fzf.ask")"
assert_contains 'startup YouTube flow searches the prompt' \
    'ytsearch15:startup cats' "$(cat "$LOG/yt-dlp.args")"
assert_contains 'startup YouTube flow plays the result' \
    'https://stream.invalid/video' "$(cat "$LOG/mpv.args")"

rm -f "$FAKE/fzf.count" "$FAKE/fzf.last"
homeanime=$(
    unit_env
    # shellcheck disable=SC2034
    CACHE_DIR="$TMP/cache/home-anime"
    TMP_WORK="$TMP/work/home-anime"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/home-anime"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=homeanime
    FAKE_FZF_QUERY='Cowboy Bebop'
    export FAKE_FZF_MODE FAKE_FZF_QUERY
    home_menu
) 2>"$TMP/home-anime.err"
rc=$?
assert_status 'startup anime flow exits 0' 0 "$rc"
assert_contains 'startup anime flow searches AniList' 'Cowboy Bebop' "$homeanime"
assert_contains 'startup anime flow records history' \
    'anime:1' "$(cat "$TMP/state/home-anime/histfile")"

rm -f "$LOG/yt-dlp.args" "$LOG/mpv.args" "$FAKE/fzf.count"
mkdir -p "$TMP/state/home-history"
printf '%s\t%s\t%s\t%s\n' '1700000000' 'youtube' \
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ' 'Startup Video' \
    >"$TMP/state/home-history/histfile"
# shellcheck disable=SC2034
homehist=$(
    unit_env
    TMP_WORK="$TMP/work/home-history"
    mkdir -p "$TMP_WORK"
    HIST_DIR="$TMP/state/home-history"
    HISTFILE="$HIST_DIR/histfile"
    USE_HISTORY=1
    FAKE_FZF_MODE=homehistory
    export FAKE_FZF_MODE
    home_menu
) 2>"$TMP/home-history.err"
rc=$?
assert_status 'startup history flow exits 0' 0 "$rc"
assert_contains 'startup history flow resolves the entry' \
    'dQw4w9WgXcQ' "$(cat "$LOG/yt-dlp.args")"
assert_contains 'startup history flow plays the entry' \
    'https://stream.invalid/video' "$(cat "$LOG/mpv.args")"

# 9j. Without a terminal the startup page cannot run, so usage is shown.
run_cli >"$TMP/out" 2>"$TMP/err" </dev/null
assert_status 'no-query non-terminal exits 1' 1 "$?"
assert_contains 'no-query non-terminal prints usage' 'Usage:' "$(cat "$TMP/err")"

run_cli --anime >"$TMP/out" 2>"$TMP/err" </dev/null
assert_status 'anime without a title exits 1 without a terminal' 1 "$?"
assert_contains 'anime without a title prints usage' 'Usage:' "$(cat "$TMP/err")"

rm -f "$FAKE/fzf.count"
FAKE_FZF_MODE=firstlast
export FAKE_FZF_MODE
run_cli --anime 'Cowboy Bebop' >"$TMP/out" 2>"$TMP/err" </dev/null
rc=$?
assert_status '--anime with a title exits 0' 0 "$rc"
assert_contains '--anime with a title shows the info screen' \
    'Cowboy Bebop' "$(cat "$TMP/out")"

# 10. Download path and format args.
rm -f "$LOG/yt-dlp.args"
run_cli -d -q 720 'cats' >"$TMP/out" 2>"$TMP/err"
assert_status 'download exits 0' 0 "$?"
ytlog=$(cat "$LOG/yt-dlp.args")
assert_contains 'download disables playlists' '--no-playlist' "$ytlog"
assert_contains 'download uses mapped quality' 'height<=720' "$ytlog"
assert_contains 'download writes to VID_CLI_DL_DIR' '/dl/%(title)s' "$ytlog"

# 11. Playlist expansion and multi-select.
rm -f "$LOG/mpv.args" "$LOG/yt-dlp.args" "$FAKE/fzf.count"
FAKE_FZF_MODE=allfirst
export FAKE_FZF_MODE
run_cli 'https://www.youtube.com/playlist?list=abc' >"$TMP/out" 2>"$TMP/err"
assert_status 'playlist playback exits 0' 0 "$?"
assert_contains 'playlist resolves first selection' 'aaaaaaaaaaa' "$(cat "$LOG/yt-dlp.args")"
assert_contains 'playlist resolves second selection' 'bbbbbbbbbbb' "$(cat "$LOG/yt-dlp.args")"
assert_contains 'playlist expansion is capped at 100' '--playlist-end 100' "$(cat "$LOG/yt-dlp.args")"
mpv_calls=$(wc -l <"$LOG/mpv.args" | tr -d ' ')
assert_eq 'playlist queues both videos' '2' "$mpv_calls"
FAKE_FZF_MODE=first
export FAKE_FZF_MODE

# 12. Help documents every flag and environment variable.
help=$(
    run_cli -h
)
assert_contains 'help has --quality' '--quality' "$help"
assert_contains 'help has --audio' '--audio' "$help"
assert_contains 'help has --download' '--download' "$help"
assert_contains 'help has --number' '--number' "$help"
assert_contains 'help has --continue' '--continue' "$help"
assert_contains 'help has --subs' '--subs' "$help"
assert_contains 'help has --sort' '--sort' "$help"
assert_contains 'help has --no-history' '--no-history' "$help"
assert_contains 'help has --vlc' '--vlc' "$help"
assert_contains 'help has --anime' '--anime' "$help"
assert_contains 'help has --' 'end option parsing' "$help"
assert_contains 'help has VID_CLI_PLAYER' 'VID_CLI_PLAYER' "$help"
assert_contains 'help has VID_CLI_DL_DIR' 'VID_CLI_DL_DIR' "$help"
assert_contains 'help has VID_CLI_HIST_DIR' 'VID_CLI_HIST_DIR' "$help"
assert_contains 'help has VID_CLI_RESULTS' 'VID_CLI_RESULTS' "$help"
assert_contains 'help has VID_CLI_EXTERNAL_MENU' 'VID_CLI_EXTERNAL_MENU' "$help"
assert_contains 'help has VID_CLI_YTDLP_ARGS' 'VID_CLI_YTDLP_ARGS' "$help"

# 13. Missing dependencies produce status 2 and names.
missing=$(
    # shellcheck disable=SC2123
    PATH="$TMP/nowhere"
    export PATH
    VID_CLI_SOURCE_ONLY=1
    export VID_CLI_SOURCE_ONLY
    # shellcheck source=/dev/null
    . "$ROOT/vid-cli"
    check_deps 2>&1
)
rc=$?
assert_status 'missing dependencies exit 2' 2 "$rc"
assert_contains 'missing dependencies are named' 'missing dependencies' "$missing"
assert_contains 'missing dependencies include install hints' 'Termux: pkg install' "$missing"

# Summary.
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
