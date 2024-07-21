#!/bin/sh

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>" >&2
    exit 1
fi

file="./secrets/servers.key"

if ! [ -d "$file" ]; then
    echo "could not find file $file" >&2
    exit 1
fi

git add -f "$file"

set +e
"$@"
set -e

git restore --staged "$file"
