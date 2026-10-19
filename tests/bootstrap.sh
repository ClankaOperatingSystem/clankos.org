#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$repo/.cache"
work=$(mktemp -d "$repo/.cache/bootstrap.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/mock-bin" "$work/bundle/scripts" "$work/garden" "$work/tmp"
export TMPDIR="$work/tmp" CALLS="$work/calls" BUNDLE="$work/bundle" RESULT="$work/result"
cat > "$BUNDLE/scripts/bootstrap" <<'BOOTSTRAP'
#!/usr/bin/env bash
[ -f "$(dirname -- "$0")/clankos-pair" ] || exit 99
printf '%s\n' "$PWD" "$@" > "$RESULT"
cat >> "$RESULT"
exit "${BOOTSTRAP_STATUS:-0}"
BOOTSTRAP
touch "$BUNDLE/scripts/clankos-pair"
cat > "$work/mock-bin/docker" <<'DOCKER'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case $1 in
    pull) exit "${PULL_STATUS:-0}" ;;
    run)
        [ "${EXTRACT_STATUS:-0}" = 0 ] || exit "$EXTRACT_STATUS"
        tar -C "$BUNDLE" -cf - . ;;
esac
DOCKER
chmod +x "$work/mock-bin/docker"
export PATH="$work/mock-bin:$PATH"
cd "$work/garden"
git init -q
printf 'answers\n' | sh "$repo/content/initiate.sh" v1.2.3 --keeper 'https://example.test/a b'
printf '%s\n' "$PWD" --image v1.2.3 --keeper 'https://example.test/a b' answers > "$work/expected"
cmp "$RESULT" "$work/expected"
grep -qx 'pull ghcr.io/clankaoperatingsystem/clankos:v1.2.3' "$CALLS"
[ -z "$(ls -A "$TMPDIR")" ]
for version in '' latest v1 'v1.2.3;bad'; do
    if sh "$repo/content/initiate.sh" "$version" >/dev/null 2>&1; then exit 1; else [ "$?" = 2 ]; fi
done
rm "$RESULT"
if EXTRACT_STATUS=37 sh "$repo/content/initiate.sh" v1.2.3 >/dev/null 2>&1; then exit 1; else [ "$?" = 37 ]; fi
[ ! -e "$RESULT" ]
if PULL_STATUS=38 sh "$repo/content/initiate.sh" v1.2.3 >/dev/null 2>&1; then exit 1; else [ "$?" = 38 ]; fi
[ ! -e "$RESULT" ]
if BOOTSTRAP_STATUS=39 sh "$repo/content/initiate.sh" v1.2.3 </dev/null; then exit 1; else [ "$?" = 39 ]; fi
[ -z "$(ls -A "$TMPDIR")" ]
echo 'Bootstrap bundle extraction, arguments, input, failures and cleanup pass.'
