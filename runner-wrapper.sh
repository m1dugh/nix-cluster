#!/bin/sh

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>" >&2
    exit 1
fi

find ./generated-certs -type f -name "*-key.pem" -exec git add -f '{}' \;
git add -f "./secrets/servers.key"

set +e
"$@"
set -e

find ./generated-certs -type f -name "*-key.pem" -exec git restore --staged '{}' \;
git restore --staged "./secrets/servers.key"
