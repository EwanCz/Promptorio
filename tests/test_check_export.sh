#!/usr/bin/env bash
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/tests"
cp "$root/tests/check_export.sh" "$tmp/tests/"
printf '%s\n' 'export OPENAI_API_KEY = "quoted-secret-value"' > "$tmp/.env"
printf '%s\n' 'quoted-secret-value' > "$tmp/artifact"
if "$tmp/tests/check_export.sh" "$tmp/artifact" >/dev/null 2>&1; then
	echo 'quoted .env value was missed' >&2; exit 1
fi
printf '%s\n' 'sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAABBBBB' > "$tmp/artifact"
if "$tmp/tests/check_export.sh" "$tmp/artifact" >/dev/null 2>&1; then
	echo 'key containing placeholder was missed' >&2; exit 1
fi
printf '%s\n' 'res://.env' > "$tmp/artifact"
if "$tmp/tests/check_export.sh" "$tmp/artifact" >/dev/null 2>&1; then
	echo 'embedded .env path was missed' >&2; exit 1
fi
printf '%s\n' 'sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAA' > "$tmp/artifact"
"$tmp/tests/check_export.sh" "$tmp/artifact" >/dev/null
echo 'export checker regression checks passed'
