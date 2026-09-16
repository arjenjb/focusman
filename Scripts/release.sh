#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?Usage: release.sh VERSION IS_SNAPSHOT}
snapshot=${2:?Usage: release.sh VERSION IS_SNAPSHOT}
case "$snapshot" in true|false) ;; *) echo "IS_SNAPSHOT must be true or false." >&2; exit 1 ;; esac

notarize=true
if [[ "$snapshot" == true && "${NOTARIZE_SNAPSHOT:-0}" != 1 ]]; then
    notarize=false
fi
if [[ "$notarize" == true ]]; then
    export SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: CosmoCows B.V. (68RP9D4Z9J)}"
    [[ "$SIGN_IDENTITY" != - ]] || { echo "Notarized releases require a Developer ID signing identity." >&2; exit 1; }
    bash Scripts/notarize.sh --check-credentials
fi

make bundle VERSION="$version" SWIFT_BUILD_FLAGS="--arch arm64 --arch x86_64"
codesign --verify --strict build/Focusman.app
if [[ "$notarize" == true ]]; then
    bash Scripts/notarize.sh build/Focusman.app
else
    echo "Snapshot: skipping notarization (set NOTARIZE_SNAPSHOT=1 to test it)."
fi
