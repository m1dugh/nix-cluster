#!/bin/sh

add_files() {
    for file in "$@"; do
        if ! [ -e "$file" ]; then
            echo "could not find file $file" >&2
            exit 1
        fi
        git add -f "$file"
    done
}

remove_files() {
    for file in "$@"; do
        git restore --staged "$file"
    done
}

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>" >&2
    exit 1
fi

files="./generated-certs ./secrets/servers.key"

add_files $files

set +e
"$@"
set -e

remove_files $files
