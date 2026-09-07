# Intel-compatible Vorssaint update workflow

Run these steps from the repository root on the Intel Mac.

## 1. Inspect the checkout and remotes

```sh
git status --short
git branch --show-current
git remote -v
git log -3 --oneline --decorate
```

Do not overwrite, stash, or discard existing work. Confirm the intended fork is `origin` and that the working tree is clean before integrating a release.

## 2. Confirm and fetch the upstream release

```sh
git ls-remote https://github.com/vorssaint/vorssaint-utils.git \
  'refs/tags/v<VERSION>' 'refs/tags/v<VERSION>^{}'
git fetch --no-tags https://github.com/vorssaint/vorssaint-utils.git \
  'refs/tags/v<VERSION>:refs/remotes/upstream/v<VERSION>'
```

Use the upstream release tag as the source of the new application features. Inspect its release metadata and DMG checksum before deciding whether the official artifact is safe to install.

## 3. Integrate without losing Intel support

Keep the current Intel compatibility delta separate from the upstream release delta. The build and source must continue to provide:

- Native host-architecture detection, including `x86_64` on Intel Macs.
- Explicit Intel builds with `VORSSAINT_TARGET=x86_64-apple-macosx14.0`.
- Sequoia SDK selection and SDK-based guards for newer macOS APIs.
- Intel AppleSMC temperature families (`TC…` CPU and `TG…`/`Tg…` GPU).
- Updater architecture validation that rejects an ARM-only bundle on Intel.
- Universal release output when `VORSSAINT_UNIVERSAL=1` is used.

For a dirty-tree-safe integration, create a temporary detached worktree at the upstream tag and apply only the local compatibility delta with a three-way patch. Resolve overlaps in favor of both the upstream feature and the Intel guard, then transfer the resolved tree back to the main checkout. Remove the temporary worktree after the transfer.

## 4. Run source checks and tests

```sh
zsh -n build.sh
git diff --check
VORSSAINT_TARGET=x86_64-apple-macosx14.0 \
  VORSSAINT_BUILD_JOBS=8 ./build.sh --test
```

The test command must pass the complete suite and preference-cleanup checks.

## 5. Build the Intel app

```sh
VORSSAINT_TARGET=x86_64-apple-macosx14.0 \
  VORSSAINT_BUILD_JOBS=8 ./build.sh
./build/Vorssaint --selftest
codesign --verify --deep --strict build/stage/Vorssaint.app
```

Verify the main app and embedded helper binaries before installation:

```sh
file build/stage/Vorssaint.app/Contents/MacOS/Vorssaint
lipo -archs build/stage/Vorssaint.app/Contents/MacOS/Vorssaint
lipo -archs build/stage/Vorssaint.app/Contents/Library/LaunchServices/com.vorssaint.utils.fan-control
lipo -archs build/stage/Vorssaint.app/Contents/Frameworks/libVorssaintNowPlaying.dylib
```

Every local Intel build must report `x86_64` and the app self-test must print `SELFTEST OK`.

## 6. Commit and push the source update

Review the complete staged diff and recent commit style before committing. Stage only the release, compatibility, documentation, and test files belonging to this update.

```sh
git add -u
git add steps.md <any new upstream source or test files>
git diff --cached --check
git diff --cached --stat
git commit -m "$(cat <<'EOF'
Integrate <VERSION> with Intel Sequoia compatibility

Bring the upstream release into the fork while preserving native Intel builds and updater architecture checks.

🤖 Generated with Codebuff
Co-Authored-By: Codebuff <noreply@codebuff.com>
EOF
)"
git push origin main
```

Confirm that `origin/main` points to the new commit after pushing.

## 7. Install the exact committed build locally

Stop the running app, replace `/Applications/Vorssaint.app` with the verified `build/stage/Vorssaint.app`, clear copied quarantine metadata, verify the signature, and launch:

```sh
pkill -f '/Applications/Vorssaint.app/Contents/MacOS/Vorssaint' || true
rm -rf /Applications/Vorssaint.app
ditto --noextattr --noqtn build/stage/Vorssaint.app /Applications/Vorssaint.app
xattr -c -r /Applications/Vorssaint.app 2>/dev/null || true
codesign --verify --deep --strict /Applications/Vorssaint.app
open -a /Applications/Vorssaint.app
```

Direct installation is used only when the normal installer wrapper stalls during its signature-finalization wait; the bundle must already have passed all build and signature checks.

## 8. Verify the installed copy

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  /Applications/Vorssaint.app/Contents/Info.plist
lipo -archs /Applications/Vorssaint.app/Contents/MacOS/Vorssaint
codesign --verify --deep --strict /Applications/Vorssaint.app
/Applications/Vorssaint.app/Contents/MacOS/Vorssaint --selftest
pgrep -f '/Applications/Vorssaint.app/Contents/MacOS/Vorssaint'
git status --short
```

The installed version must match `<VERSION>`, the executable must include `x86_64`, the signature and self-test must pass, the process must be running, and the source working tree should be clean after the commit.
