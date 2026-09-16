# Focusman

Dims every window except the one you're working in.
Menu bar only, no dock icon, built with AppKit.

## Build

```sh
make run        # build, bundle, launch
make install    # copy to /Applications
```

Requires Swift 5.9+ and macOS 13+. No Accessibility permission is required.

## CLI

The CLI is included at `Focusman.app/Contents/Resources/focusman`, so copying the
app also carries the CLI. After `make bundle`, run from the project directory:

```sh
./build/focusman --quit-on-background-click
./build/focusman --help
```

`build/focusman` is a convenience symlink to the bundled CLI. From inside `build`,
use `./focusman --quit-on-background-click`. You can also run it directly:

```sh
./build/Focusman.app/Contents/Resources/focusman --quit-on-background-click
```
The command runs Focusman until it quits. A left, right, or middle click on the dimmed
background quits immediately and consumes the click, so it does not activate or
click the window underneath. Clicks inside the active window work normally.
This session keeps only the active window lit, temporarily ignoring the saved
“All windows” mode and app exclusions. Saved preferences are unchanged.
The option applies only to this launch; `./build/focusman` starts normal click-through
mode. Quit an existing copy before launching a new session.

Only visible dimming intercepts clicks: disabled dimming, zero intensity, and paused
full-screen dimming leave clicks alone. The Dock, undimmed menu bar, and floating
panels remain above the dim layer and behave normally.

To install the app and a `focusman` command in `~/.local/bin`:

```sh
make install-cli
```

This links `~/.local/bin/focusman` to the CLI inside `/Applications/Focusman.app`.
Include `~/.local/bin` in your shell's `PATH`, or set `CLI_DIR` when installing.
If you installed the app by copying it to Applications, create the link directly:

```sh
mkdir -p "$HOME/.local/bin"
ln -sfn /Applications/Focusman.app/Contents/Resources/focusman "$HOME/.local/bin/focusman"
```

## Releases with GoReleaser

`.goreleaser.yaml` uses GoReleaser OSS v2 (validated with v2.18.1). Run on macOS
with Xcode and its command-line tools installed. The release hook builds a
universal app for Apple Silicon and Intel using Swift, then GoReleaser packages
`Focusman.app` (including its CLI) and this README into
`Focusman_<version>_macOS_universal.zip` and generates `checksums.txt` in `dist/`.
The app's version fields are set from the numeric part of the Git tag before signing.

From a Git checkout with a commit and an `origin` remote:

```sh
goreleaser check
goreleaser release --snapshot --clean
```

Snapshot mode builds local artifacts without publishing. GoReleaser requires a
Git checkout with an `origin` remote. No repository owner is hardcoded:
GoReleaser uses the remote.

For a release, run `goreleaser release --clean --timeout 45m` from a clean checkout of a pushed
semantic-version tag such as `v0.1.0`, with `GITHUB_TOKEN` set to a token allowed
to create releases in that repository. Prerelease tags are marked automatically.

Release builds automatically sign with the CosmoCows Developer ID, submit to
Apple, wait for acceptance, staple and validate the ticket, then create the final
ZIP and checksums. Rejection, submission errors, and stapling failures stop the
release before publication. Snapshot builds skip notarization unless
`NOTARIZE_SNAPSHOT=1` is set. `SIGN_IDENTITY` can override the release identity;
ordinary `make bundle` builds still default to ad-hoc signing.

### Local notarization setup

The signing certificate and its private key must be in your Keychain. Store the
CosmoCows Apple account's notarization credentials once:

```sh
xcrun notarytool store-credentials focusman \
  --apple-id YOUR_APPLE_ID --team-id 68RP9D4Z9J
```

Enter an Apple app-specific password at the secure prompt. Then test the complete
release process without publishing:

```sh
export NOTARY_KEYCHAIN_PROFILE=focusman
NOTARIZE_SNAPSHOT=1 goreleaser release --snapshot --clean --timeout 45m
```

For a tagged release, run `goreleaser release --clean --timeout 45m` with the same
profile and `GITHUB_TOKEN`. To notarize an already-signed app without rebuilding,
use `NOTARY_KEYCHAIN_PROFILE=focusman make notarize`.

`NOTARY_KEYCHAIN` optionally selects a particular keychain. As an alternative to
a profile, supply a team App Store Connect API key through `NOTARY_KEY_PATH`
(the `.p8` file), `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`.

Submission responses and rejection logs are saved in `build/notarization/`.
Waiting times out after 30 minutes by default (`NOTARY_TIMEOUT` can override it).
Apple may continue processing a timed-out submission; use its recorded ID with
`xcrun notarytool info` or `wait` and your credentials to inspect it.

