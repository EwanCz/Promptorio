#!/usr/bin/env bash
# Inspect an exported artifact (binary with embedded .pck, or a standalone .pck)
# for a leaked dev secret and for dev-only files that shouldn't ship.
#
# Usage: tests/check_export.sh <path-to-exported-binary-or-pck>
#
# Checks:
# 1. Key-shaped strings for the providers this project talks to (Anthropic
#    `sk-ant-...`, OpenAI `sk-...`/`sk-proj-...`) and the literal content of
#    a local .env, if one exists at the project root.
# 2. Whether dev-only directories (tests/, saves/) were swept into the
#    artifact by Godot's default "all_resources" export filter. They hold no
#    secret, but they bloat the build and ship test fixtures; exclude them
#    with export_filter's exclude_filter ("tests/*,saves/*") in the preset
#    you export with (export_presets.cfg is gitignored, so that setting
#    lives only in each exporter's local file, not in git).
#
# Exit 1 if a key-shaped string is found. Exit 0 (with a warning) if only
# dev-file bloat is found. Exit 0 clean otherwise.
set -u

ARTIFACT="${1:-}"
if [ -z "$ARTIFACT" ] || [ ! -f "$ARTIFACT" ]; then
	echo "usage: tests/check_export.sh <path-to-exported-binary-or-pck>" >&2
	exit 2
fi
ARTIFACT="$(cd "$(dirname "$ARTIFACT")" && pwd)/$(basename "$ARTIFACT")"
cd "$(dirname "$0")/.."

STATUS=0

echo "== key-shaped strings =="
# Long enough to avoid matching the "sk-ant-api03-AAAA..." style placeholder
# used in tests/test_llm_http.gd on purpose (that test asserts redaction, and
# this check is a separate net for a *real* key accidentally landing in an
# export, not a reason to special-case that file).
if grep -a -o -E "sk-ant-api[0-9]{2}-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}" "$ARTIFACT" | grep -v -x -q "sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAA"; then
	echo "FOUND a key-shaped string in $ARTIFACT (not reproduced here; inspect locally with the grep above)" >&2
	STATUS=1
else
	echo "  none found"
fi

if strings "$ARTIFACT" | grep -q -x 'res://.env'; then
	echo "FOUND a res://.env reference in $ARTIFACT; inspect the export for an included .env" >&2
	STATUS=1
fi

if [ -f .env ]; then
	echo "== local .env leakage =="
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line#"${line%%[![:space:]]*}"}"
		case "$line" in ''|'#'*) continue ;; esac
		line="${line#export }"
		case "$line" in *=*) ;; *) continue ;; esac
		value="${line#*=}"
		value="${value#"${value%%[![:space:]]*}"}"
		value="${value%"${value##*[![:space:]]}"}"
		if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
			value="${value:1:${#value}-2}"
		fi
		[ "${#value}" -lt 8 ] && continue
		if grep -a -q -F -- "$value" "$ARTIFACT"; then
			echo "FOUND the value of a local .env entry inside $ARTIFACT" >&2
			STATUS=1
		fi
	done < .env
	echo "  checked $(grep -c -v -E '^\s*(#|$)' .env) entries from .env"
else
	echo "== local .env leakage == (skipped: no .env at project root)"
fi

echo "== dev-only files swept into the artifact =="
for dir in tests saves; do
	count=$(strings "$ARTIFACT" | grep -c "^res://$dir/" || true)
	if [ "$count" -gt 0 ]; then
		echo "WARNING: $count res://$dir/* entries found — exclude \"$dir/*\" in the preset's exclude_filter" >&2
	else
		echo "  res://$dir/ : clean"
	fi
done

exit "$STATUS"
