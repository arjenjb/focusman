#!/bin/bash
set -euo pipefail

# Use a Keychain profile locally, or a team App Store Connect API key in CI.
auth=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    auth=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
        auth+=(--keychain "$NOTARY_KEYCHAIN")
    fi
elif [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    [[ -f "$NOTARY_KEY_PATH" ]] || { echo "Notary API key file does not exist." >&2; exit 1; }
    auth=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
    echo "Set NOTARY_KEYCHAIN_PROFILE, or NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID." >&2
    exit 1
fi

# Release builds check configuration before spending time compiling.
if [[ "${1:-}" == "--check-credentials" ]]; then
    exit 0
fi
app=${1:-build/Focusman.app}
[[ -d "$app" ]] || { echo "App bundle not found: $app" >&2; exit 1; }
codesign --verify --strict "$app"
signature=$(codesign -d --verbose=2 "$app" 2>&1)
case "$signature" in
    *"Authority=Developer ID Application:"*) ;;
    *) echo "Notarization requires Developer ID Application signing." >&2; exit 1 ;;
esac

report_root=${NOTARY_REPORT_DIR:-build/notarization}
mkdir -p "$report_root"
report_dir=$(mktemp -d "$report_root/submission.XXXXXX")
archive="$report_dir/Focusman.zip"
response="$report_dir/response.json"
ditto -c -k --keepParent "$app" "$archive"
echo "Submitting Focusman to Apple; results will be saved in $report_dir"
submit_result=0
xcrun notarytool submit "$archive" "${auth[@]}" --wait \
    --timeout "${NOTARY_TIMEOUT:-30m}" --output-format json > "$response" || submit_result=$?
status=$(plutil -extract status raw -o - "$response" 2>/dev/null) || status=Unknown
submission_id=$(plutil -extract id raw -o - "$response" 2>/dev/null) || submission_id=

# Do not rely on the command's exit code alone: Apple can return a rejected status.
if [[ "$submit_result" != 0 || "$status" != Accepted ]]; then
    echo "Notarization did not succeed (status: $status). See $response" >&2
    if [[ -n "$submission_id" ]]; then
        echo "Submission ID: $submission_id" >&2
        if xcrun notarytool log "$submission_id" "${auth[@]}" "$report_dir/log.json"; then
            cat "$report_dir/log.json" >&2
        fi
    fi
    exit 1
fi

xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --strict "$app"
echo "Focusman is notarized and stapled."
