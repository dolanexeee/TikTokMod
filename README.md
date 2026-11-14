# TikTokMod

Native Objective-C dylib mod for decrypted **TikTok 47.7.0**
(bundle `com.zhiliaoapp.musically`, arm64).

- One dylib, one in-app settings hub (`TikTokModHub`), 41 feature toggles (45-feature list)
  (`TikTokModSettings`, persisted in NSUserDefaults suite
  `com.tiktokmod.settings`).
- Toggles are dictionary-backed and keyed by feature ID: adding one is a
  single line in the `+allFeatures` registry in `TikTokModSettings.m`.
- #45 Custom Background (his own request): toggle + picker row in the hub —
  image via UIImagePickerController (stored as JPEG under Documents/TikTokMod/)
  or color as a hex string; overlay application is a stub until research lands.
- NOT toggles: #11 (Android bugfix), #12 (maintenance note), #19
  (Android-only offline limit); #15 OTA updates merges into #41.
- Server-side-caution toggles (comment reposts, 9-image comments, hashtag
  limit, repost character limit, send/pin limits) are marked UNVERIFIED in
  the hub — the server may still enforce them; never present them as working.
- Hooks use ObjC runtime method swizzling, feature-gated and fail-soft:
  a missing class/selector is a no-op with an `NSLog`, never a crash.
- Base IPA is **not** in this repo. The dylib is injected into a decrypted
  TikTok 47.7.0 IPA at assembly time (cyan), then re-signed by the user.

## Status

Skeleton (B1): the dylib builds in CI, logs `TikTokMod loaded` on load,
and presents the hub. **No real TikTok hooks yet** — toggles are stubs
pending the class-map research (R1/R2).

## Safety

- **Test on a secondary account only.** TikTok detects modified clients.
- **Series unlock is impossible and not attempted.** Series purchase state
  is server-side; the mod only ever *hides* Series rows. Never claim otherwise.

## Build

GitHub Actions (`.github/workflows/build-dylib.yml`) builds
`TikTokMod.dylib` on macOS-latest with `xcodebuild` and uploads it as an
artifact. See `BUILD-LOG.md` in `~/workspace/projects/tiktok-mod/` for the
verified run.
