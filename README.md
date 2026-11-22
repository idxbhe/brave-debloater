# Brave DeBloater

A small, dependency-light Windows GUI tool to toggle Brave browser
bloatware/feature policies through the Windows registry, plus Secure DNS
(DNS-over-HTTPS) settings.

Written in [Nim](https://nim-lang.org/) using the raw Win32 API via
[winim](https://github.com/khchen/winim) — no external GUI toolkit.

## What it does

Brave (like all Chromium browsers) reads managed policies from the registry.
This tool writes and removes those values — nothing else. It does **not**
patch Brave binaries or modify `Preferences` / `Local State` JSON files.

Policy target key:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave   (preferred)
HKEY_CURRENT_USER\SOFTWARE\Policies\BraveSoftware\Brave    (fallback)
```

- When launched as administrator, policies are written to **HKLM**
  (machine-wide, mandatory for all users).
- Otherwise it falls back to **HKCU** (per-user).
- The app always **reads both** HKLM and HKCU (HKLM wins, matching Chromium's
  mandatory-over-recommended precedence), so policies you set in one
  elevation context are still shown as active when the app is reopened in the
  other. Each row's State column shows `(HKLM)` or `(HKCU)` so you can see
  where a value lives.
- Reverting removes the value from both roots (HKLM removal requires
  elevation).

### Feature toggles (27 policies)

| Group | Policies |
|---|---|
| Brave features (disable) | Rewards, Wallet, News, VPN, Talk, AI Chat (Leo), Playlist, Speedreader, Wayback Machine, IPFS, Email Aliases, Tor windows, Local AI, Password Manager |
| Telemetry & tracking (disable) | stats ping, P3A, Web Discovery |
| Privacy hardening (enable) | De-AMP, Debouncing, Reduce Language, Global Privacy Control, tracking query parameter filtering |
| Shields defaults (enforce) | block ads, fingerprinting protection, HTTPS-first strict, strict referrers, forget first-party storage |

Each row shows the exact registry value name and its current state
(`Not set` / `Set` / `Other`). Hover the mouse over any row to see a tooltip
with a short description of what that policy does. Reverting deletes the value
so Brave falls back to its built-in default and the user regains control.

### Secure DNS (DNS-over-HTTPS)

Sets `DnsOverHttpsMode` (`off` / `automatic` / `secure`) and
`DnsOverHttpsTemplates` in the same policy key. Provider presets:
Cloudflare, Google, Quad9, AdGuard, NextDNS (append your config ID), or a
custom template URL.

## Requirements

- Nim >= 2.0.0
- winim >= 4.0.0 (`nimble install winim`)
- MinGW-w64 (GCC) toolchain on PATH

## Build

```
windres -i bravedebloater.rc -o bravedebloater.res --input-format=rc --output-format=coff
nim c -d:release src/main.nim
```

The first command compiles the multi-resolution icon (`bravedebloater.ico`,
16×16 through 256×256) into a Win32 resource. The settings in `src/nim.cfg`
then embed that resource into the binary and switch the PE subsystem to
Windows, producing a single self-contained `bin/bravedebloater.exe` with no
console window and the correct app icon in Explorer and the title bar.

## Usage

1. Run the exe. For machine-wide (HKLM) policies, run it as administrator.
2. Check the features you want to enforce, then **Apply checked**.
3. To undo, check rows and click **Revert checked**, or use **Revert all**
   to remove every policy this tool manages (including Secure DNS).
4. Restart Brave (fully exit from the tray) for policies to take effect.
   You can verify what Brave sees at `brave://policy`.

## Notes

- Policies are mandatory: when set, they override user settings and cannot
  be changed from within Brave. Revert a policy to hand control back to the
  user.
- The tool only manages the values listed above; it never deletes the
  policy key itself or values it did not write.
- Run as the same user account that uses the browser when relying on the
  HKCU fallback.

## Releasing

Pushing a tag like `v1.2.0` triggers `.github/workflows/release.yml`, which
builds the Windows x64 binary, packages it, and publishes a GitHub Release.

You can also run the workflow manually from the Actions tab: enter a version
(e.g. `1.2.0`) and it will bump the version in `bravedebloater.nimble`, commit
and tag it, then publish the release. The `GITHUB_TOKEN` needs write access
(repository default is sufficient).

## License

MIT
