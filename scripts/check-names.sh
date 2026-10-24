#!/usr/bin/env bash
# Fails if a retired product name shows up outside the migration allowlist.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail=0
report() {
  printf 'check-names: %s\n' "$1" >&2
  fail=1
}

while IFS= read -r -d '' path; do
  rel="${path#./}"
  case "$rel" in
    scripts/check-names.sh|docs/architecture.md) continue ;;
  esac

  for needle in "PCPCore" "PCP.xcodeproj" "Personal Copy Paste"; do
    if [[ "$rel" == *"$needle"* ]]; then
      report "path contains ${needle}: ${rel}"
    fi
  done

  if [[ -f "$path" ]]; then
    for needle in "PCPCore" "PCP.xcodeproj" "Personal Copy Paste" "PRODUCT_NAME: PCP" "PRODUCT_NAME = PCP"; do
      if grep -I -q -F -- "$needle" "$path"; then
        report "${rel} contains ${needle}"
      fi
    done
  fi
done < <(find . \
  \( \
    -path ./.git -o \
    -path ./build -o \
    -path ./Core/.build -o \
    -path ./Core/.swiftpm -o \
    -path ./DerivedData -o \
    -path ./output -o \
    -name xcuserdata \
  \) -prune -o -print0)

exit "$fail"
