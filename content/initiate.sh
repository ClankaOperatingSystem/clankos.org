#!/bin/sh
# initiate.sh: make the Git repository in the working directory a ClankOS
# garden.
#
#   sh initiate.sh [VERSION] [OPTION ...]
#
# VERSION is the ClankOS image the garden's commands run in: latest, which
# follows each new version, or a version to pin, such as v0.0.2. At a
# terminal the script asks for it when it is not given; otherwise it is
# latest. The options are those of the image's initiate command, which
# does the work and asks the rest: see
# https://github.com/ClankaOperatingSystem/clankos/blob/master/docs/initiate.txt
#
# It needs docker and bash, and the network to pull the image. It pulls
# the image, takes from it the script that starts its commands, and runs
# initiate with that. It writes only in the repository, writes over
# nothing that is there, and commits nothing.
#
# CLANKOS_IMAGE names an image to use as it is, and none is pulled.
# Exit: initiate's own; 2 not a Git repository; 127 docker or bash not found.

set -eu

main() {
    registry=ghcr.io/clankaoperatingsystem/clankos

    for tool in docker bash; do
        command -v "$tool" >/dev/null || {
            echo "initiate.sh: $tool not found" >&2
            exit 127
        }
    done
    [ -e .git ] || {
        echo "initiate.sh: not the root of a Git repository: $PWD" >&2
        exit 2
    }

    version=
    case ${1:-} in
        ''|-*) ;;
        *) version=$1; shift ;;
    esac
    if [ -z "$version" ] && [ -z "${CLANKOS_IMAGE:-}" ] && [ -t 0 ]; then
        printf 'The image: latest, which follows new versions, or a version to pin, such as v0.0.2 [latest]: ' >&2
        read -r version || version=
    fi
    version=${version:-latest}
    case $version in
        *[!A-Za-z0-9._-]*)
            echo "initiate.sh: not a version: $version" >&2
            exit 2 ;;
    esac

    if [ -n "${CLANKOS_IMAGE:-}" ]; then
        image=$CLANKOS_IMAGE
    else
        image=$registry:$version
        docker pull "$image" >&2
    fi

    run=$(mktemp)
    trap 'rm -f "$run"' EXIT
    docker run --rm "$image" cat /usr/local/share/clankos/bin/clankos-run > "$run"
    CLANKOS_IMAGE=$image CLANKOS_WORKSPACE=$PWD bash "$run" initiate --image "$version" "$@"
}

# Read whole before any of it runs, so that piping this file to sh works;
# and when it is piped, the questions are asked at the terminal if there
# is one.
if [ -t 0 ] || ! ( : < /dev/tty ) 2>/dev/null; then
    main "$@"
else
    main "$@" < /dev/tty
fi
