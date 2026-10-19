#!/bin/sh
# Download the standalone bootstrap bundle from a fixed ClankOS release.
# Usage: sh initiate.sh vX.Y.Z [BOOTSTRAP OPTION ...]
# CLANKOS_IMAGE may select a local test image; it must provide the same protocol.
set -eu
main() {
    version=${1:-}
    if ! printf '%s\n' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo 'Usage: initiate.sh vX.Y.Z [BOOTSTRAP OPTION ...]' >&2
        echo 'Select a published fixed release; latest is not a bootstrap target.' >&2
        exit 2
    fi
    shift
    for tool in git docker bash tar; do
        command -v "$tool" >/dev/null || {
            echo "initiate.sh: $tool not found" >&2
            exit 127
        }
    done
    root=$(git rev-parse --show-toplevel) || exit 2
    [ "$root" -ef . ] || {
        echo 'initiate.sh: run at the Git repository root' >&2
        exit 2
    }
    image=${CLANKOS_IMAGE:-ghcr.io/clankaoperatingsystem/clankos:$version}
    [ -n "${CLANKOS_IMAGE:-}" ] || docker pull "$image" >&2
    bundle=$(mktemp -d)
    trap 'rm -rf "$bundle"' EXIT
    docker run --rm "$image" tar -C /usr/local/share/clankos/source/skills/clankos-bootstrap -cf - . > "$bundle/bundle.tar"
    tar -xf "$bundle/bundle.tar" -C "$bundle"
    CLANKOS_IMAGE=$image bash "$bundle/scripts/bootstrap" --image "$version" "$@"
}
# Read the whole script before consuming answers, including when piped to sh.
if [ -t 0 ] || ! ( : < /dev/tty ) 2>/dev/null; then
    main "$@"
else
    main "$@" < /dev/tty
fi