### GitHub Actions

`.github/workflows/release.yml` runs the complete release on a macOS runner when
a `v*` tag is pushed. Add these repository or organization Actions secrets:

| Secret | Value |
|---|---|
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 of the exported CosmoCows Developer ID Application certificate **and private key**, in a password-protected `.p12` file |
| `APPLE_CERTIFICATE_PASSWORD` | Password for that `.p12` file |
| `APPLE_NOTARY_KEY_P8` | Contents of a CosmoCows team App Store Connect API private key (`.p8`) |
| `APPLE_NOTARY_KEY_ID` | The API key ID |
| `APPLE_NOTARY_ISSUER_ID` | The API key's issuer ID |

GitHub supplies `GITHUB_TOKEN`. The workflow imports the certificate into a
temporary keychain, materializes the API key only on the runner, and removes both
after the job. Credentials belong in Actions secrets, not in the repository.
Configure these secrets before pushing the first release tag. See Apple's
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
and GitHub's [certificate setup](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
for the account and certificate prerequisites.

The configuration uses GoReleaser's [global hooks](https://goreleaser.com/customization/general/hooks/)
and [file-only archives](https://goreleaser.com/customization/package/archives/),
so it does not require a Go module or a GoReleaser Pro license.

## How it works

There is one borderless `NSPanel` per display, filled with translucent black.
It sits at the normal window level, immediately behind the active window using
`order(.below, relativeTo:)`. macOS composites the active window's actual shape,
corners, transparency, and shadow above the dim layer; no estimated cutout is
needed for that window. The Dock, menu bar, and floating panels remain above it.
The optional menu-bar dimming uses separate narrow panels above the menu bar.

“All windows of front app” and “Never dim” still use rounded cutouts for additional
windows behind the panel. Their corner radius remains an approximation, controlled
by the `cornerRadius` default. If there is no active window but excluded windows
exist, the panel uses the original floating-level cutout behavior.

The panel is `.nonactivatingPanel` and returns `false` from `canBecomeKey`, so
it never steals keyboard focus. Normally `ignoresMouseEvents = true` lets clicks
pass through. The CLI dismissal mode instead consumes mouse-down events on the
dim panels and terminates Focusman. `sharingType = .none` keeps the dim out of screenshots and screen
shares, which matters if you present.

Geometry comes from `CGWindowListCopyWindowInfo`, filtered to `kCGWindowLayer == 0`.
Worth knowing: window **bounds and owner pid are readable without any
permission**. Focusman does not read window titles or use Accessibility APIs.

Window tracking uses app notifications and polling:

| Event | Source |
|---|---|
| Front app changed | `NSWorkspace.didActivateApplicationNotification` |
| Window moved / resized / focus changed within an app | 4 Hz window-list poll |
| Drag in progress | 60 Hz poll, armed by a global mouse-down monitor |

The idle fallback poll runs at 4 Hz and reasserts panel ordering even when window
bounds are unchanged. Window IDs distinguish same-sized windows in the same
position. Focusman excludes its own panels from window selection.

## Caveats and rough edges

- **Additional-window cutouts.** Only the active window uses exact native layering.
  Background windows kept lit by app mode or exclusions still use an approximate
  11pt radius (`cornerRadius` in defaults).
- **Floating panels stay lit.** Floating windows sit above the normal-level dim
  panel, including panels owned by other apps.
- **Ordering transitions.** App activation and Space changes reassert ordering;
  the fallback poll catches changes within the same app within approximately
  250 ms. Movement of the active window needs no cutout updates.
- **Full-screen windows.** A full-screen window matches the display frame
  exactly, so `skipFullScreen` detects it by size and disables dimming. There's
  no public API for "is this window in a full-screen Space".
- **Multi-monitor.** One overlay per display, ordered behind the active window. If you'd rather dim by display than by window, drop
  the mask on the non-active screens entirely.

## Possible next steps

- Gaussian blur instead of a solid fill: swap `dimLayer.backgroundColor` for a
  `CABackdropLayer` (private) or an `NSVisualEffectView` with a dark material.
- A colored border around the active window — cheap to add, just a second
  `CAShapeLayer` stroking the hole path.
- Per-display intensity, and a lower intensity for the app's non-front windows
  so you get three brightness tiers rather than two.
- Launch at login via `SMAppService.mainApp.register()`.

## Tests

Run `swift test` in a logged-in macOS desktop session with another app window open.
The ordering test checks the actual WindowServer order against another process.

Release-script tests use mocked Apple tools and never upload an app:

```sh
python3 -m unittest discover -s Tests/ReleaseTests -v
```
