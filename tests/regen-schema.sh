#!/usr/bin/env bash
# Regenerate the schema snapshot from the recorded fixture.
# Run this after an *intentional* schema change.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
jq -r '
  . as $root
  | [paths(type != "object" and type != "array")]
  | map(. as $p | ($p | map(tostring) | join(".")) + ": " + ($root | getpath($p) | type))
  | sort
  | unique[]
' "$DIR/fixtures/real-opus.json" > "$DIR/fixtures/real-opus.schema"
echo "wrote $DIR/fixtures/real-opus.schema"
