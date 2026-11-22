# Brave DeBloater

A small Windows GUI tool to disable Brave browser bloatware and features via
registry policies, plus Secure DNS (DNS-over-HTTPS) settings.

Built with [Nim](https://nim-lang.org/) and the Win32 API — no dependencies,
no installer, just a single executable.

## Features

- **27 toggles** for Brave features, telemetry, privacy protections and
  Shields defaults
- **Secure DNS** configuration: off, automatic, or DNS-over-HTTPS with
  Cloudflare, Google, Quad9, AdGuard, NextDNS, or a custom template
- Hover tooltips explaining each setting
- Reads and writes both HKLM and HKCU, so your settings stay visible whether
  the app runs as administrator or not
- Revert any setting to restore Brave's defaults

## Usage

1. Run `bravedebloater.exe`. Run as administrator to apply settings for all
   users (HKLM); otherwise settings apply to the current user (HKCU).
2. Check the features you want to disable/enforce, then click **Apply checked**.
3. To undo, check the rows and click **Revert checked**, or use **Revert all**
   to clear everything the app manages.
4. Fully restart Brave for policies to take effect. Verify them at
   `brave://policy`.

Policies are mandatory while set: Brave won't let you change those settings
in its UI. Revert a policy to give control back to the user.

## Build

Requires Nim >= 2.0.0, [winim](https://github.com/khchen/winim) >= 4.0.0 and
MinGW-w64.

```
nimble install winim
windres -i bravedebloater.rc -o bravedebloater.res --input-format=rc --output-format=coff
nim c -d:release src/main.nim
```

The resulting `bin/bravedebloater.exe` is self-contained with the app icon
embedded.

## License

MIT
