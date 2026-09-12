#!/usr/bin/env bash
# Runs every test in this directory and reports what failed.
#
#   ./tests/run.sh
#
# Needs lua5.4 for the Lua tests and node for the JavaScript ones. They read the
# shipped files out of M5_RankedPvP/ and run the real functions against stubs,
# so they check what actually ships rather than a copy of it.
set -u
cd "$(dirname "$0")/.."

fails=0
echo "--- syntax ---"
for f in M5_RankedPvP/Files/*.lua M5_RankedPvP/الاعدادات/*.lua M5_RankedPvP/fxmanifest.lua; do
  luac5.4 -p "$f" || { echo "SYNTAX FAIL $f"; fails=$((fails+1)); }
done
node --check M5_RankedPvP/Files/ui/app.js || { echo "SYNTAX FAIL app.js"; fails=$((fails+1)); }
echo "ok"

echo
echo "--- tests ---"
for f in tests/*.lua; do
  out=$(lua5.4 "$f" 2>&1)
  last=$(echo "$out" | tail -1)
  printf '%-28s %s\n' "$(basename "$f")" "$last"
  case "$last" in
    *"ALL PASS"*) ;;
    *) fails=$((fails+1)); echo "$out" | grep '^FAIL' ;;
  esac
done

echo
if [ "$fails" -eq 0 ]; then echo "everything passed"; else echo "$fails failed"; fi
exit "$fails"
